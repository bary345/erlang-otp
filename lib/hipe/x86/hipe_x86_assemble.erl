%%% -*- erlang-indent-level: 2 -*-
%%% $Id$
%%% HiPE/x86 assembler
%%%
%%% TODO:
%%% - Migrate old resolve_arg users to translate_src/dst.
%%% - Simplify combine_label_maps and mk_data_relocs.
%%% - Move find_const to hipe_pack_constants?

-module(hipe_x86_assemble).
-export([assemble/4]).

-define(DEBUG,true).

-include("../main/hipe.hrl").
-include("hipe_x86.hrl").
-include("../../kernel/src/hipe_ext_format.hrl").
-include("../rtl/hipe_literals.hrl").
-include("../misc/hipe_sdi.hrl").

assemble(CompiledCode, Closures, Exports, Flags) ->
  ?when_option(time, Flags, ?start_timer("x86 assembler")),
  put(hipe_x86_flags,Flags),
  print("****************** Assembling *******************\n"),
  %%
  Code = [{MFA,
	   hipe_x86:defun_code(Defun),
	   hipe_x86:defun_data(Defun)}
	  || {MFA, Defun} <- CompiledCode],
  %%
  {ConstAlign,ConstSize,ConstMap,RefsFromConsts} =
    hipe_pack_constants:pack_constants(Code, hipe_x86_registers:alignment()),
  %%
  {CodeSize,AccCode,AccRefs,LabelMap,ExportMap} =
    encode(translate(Code, ConstMap)),
  CodeBinary = mk_code_binary(AccCode),
  print("Total num bytes=~w\n",[CodeSize]),
  put(code_size, CodeSize),
  put(const_size, ConstSize),
  ?when_option(verbose, Flags,
	       ?debug_msg("Constants are ~w bytes\n",[ConstSize])),
  %%
  SC = hipe_pack_constants:slim_constmap(ConstMap),
  DataRelocs = mk_data_relocs(RefsFromConsts, LabelMap),
  SSE = slim_sorted_exportmap(ExportMap,Closures,Exports),
  SlimRefs = hipe_pack_constants:slim_refs(AccRefs),
  Bin = term_to_binary([{?VERSION(),?HIPE_SYSTEM_CRC},
			ConstAlign, ConstSize,
			SC,
			DataRelocs, % nee LM, LabelMap
			SSE,
			CodeSize,CodeBinary,SlimRefs,
			0,[] % ColdCodeSize, SlimColdRefs
		       ]),
  %%
  ?when_option(time, Flags, ?stop_timer("x86 assembler")),
  Bin.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mk_code_binary(AccCode) ->
  Size = hipe_bifs:array_length(AccCode),
  list_to_binary(array_to_bytes(AccCode, Size, [])).

array_to_bytes(Array, I1, Bytes) ->
  I2 = I1 - 1,
  if I2 < 0 ->
      Bytes;
     true ->
      %% 'band 255' to fix up negative bytes (from disp8 operands?)
      Byte = hipe_bifs:array_sub(Array, I2) band 255,
      array_to_bytes(Array, I2, [Byte|Bytes])
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%
%%% Assembly Pass 1.
%%% Process initial {MFA,Code,Data} list.
%%% Translate each MFA's body, choosing operand & instruction kinds.
%%%
%%% Assembly Pass 2.
%%% Perform short/long form optimisation for jumps.
%%% Build LabelMap for each MFA.
%%%
%%% Result is {MFA,NewCode,CodeSize,LabelMap} list.
%%%

translate(Code, ConstMap) ->
  translate_mfas(Code, ConstMap, []).

translate_mfas([{MFA,Insns,_Data}|Code], ConstMap, NewCode) ->
  {NewInsns,CodeSize,LabelMap} =
    translate_insns(Insns, MFA, ConstMap, hipe_sdi:pass1_init(), 0, []),
  translate_mfas(Code, ConstMap, [{MFA,NewInsns,CodeSize,LabelMap}|NewCode]);
translate_mfas([], _ConstMap, NewCode) ->
  lists:reverse(NewCode).

translate_insns([I|Insns], MFA, ConstMap, SdiPass1, Address, NewInsns) ->
  NewIs = translate_insn(I, MFA, ConstMap),
  add_insns(NewIs, Insns, MFA, ConstMap, SdiPass1, Address, NewInsns);
translate_insns([], _MFA, _ConstMap, SdiPass1, Address, NewInsns) ->
  {LabelMap,CodeSizeIncr} = hipe_sdi:pass2(SdiPass1),
  {lists:reverse(NewInsns), Address+CodeSizeIncr, LabelMap}.

add_insns([I|Is], Insns, MFA, ConstMap, SdiPass1, Address, NewInsns) ->
  NewSdiPass1 =
    case I of
      {'.label',L,_} ->
	hipe_sdi:pass1_add_label(SdiPass1, Address, L);
      {jcc_sdi,{_,{label,L}},_} ->
	SdiInfo = #sdi_info{incr=(6-2),lb=(-128)+2,ub=127+2},
	hipe_sdi:pass1_add_sdi(SdiPass1, Address, L, SdiInfo);
      {jmp_sdi,{{label,L}},_} ->
	SdiInfo = #sdi_info{incr=(5-2),lb=(-128)+2,ub=127+2},
	hipe_sdi:pass1_add_sdi(SdiPass1, Address, L, SdiInfo);
      _ ->
	SdiPass1
    end,
  Address1 = Address + insn_size(I),
  add_insns(Is, Insns, MFA, ConstMap, NewSdiPass1, Address1, [I|NewInsns]);
add_insns([], Insns, MFA, ConstMap, SdiPass1, Address, NewInsns) ->
  translate_insns(Insns, MFA, ConstMap, SdiPass1, Address, NewInsns).

insn_size(I) ->
  case I of
    {'.label',_,_} -> 0;
    {'.sdesc',_,_} -> 0;
    {jcc_sdi,_,_} -> 2;
    {jmp_sdi,_,_} -> 2;
    {Op,Arg,_Orig} -> hipe_x86_encode:insn_sizeof(Op, Arg)
  end.

translate_insn(I, MFA, ConstMap) ->
  case I of
    #alu{} ->
      Arg = resolve_alu_args(hipe_x86:alu_src(I), hipe_x86:alu_dst(I)),
      [{hipe_x86:alu_op(I), Arg, I}];
    #call{} ->
      translate_call(I);
    #cmovcc{} ->
      {Dst,Src} = resolve_move_args(hipe_x86:cmovcc_src(I), hipe_x86:cmovcc_dst(I),
				    {MFA,ConstMap}),
      CC = {cc,hipe_x86_encode:cc(hipe_x86:cmovcc_cc(I))},
      Arg = {CC,Dst,Src},
      [{cmovcc, Arg, I}];
    #cmp{} ->
      Arg = resolve_alu_args(hipe_x86:cmp_src(I), hipe_x86:cmp_dst(I)),
      [{cmp, Arg, I}];
    #comment{} ->
      [];
    #dec{} ->
      Arg = translate_dst(hipe_x86:dec_dst(I)),
      [{dec, {Arg}, I}];
    #fp_binop{} ->
      Arg = resolve_fp_binop_args(hipe_x86:fp_binop_src(I),
				  hipe_x86:fp_binop_dst(I)),
      [{hipe_x86:fp_binop_op(I), Arg, I}];
    #fp_unop{} ->
      Arg = resolve_fp_unop_arg(hipe_x86:fp_unop_arg(I)),
      [{hipe_x86:fp_unop_op(I), Arg, I}];
    #inc{} ->
      Arg = translate_dst(hipe_x86:inc_dst(I)),
      [{inc, {Arg}, I}];
    #jcc{} ->
      Cc = {cc,hipe_x86_encode:cc(hipe_x86:jcc_cc(I))},
      Label = translate_label(hipe_x86:jcc_label(I)),
      [{jcc_sdi, {Cc,Label}, I}];
    #jmp_fun{} ->
      %% call and jmp are patched the same, so no need to distinguish
      %% call from tailcall
      PatchTypeExt =
	case hipe_x86:jmp_fun_linkage(I) of
	  remote -> ?PATCH_TYPE2EXT(call_remote);
	  not_remote -> ?PATCH_TYPE2EXT(call_local)
	end,
      Arg = translate_fun(hipe_x86:jmp_fun_fun(I), PatchTypeExt),
      [{jmp, {Arg}, I}];
    #jmp_label{} ->
      Arg = translate_label(hipe_x86:jmp_label_label(I)),
      [{jmp_sdi, {Arg}, I}];
    #jmp_switch{} ->
      RM32 = resolve_jmp_switch_arg(I, {MFA,ConstMap}),
      [{jmp, {RM32}, I}];
    #label{} ->
      [{'.label', hipe_x86:label_label(I), I}];
    #lea{} ->
      Arg = resolve_lea_args(hipe_x86:lea_mem(I), hipe_x86:lea_temp(I)),
      [{lea, Arg, I}];
    #move{} ->
      Arg = resolve_move_args(hipe_x86:move_src(I), hipe_x86:move_dst(I),
			      {MFA,ConstMap}),
      [{mov, Arg, I}];
    #movsx{} ->
      Arg = resolve_movx_args(hipe_x86:movsx_src(I), hipe_x86:movsx_dst(I)),
      [{movsx, Arg, I}];
    #movzx{} ->
      Arg = resolve_movx_args(hipe_x86:movzx_src(I), hipe_x86:movzx_dst(I)),
      [{movzx, Arg, I}];
    %% nop: we shouldn't have any as input
    #prefix_fs{} ->
      [{prefix_fs, {}, I}];
    %% pseudo_call: eliminated before assembly
    %% pseudo_jcc: eliminated before assembly
    %% pseudo_tailcall: eliminated before assembly
    %% pseudo_tailcall_prepare: eliminated before assembly
    #pop{} ->
      Arg = translate_dst(hipe_x86:pop_dst(I)),
      [{pop, {Arg}, I}];
    #push{} ->
      Arg = translate_src(hipe_x86:push_src(I), MFA, ConstMap),
      [{push, {Arg}, I}];
    #ret{} ->
      translate_ret(I);
    #shift{} ->
      Arg = resolve_shift_args(hipe_x86:shift_src(I), hipe_x86:shift_dst(I)),
      [{hipe_x86:shift_op(I), Arg, I}];
    #test{} ->
      Arg = resolve_test_args(hipe_x86:test_src(I), hipe_x86:test_dst(I)),
      [{test, Arg, I}]
  end.

-ifdef(X86_SIMULATE_NSP).

translate_call(I) ->
  WordSize = 4, % XXX: s/4/8/ if AMD64
  RegSP = 2#100, % esp
  TempSP = hipe_x86:mk_temp(RegSP, untagged),
  FunOrig = hipe_x86:call_fun(I),
  Fun =
    case FunOrig of
      #x86_mem{base=#x86_temp{reg=4}, off=#x86_imm{value=Off}} ->
	FunOrig#x86_mem{off=#x86_imm{value=Off+WordSize}};
      _ -> FunOrig
    end,
  PatchTypeExt =
    case hipe_x86:call_linkage(I) of
      remote -> ?PATCH_TYPE2EXT(call_remote);
      not_remote -> ?PATCH_TYPE2EXT(call_local)
    end,
  JmpArg = translate_fun(Fun, PatchTypeExt),
  I3 = {'.sdesc', hipe_x86:call_sdesc(I), #comment{term=sdesc}},
  I2 = {jmp, {JmpArg}, #comment{term=call}},
  Size2 = hipe_x86_encode:insn_sizeof(jmp, {JmpArg}),
  I1 = {mov, {mem_to_rm32(hipe_x86:mk_mem(TempSP,
					  hipe_x86:mk_imm(0),
					  untagged)),
	      {imm32,{?PATCH_TYPE2EXT(x86_abs_pcrel),4+Size2}}},
	#comment{term=call}},
  I0 = {sub, {temp_to_rm32(TempSP), {imm8,WordSize}}, I},
  [I0,I1,I2,I3].

translate_ret(I) ->
  NPOP = hipe_x86:ret_npop(I) + 4, % XXX: s/4/8/ if AMD64
  RegSP = 2#100, % esp
  TempSP = hipe_x86:mk_temp(RegSP, untagged),
  RegRA = 2#011, % ebx
  TempRA = hipe_x86:mk_temp(RegRA, untagged),
  [{mov,
    {temp_to_reg32(TempRA),
     mem_to_rm32(hipe_x86:mk_mem(TempSP,
				 hipe_x86:mk_imm(0),
				 untagged))},
    I},
   {add,
    {temp_to_rm32(TempSP),
     case NPOP < 128 of
       true -> {imm8,NPOP};
       false -> {imm32,NPOP}
     end},
    #comment{term=ret}},
   {jmp,
    {temp_to_rm32(TempRA)},
    #comment{term=ret}}].

-else. % not X86_SIMULATE_NSP

translate_call(I) ->
  %% call and jmp are patched the same, so no need to distinguish
  %% call from tailcall
  PatchTypeExt =
    case hipe_x86:call_linkage(I) of
      remote -> ?PATCH_TYPE2EXT(call_remote);
      not_remote -> ?PATCH_TYPE2EXT(call_local)
    end,
  Arg = translate_fun(hipe_x86:call_fun(I), PatchTypeExt),
  SDesc = hipe_x86:call_sdesc(I),
  [{call, {Arg}, I}, {'.sdesc', SDesc, #comment{term=sdesc}}].

translate_ret(I) ->
  Arg =
    case hipe_x86:ret_npop(I) of
      0 -> {};
      N -> {{imm16,N}}
    end,
  [{ret, Arg, I}].

-endif. % X86_SIMULATE_NSP

translate_label(Label) when integer(Label) ->
  {label,Label}.	% symbolic, since offset is not yet computable

translate_fun(Arg, PatchTypeExt) ->
  case Arg of
    #x86_temp{} ->
      temp_to_rm32(Arg);
    #x86_mem{} ->
      mem_to_rm32(Arg);
    #x86_mfa{m=M,f=F,a=A} ->
      {rel32,{PatchTypeExt,{M,F,A}}};
    #x86_prim{prim=Prim} ->
      {rel32,{PatchTypeExt,Prim}}
  end.

translate_src(Src, MFA, ConstMap) ->
  case Src of
    #x86_imm{value=Imm} ->
      if is_atom(Imm) ->
	  {imm32,{?PATCH_TYPE2EXT(load_atom),Imm}};
	 is_integer(Imm) ->
	  case (Imm =< 127) and (Imm >= -128) of
	    true ->
	      {imm8,Imm};
	    false ->
	      {imm32,Imm}
	  end;
	 true ->
	  Val =
	    case Imm of
	      {Label,constant} ->
		ConstNo = find_const({MFA,Label}, ConstMap),
		{constant,ConstNo};
	      {Label,closure} ->
		{closure,Label};
	      {Label,c_const} ->
		{c_const,Label}
	    end,
	  {imm32,{?PATCH_TYPE2EXT(load_address),Val}}
      end;
    _ ->
      translate_dst(Src)
  end.

translate_dst(Dst) ->
  case Dst of
    #x86_temp{} ->
      temp_to_reg32(Dst);
    #x86_mem{type='double'} ->
      mem_to_rm64fp(Dst);
    #x86_mem{} ->
      mem_to_rm32(Dst);
    #x86_fpreg{} ->
      fpreg_to_stack(Dst)
  end.

%%%
%%% Assembly Pass 3.
%%% Process final {MFA,Code,CodeSize,LabelMap} list from pass 2.
%%% Translate to a single binary code segment.
%%% Collect relocation patches.
%%% Build ExportMap (MFA-to-address mapping).
%%% Combine LabelMaps to a single one (for mk_data_relocs/2 compatibility).
%%% Return {CombinedCodeSize,BinaryCode,Relocs,CombinedLabelMap,ExportMap}.
%%%

-undef(ASSERT).
-define(ASSERT(G), if G -> [] ; true -> exit({assertion_failed,?MODULE,?LINE,??G}) end).

encode(Code) ->
  CodeSize = compute_code_size(Code, 0),
  ExportMap = build_export_map(Code, 0, []),
  CodeArray = hipe_bifs:array(CodeSize, 0), % XXX: intarray, should have bytearray support!
  Relocs = encode_mfas(Code, 0, CodeArray, []), % updates CodeArray via side-effects
  CombinedLabelMap = combine_label_maps(Code, 0, gb_trees:empty()),
  {CodeSize,CodeArray,Relocs,CombinedLabelMap,ExportMap}.

nr_pad_bytes(Address) -> (4 - (Address rem 4)) rem 4. % XXX: 16 or 32 instead?

align_entry(Address) -> Address + nr_pad_bytes(Address).

compute_code_size([{_MFA,_Insns,CodeSize,_LabelMap}|Code], Size) ->
  compute_code_size(Code, align_entry(Size+CodeSize));
compute_code_size([], Size) -> Size.

build_export_map([{{M,F,A},_Insns,CodeSize,_LabelMap}|Code], Address, ExportMap) ->
  build_export_map(Code, align_entry(Address+CodeSize), [{Address,M,F,A}|ExportMap]);
build_export_map([], _Address, ExportMap) -> ExportMap.

combine_label_maps([{MFA,_Insns,CodeSize,LabelMap}|Code], Address, CLM) ->
  NewCLM = merge_label_map(gb_trees:to_list(LabelMap), MFA, Address, CLM),
  combine_label_maps(Code, align_entry(Address+CodeSize), NewCLM);
combine_label_maps([], _Address, CLM) -> CLM.

merge_label_map([{Label,Offset}|Rest], MFA, Address, CLM) ->
  NewCLM = gb_trees:insert({MFA,Label}, Address+Offset, CLM),
  merge_label_map(Rest, MFA, Address, NewCLM);
merge_label_map([], _MFA, _Address, CLM) -> CLM.

encode_mfas([{MFA,Insns,CodeSize,LabelMap}|Code], Address, CodeArray, Relocs) ->
  print("Generating code for:~w\n", [MFA]),
  print("Offset   | Opcode (hex)             | Instruction\n"),
  {Address1,Relocs1} = encode_insns(Insns, Address, Address, LabelMap, Relocs, CodeArray),
  ExpectedAddress = align_entry(Address + CodeSize),
  ?ASSERT(Address1 =:= ExpectedAddress),
  print("Finished.\n\n"),
  encode_mfas(Code, Address1, CodeArray, Relocs1);
encode_mfas([], _Address, _CodeArray, Relocs) -> Relocs.

encode_insns([I|Insns], Address, FunAddress, LabelMap, Relocs, CodeArray) ->
  case I of
    {'.label',L,_} ->
      LabelAddress = gb_trees:get(L, LabelMap) + FunAddress,
      ?ASSERT(Address =:= LabelAddress),	% sanity check
      print_insn(Address, [], I),
      encode_insns(Insns, Address, FunAddress, LabelMap, Relocs, CodeArray);
    {'.sdesc',SDesc,_} ->
      #x86_sdesc{exnlab=ExnLab,fsize=FSize,arity=Arity,live=Live} = SDesc,
      ExnRA =
	case ExnLab of
	  [] -> [];	% don't cons up a new one
	  ExnLab -> gb_trees:get(ExnLab, LabelMap) + FunAddress
	end,
      Reloc = {?PATCH_TYPE2EXT(sdesc),Address,
	       ?STACK_DESC(ExnRA, FSize, Arity, Live)},
      encode_insns(Insns, Address, FunAddress, LabelMap, [Reloc|Relocs], CodeArray);
    _ ->
      {Op,Arg,_} = fix_jumps(I, Address, FunAddress, LabelMap),
      {Bytes, NewRelocs} = hipe_x86_encode:insn_encode(Op, Arg, Address),
      Size = length(Bytes),
      print_insn(Address, Bytes, I),
      list_to_array(Bytes, CodeArray, Address),
      encode_insns(Insns, Address+Size, FunAddress, LabelMap, NewRelocs++Relocs, CodeArray)
  end;
encode_insns([], Address, FunAddress, LabelMap, Relocs, CodeArray) ->
  case nr_pad_bytes(Address) of
    0 ->
      {Address,Relocs};
    NrPadBytes ->	% triggers at most once per function body
      Padding = lists:duplicate(NrPadBytes, {nop,{},#comment{term=padding}}),
      encode_insns(Padding, Address, FunAddress, LabelMap, Relocs, CodeArray)
  end.

fix_jumps(I, InsnAddress, FunAddress, LabelMap) ->
  case I of
    {jcc_sdi,{CC,{label,L}},OrigI} ->
      LabelAddress = gb_trees:get(L, LabelMap) + FunAddress,
      ShortOffset = LabelAddress - (InsnAddress + 2),
      if ShortOffset >= -128, ShortOffset =< 127 ->
	  {jcc,{CC,{rel8,ShortOffset}},OrigI};
	 true ->
	  LongOffset = LabelAddress - (InsnAddress + 6),
	  {jcc,{CC,{rel32,LongOffset}},OrigI}
      end;
    {jmp_sdi,{{label,L}},OrigI} ->
      LabelAddress = gb_trees:get(L, LabelMap) + FunAddress,
      ShortOffset = LabelAddress - (InsnAddress + 2),
      if ShortOffset >= -128, ShortOffset =< 127 ->
	  {jmp,{{rel8,ShortOffset}},OrigI};
	 true ->
	  LongOffset = LabelAddress - (InsnAddress + 5),
	  {jmp,{{rel32,LongOffset}},OrigI}
      end;
    _ -> I
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

list_to_array(List, Array, Addr) ->
  lists:foldl(fun(X,I) -> hipe_bifs:array_update(Array,I,X), I+1 end, Addr, List).

fpreg_to_stack(#x86_fpreg{reg=Reg}) ->
  {fpst, Reg}.

temp_to_reg32(#x86_temp{reg=Reg}) ->
  {reg32, Reg}.
temp_to_reg16(#x86_temp{reg=Reg}) ->
  {reg16, Reg}.
temp_to_reg8(#x86_temp{reg=Reg}) ->
  {reg8, Reg}.
temp_to_rm32(#x86_temp{reg=Reg}) ->
  {rm32, hipe_x86_encode:rm_reg(Reg)}.

mem_to_ea(Mem) ->
  EA = mem_to_ea_common(Mem),
  {ea, EA}.

mem_to_rm32(Mem) ->
  EA = mem_to_ea_common(Mem),
  {rm32, hipe_x86_encode:rm_mem(EA)}.

mem_to_rm64fp(Mem) ->
  EA = mem_to_ea_common(Mem),
  {rm64fp, hipe_x86_encode:rm_mem(EA)}.

%%%%%%%%%%%%%%%%%
mem_to_rm8(Mem) ->
  EA = mem_to_ea_common(Mem),
  {rm8, hipe_x86_encode:rm_mem(EA)}.

mem_to_rm16(Mem) ->
  EA = mem_to_ea_common(Mem),
  {rm16, hipe_x86_encode:rm_mem(EA)}.
%%%%%%%%%%%%%%%%%

mem_to_ea_common(#x86_mem{base=[], off=#x86_imm{value=Off}}) ->
  hipe_x86_encode:ea_disp32(Off);
mem_to_ea_common(#x86_mem{base=#x86_temp{reg=Base}, off=#x86_imm{value=Off}}) ->
  if
    Off =:= 0 ->
      case Base of
	4 -> %esp, use SIB w/o disp8
	  SIB = hipe_x86_encode:sib(Base),
	  hipe_x86_encode:ea_sib(SIB);
	5 -> %ebp, use disp8 w/o SIB
	  hipe_x86_encode:ea_disp8_base(Off, Base);
	_ -> %neither SIB nor disp8 needed
	  hipe_x86_encode:ea_base(Base)
      end;
    Off >= -128, Off =< 127 ->
      case Base of
	4 -> %esp, must use SIB
	  SIB = hipe_x86_encode:sib(Base),
	  hipe_x86_encode:ea_disp8_sib(Off, SIB);
	_ -> %use disp8 w/o SIB
	  hipe_x86_encode:ea_disp8_base(Off, Base)
      end;
    true ->
      case Base of
	4 -> %esp, must use SIB
	  SIB = hipe_x86_encode:sib(Base),
	  hipe_x86_encode:ea_disp32_sib(Off, SIB);
	_ ->
	  hipe_x86_encode:ea_disp32_base(Off, Base)
      end
  end.

%% jmp_switch
%% Context = [] when no relocs are expected, {MFA,ConstMap} otherwise
resolve_jmp_switch_arg(I, Context) ->
  Disp32 =
    case Context of
    %%   [] ->
    %%	0;
      {MFA,ConstMap} ->
	ConstNo = find_const({MFA,hipe_x86:jmp_switch_jtab(I)}, ConstMap),
	{?PATCH_TYPE2EXT(load_address),{constant,ConstNo}}
    end,
  SINDEX = hipe_x86_encode:sindex(2, hipe_x86:temp_reg(hipe_x86:jmp_switch_temp(I))),
  EA = hipe_x86_encode:ea_disp32_sindex(Disp32, SINDEX), % this creates a SIB implicitly
  {rm32,hipe_x86_encode:rm_mem(EA)}.

%% lea reg, mem
resolve_lea_args(Src=#x86_mem{}, Dst=#x86_temp{}) ->
  {temp_to_reg32(Dst),mem_to_ea(Src)}.

%% mov mem, imm
resolve_move_args(#x86_imm{value=ImmSrc}, Dst=#x86_mem{type=Type}, Context) ->
  case Type of   % to support byte and int16 stores
    byte ->
      ByteImm = ImmSrc band 255, %to ensure that it is a bytesized imm
      {mem_to_rm8(Dst),{imm8,ByteImm}};
    _ ->
      RM32 = mem_to_rm32(Dst),
      {_,Imm} = resolve_arg(#x86_imm{value=ImmSrc}, Context),
      {RM32,{imm32,Imm}}
  end;

%% mov reg,mem
resolve_move_args(Src=#x86_mem{}, Dst=#x86_temp{}, _Context) ->
  {temp_to_reg32(Dst),mem_to_rm32(Src)};

%% mov mem,reg
resolve_move_args(Src=#x86_temp{}, Dst=#x86_mem{type=Type}, _Context) ->
  case Type of   % to support byte and int16 stores
    byte ->
      {mem_to_rm8(Dst),temp_to_reg8(Src)};
    int16 ->
      {mem_to_rm16(Dst),temp_to_reg16(Src)};
    _ ->
      {mem_to_rm32(Dst),temp_to_reg32(Src)}
  end;

%% mov reg,reg
resolve_move_args(Src=#x86_temp{}, Dst=#x86_temp{}, _Context) ->
  {temp_to_reg32(Dst),temp_to_rm32(Src)};

%% mov reg,imm
resolve_move_args(Src=#x86_imm{value=_ImmSrc}, Dst=#x86_temp{}, Context) ->
  {_,Imm} = resolve_arg(Src, Context),
  {temp_to_reg32(Dst),{imm32,Imm}}.

%%% mov{s,z}x
resolve_movx_args(Src=#x86_mem{type=Type}, Dst=#x86_temp{}) ->
  {temp_to_reg32(Dst),
   case Type of
     byte ->
       mem_to_rm8(Src);
     int16 ->
       mem_to_rm16(Src)
   end}.

%%% alu/cmp (_not_ test)
resolve_alu_args(Src, Dst) ->
  case {Src,Dst} of
    {#x86_imm{}, #x86_mem{}} ->
      {mem_to_rm32(Dst), resolve_arg(Src, [])};
    {#x86_mem{}, #x86_temp{}} ->
      {temp_to_reg32(Dst), mem_to_rm32(Src)};
    {#x86_temp{}, #x86_mem{}} ->
      {mem_to_rm32(Dst), temp_to_reg32(Src)};
    {#x86_temp{}, #x86_temp{}} ->
      {temp_to_reg32(Dst), temp_to_rm32(Src)};
    {#x86_imm{}, #x86_temp{reg=0}} -> % eax,imm
      NewSrc = resolve_arg(Src, []),
      NewDst =
	case NewSrc of
	  {imm8,_} -> temp_to_rm32(Dst);
	  {imm32,_} -> eax
	end,
      {NewDst, NewSrc};
    {#x86_imm{}, #x86_temp{}} ->
      {temp_to_rm32(Dst), resolve_arg(Src, [])}
  end.

%%% test
resolve_test_args(Src, Dst) ->
  case Src of
    #x86_imm{} -> % imm8 not allowed
      {_ImmSize,ImmValue} = resolve_arg(Src, []),
      NewDst =
	case Dst of
	  #x86_temp{reg=0} -> eax;
	  #x86_temp{} -> temp_to_rm32(Dst);
	  #x86_mem{} -> mem_to_rm32(Dst)
	end,
      {NewDst, {imm32,ImmValue}};
    #x86_temp{} ->
      NewDst =
	case Dst of
	  #x86_temp{} -> temp_to_rm32(Dst);
	  #x86_mem{} -> mem_to_rm32(Dst)
	end,
      {NewDst, temp_to_reg32(Src)}
  end.

%%% shifts
resolve_shift_args(Src, Dst) ->
  RM32 =
    case Dst of
      #x86_temp{} -> temp_to_rm32(Dst);
      #x86_mem{} -> mem_to_rm32(Dst)
    end,
  Count =
    case Src of
      #x86_imm{value=1} -> 1;
      #x86_imm{} -> resolve_arg(Src, []); % must be imm8
      #x86_temp{reg=1} -> cl	% temp must be ecx
    end,
  {RM32, Count}.

%% fp_binop mem
resolve_fp_unop_arg(Arg=#x86_mem{type=Type})->
  case Type of
    'double' -> {mem_to_rm64fp(Arg)};
    'untagged' -> {mem_to_rm32(Arg)};
    _ -> ?EXIT({fmovArgNotSupported,{Arg}})
  end;
resolve_fp_unop_arg(Arg=#x86_fpreg{}) ->
  {fpreg_to_stack(Arg)};
resolve_fp_unop_arg([]) ->
  [].

%% fp_binop mem, st(i)
resolve_fp_binop_args(Src=#x86_fpreg{}, Dst=#x86_mem{})->
  {mem_to_rm64fp(Dst),fpreg_to_stack(Src)};
%% fp_binop st(0), st(i)
resolve_fp_binop_args(Src=#x86_fpreg{}, Dst=#x86_fpreg{})->
  {fpreg_to_stack(Dst),fpreg_to_stack(Src)}.


%% return arg for encoding
%% Context=[] when no relocs are expected, {MFA,ConstMap} otherwise
resolve_arg(Arg, Context) ->
  case Arg of
    {reg32,_Reg32} ->
      Arg;
    #x86_imm{value=Imm} ->
      if is_atom(Imm) ->
	  %%print("Atom:~w added to patchlist at addr:~w - ",[Imm,Addr+BytesToImm32]),
	  {imm32,{?PATCH_TYPE2EXT(load_atom),Imm}};
	 is_integer(Imm) ->
	  case (Imm =< 127) and (Imm >= -128) of
	    true ->
	      {imm8,Imm};
	    false ->
	      {imm32,Imm}
	  end;
	 true ->
	  case Context of
	    [] ->
	      {imm32,0};
	    {MFA,ConstMap} ->
	      Val =
		case Imm of
		  {Label,constant} ->
		    ConstNo = find_const({MFA,Label}, ConstMap),
		    {constant,ConstNo};
		  {Label,closure} ->
		    {closure,Label};
		  {Label,c_const} ->
		    {c_const,Label}
		end,
	      {imm32,{?PATCH_TYPE2EXT(load_address),Val}}
	  end
      end;
    #x86_temp{} ->
      temp_to_reg32(Arg);
    %% Push uses this, and goes via ESP so the SIB byte stays...
    #x86_mem{type=Type} ->
      case Type of
	'double'-> mem_to_rm64fp(Arg);
	_ -> mem_to_rm32(Arg)
      end;
    #x86_fpreg{} ->
      fpreg_to_stack(Arg)
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mk_data_relocs(RefsFromConsts, LabelMap) ->
  lists:flatten(mk_data_relocs(RefsFromConsts, LabelMap, [])).

mk_data_relocs([{MFA,Labels} | Rest], LabelMap, Acc) ->
  Map = [case Label of
	   {L,Pos} ->
	     Offset = find({MFA,L}, LabelMap),
	     {Pos,Offset};
	   {sorted,Base,OrderedLabels} ->
	     {sorted, Base, [begin
			       Offset = find({MFA,L}, LabelMap),
			       {Order, Offset}
			     end
			     || {L,Order} <- OrderedLabels]}
	 end
	 || Label <- Labels],
  %% msg("Map: ~w Map\n",[Map]),
  mk_data_relocs(Rest, LabelMap, [Map,Acc]);
mk_data_relocs([],_,Acc) -> Acc.

find({MFA,L},LabelMap) ->
  gb_trees:get({MFA,L}, LabelMap).

slim_sorted_exportmap([{Addr,M,F,A}|Rest], Closures, Exports) ->
  IsClosure = lists:member({M,F,A}, Closures),
  IsExported = is_exported(F, A, Exports),
  [Addr,M,F,A,IsClosure,IsExported | slim_sorted_exportmap(Rest, Closures, Exports)];
slim_sorted_exportmap([],_,_) -> [].

is_exported(_F, _A, []) -> true; % XXX: kill this clause when Core is fixed
is_exported(F, A, Exports) -> lists:member({F,A}, Exports).

%%%
%%% Assembly listing support (pp_asm option).
%%%

print(String) ->
  Flags = get(hipe_x86_flags),
  ?when_option(pp_asm, Flags,io:format(String,[])).

print(String, Arglist) ->
  Flags = get(hipe_x86_flags),
  ?when_option(pp_asm, Flags,io:format(String,Arglist)).

print_insn(Address, Bytes, I) ->
  Flags = get(hipe_x86_flags),
  ?when_option(pp_asm, Flags, print_insn_2(Address, Bytes, I)).

print_insn_2(Address, Bytes, {_,_,OrigI}) ->
  print("~8.16b | ",[Address]),
  print_code_list(Bytes, 0),
  hipe_x86_pp:pp_insn(OrigI).

print_code_list([Byte|Rest], Len) ->
  print_byte(Byte),
  print_code_list(Rest, Len+1);
print_code_list([], Len) ->
  fill_spaces(24-(Len*2)),
  io:format(" | ").

print_byte(Byte) ->
  io:format("~2.16.0b", [Byte band 16#FF]).

fill_spaces(N) when N > 0 ->
  io:format(" "),
  fill_spaces(N-1);
fill_spaces(_) ->
  [].

%%%
%%% Lookup a constant in a ConstMap.
%%%

find_const({MFA,Label},[{pcm_entry,MFA,Label,ConstNo,_,_,_}|_]) ->
  ConstNo;
find_const(N,[_|R]) ->
  find_const(N,R);
find_const(C,[]) ->
  ?EXIT({constant_not_found,C}).
