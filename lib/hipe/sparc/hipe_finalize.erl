-module(hipe_finalize).

-export([straighten/2,
	 split_constants/1]).

%-ifndef(DEBUG).
%-define(DEBUG,1).
%-endif.
%-define(TIMING,true).
-include("../main/hipe.hrl").

%% hipe:compile({beam_inv_opcodes,opcode,1},[o2,time]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Makes the code possible to linearize without code duplication.
% Basic blocks are merged when possible.
%

straighten(CFG, Options) ->
  %% hipe_sparc_cfg:pp(CFG),
  case property_lists:get_bool(old_straighten, Options) of
    true ->  old_straighten(CFG);
    false ->
      {Low, High} = hipe_sparc_cfg:label_range(CFG),
      hipe_gensym:set_label(High),
      ?TIME_STMNT(Lbls = hipe_sparc_cfg:depth_first_ordering(CFG),
		  "Ordering took: ",
		  Otime),
      ?TIME_STMNT(CFG1 = straighten(Lbls,CFG,CFG,none_visited()),
		  "Straigthtening took: ",
		  STime),
      ?IF_DEBUG(hipe_sparc_cfg:pp(CFG1),true),
      NewHigh = hipe_gensym:get_label(),
      hipe_sparc_cfg:label_range_update(CFG1,{Low, NewHigh})
  end.



straighten([Lbl|Ls],CFG,NewCFG,Visited) ->
  ?debug_msg("Visiting ~w~n",[Lbl]),
  Vis0 = visit(Lbl, Visited),
  BB = hipe_sparc_cfg:bb(CFG, Lbl),
  Jmp = hipe_bb:last(BB),
  case is_cond(Jmp) of
    true ->
      %% Switch the jump so the common case is not taken
      Pred = cond_pred(Jmp),
      Jmp0 =
	if Pred >= 0.5 ->
	    %% io:format("Switching ~w~n", [Jmp]),
	    switch_cond(Jmp);
	   true ->
	    Jmp
	end,
      FallTrough = cond_false_label(Jmp0),
      Taken = cond_true_label(Jmp0),
  %%    case visited(FallTrough, Vis0) of
%%	true ->
	  %% We have to insert a goto (the falltrough is
	  %% somewhere else (or duplicate the code))
	  ?debug_msg("Need goto to ~w~n", [FallTrough]),
	  NewFT = hipe_sparc:label_create_new(),
	  NewFTName = hipe_sparc:label_name(NewFT),
	  Jmp1 = cond_false_label_update(Jmp0, NewFTName),
	  Goto = hipe_sparc:goto_create(FallTrough, []),
	  GotoBB = hipe_bb:mk_bb([Goto]),
	  CFG0 = hipe_sparc_cfg:bb_add(NewCFG, NewFTName, GotoBB),
%	false ->
%	  CFG0 = CFG,
%	  Jmp1 = Jmp0
%      end,
      NewBBCode = hipe_bb:butlast(BB) ++ [Jmp1],
      NewBB = hipe_bb:code_update(BB, NewBBCode),
      CFG1 = hipe_sparc_cfg:bb_update(CFG0, Lbl, NewBB),

      straighten(Ls, CFG, CFG1, Vis0);

    false ->
      case hipe_sparc:type(Jmp) of 
	jmp ->
	  straighten(Ls++hipe_sparc:jmp_destinations(Jmp), CFG, NewCFG, Vis0);
	_ ->
	  straighten(Ls, CFG, NewCFG, Vis0)
      end

  end;
straighten([],_,CFG,_) -> CFG.


%% --------------------------------------------------------

old_straighten(CFG) ->
  Start = hipe_sparc_cfg:start(CFG),
  {Low, High} = hipe_sparc_cfg:label_range(CFG),
  hipe_gensym:set_label(High),
  Vis = none_visited(),
  ?TIME_STMNT({CFG1, Vis0} = straighten(Start, CFG, Vis),
	      "Straghtening took: ",
	      STime),
  CFG2 = 
    hipe_sparc_cfg:label_range_update(CFG1, {Low,hipe_gensym:get_label()}),
  CFG2.



straighten(Lbl, CFG, Vis) ->
  case visited(Lbl, Vis) of
    true ->
      %% io:format("Block ~w done~n", [Lbl]),
      {CFG, Vis};
    false ->
      SuccMap = hipe_sparc_cfg:succ_map(CFG),
      Succ = hipe_sparc_cfg:succ(SuccMap, Lbl),
      %% io:format("Str: ~w -> ~w~n", [Lbl, Succ]),
      case Succ of
	[] ->
	  {CFG, visit(Lbl, Vis)};
	[S] ->
	  straighten_single_succ(Lbl, S, CFG, Vis);
	_ ->
	  straighten_multiple_succ(Lbl, CFG, Vis)
      end
  end.



%
% Lbl is a basic block with a single successor (Succ), if this successors
% only predecessor is Lbl we merge the blocks.
%

straighten_single_succ(Lbl, Succ, CFG, Vis) ->
   PredMap = hipe_sparc_cfg:pred_map(CFG),
   Pred = hipe_sparc_cfg:pred(PredMap, Succ),
   %% If we duplicated code, we could accept successors with
   %% multiple predecessors.
  {CFG3, Vis3} = 
    case Pred of
      [Lbl] ->
	 %% Now we know that S got a single successor with Lbl as
	 %% it's only predecessor.
	 %% io:format("Gluing ~w to ~w~n", [Lbl, Succ]),
	 BB = hipe_sparc_cfg:bb(CFG, Lbl),
	 BBsucc = hipe_sparc_cfg:bb(CFG, Succ),
	 NewCode = hipe_bb:butlast(BB) ++ hipe_bb:code(BBsucc),
	 NewBB = hipe_bb:code_update(BB, NewCode),
	 CFG0 = hipe_sparc_cfg:bb_update(CFG, Lbl, NewBB),
	 CFG1 = hipe_sparc_cfg:bb_remove(CFG0, Succ),
	 straighten(Lbl, CFG1, Vis);
      _ ->
	 Vis0 = visit(Lbl, Vis),
	 straighten(Succ, CFG, Vis0)
   end,
   {CFG3, Vis3}.


%
% Lbl is a basic block with multiple (2?) successors.
%

straighten_multiple_succ(Lbl, CFG, Vis) ->
  BB = hipe_sparc_cfg:bb(CFG, Lbl),
  Jmp = hipe_bb:last(BB),
  case is_cond(Jmp) of
    true ->
      %% Switch the jump so the common case is not taken
      Pred = cond_pred(Jmp),
      Jmp0 =
	if Pred >= 0.5 ->
	    %% io:format("Switching ~w~n", [Jmp]),
	    switch_cond(Jmp);
	   true ->
	    Jmp
	end,
      %% The common case is now *not* taken i.e it's a fall trough
      FallTrough = cond_false_label(Jmp0),
      Taken = cond_true_label(Jmp0),
      {CFG2, Jmp2} = 
	case visited(FallTrough, Vis) of
	  true ->
	    %% We have to insert a goto (the falltrough is
	    %% somewhere else (or duplicate the code))
	    %% io:format("Need goto to ~w~n", [FallTrough]),
	    NewFT = hipe_sparc:label_create_new(),
	    NewFTName = hipe_sparc:label_name(NewFT),
	    Jmp1 = cond_false_label_update(Jmp0, NewFTName),
	    Goto = hipe_sparc:goto_create(FallTrough, []),
	    GotoBB = hipe_bb:mk_bb([Goto]),
	    CFG0 = hipe_sparc_cfg:bb_add(CFG, NewFTName, GotoBB),
	    {CFG0, Jmp1};
	  false ->
	    {CFG, Jmp0}
	end,
      NewBB = hipe_bb:code_update(BB, hipe_bb:butlast(BB)++[Jmp2]),
      CFG3 = hipe_sparc_cfg:bb_update(CFG2, Lbl, NewBB),
      Vis0 = visit(Lbl, Vis),
      {CFG4, Vis1} = straighten(FallTrough, CFG3, Vis0),
      straighten(Taken, CFG4, Vis1);
    false ->
      exit({hipe_sparc_cfg, "this is odd"})
  end.

%% ------------------------------------------------------

%
% A couple of functions that gives a common interface to 
% both b- and br- branches
%

is_cond(I) ->
   case hipe_sparc:type(I) of
      br -> true;
      b -> true;
      _ -> false
   end.


cond_pred(I) ->
   case hipe_sparc:type(I) of
      br -> hipe_sparc:br_pred(I);
      b -> hipe_sparc:b_pred(I)
   end.
   

cond_true_label(B) ->
   case hipe_sparc:type(B) of
      br -> hipe_sparc:br_true_label(B);
      b -> hipe_sparc:b_true_label(B)
   end.


cond_false_label(B) ->
   case hipe_sparc:type(B) of
      br -> hipe_sparc:br_false_label(B);
      b -> hipe_sparc:b_false_label(B)
   end.


cond_false_label_update(B, NewTrue) ->
   case hipe_sparc:type(B) of
      br -> hipe_sparc:br_false_label_update(B, NewTrue);
      b -> hipe_sparc:b_false_label_update(B, NewTrue)
   end.
  

switch_cond(B) ->
   case hipe_sparc:type(B) of
      br -> switch_br(B);
      b -> switch_b(B)
   end.


%
% Negate the cc and change the labels of a register branch
%

switch_br(B) ->
   CC = hipe_sparc:cc_negate(hipe_sparc:br_regcond(B)),
   True = hipe_sparc:br_true_label(B),
   False = hipe_sparc:br_false_label(B),
   Pred = 1 - hipe_sparc:br_pred(B),
   B0 = hipe_sparc:br_regcond_update(B, CC),
   B1 = hipe_sparc:br_true_label_update(B0, False),
   B2 = hipe_sparc:br_false_label_update(B1, True),
   hipe_sparc:br_pred_update(B2, Pred).


%
% Negate the cc and change the labels of a branch
%

switch_b(B) ->
   CC = hipe_sparc:cc_negate(hipe_sparc:b_cond(B)),
   True = hipe_sparc:b_true_label(B),
   False = hipe_sparc:b_false_label(B),
   Pred = 1 - hipe_sparc:b_pred(B),
   B0 = hipe_sparc:b_cond_update(B, CC),
   B1 = hipe_sparc:b_true_label_update(B0, False),
   B2 = hipe_sparc:b_false_label_update(B1, True),
   hipe_sparc:b_pred_update(B2, Pred).




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Does the final layout of the code and fills delay slots. After
% this pass the code can't be converted back to a CFG.
%

%finalize(CFG) ->
%   Start = hipe_sparc_cfg:start(CFG),
%   Vis = none_visited(),
%   {Vis0, NestedCode} = finalize_succ(Start, CFG, Vis),
%   AllCode = finalize_fail_entries(NestedCode, CFG,
%				   hipe_sparc_cfg:fail_entrypoints(CFG),
%				   Vis0),
%   hipe_sparc:mk_sparc(hipe_sparc_cfg:function(CFG),
%		  lists:flatten(AllCode),
%		  hipe_sparc_cfg:var_range(CFG), 
%		  hipe_sparc_cfg:label_range(CFG)).



%finalize_succ(none, CFG, Vis) ->
%   {Vis, []};
%finalize_succ(Label, CFG, Vis) ->
%   case visited(Label, Vis) of
%      true ->
%	 {Vis, []};      % already visited
%      false ->
%	 Vis0 = visit(Label, Vis),
%	 BB = hipe_sparc_cfg:bb(CFG, Label),
%	 Fallthrough = hipe_sparc_cfg:fallthrough(CFG, Label),
%	 Cond = hipe_sparc_cfg:cond(CFG, Label),
%	 %% If Label got only one successor thats not been visited we can
%	 %% remove the jump.
%	 case {Fallthrough, Cond} of
%	    {Lbl, none} when Lbl =/= none -> 
%	       case visited(Lbl, Vis0) of
%		  true -> Merge = false;
%		  false -> Merge = true
%	       end;
%	    _ -> Merge = false
%	 end,
%	 if Merge =:= true ->
%	       LblInstr = hipe_sparc:label_create(Label, hipe_bb:annot(BB)),
%	       Code = hipe_bb:butlast(BB),
%	       {Vis1, Code1} = finalize_succ(Fallthrough, CFG, Vis0),
%	       {Vis1, [[LblInstr|fill_delay(Code)], Code1]};
%	    true ->
%	       LblInstr = hipe_sparc:label_create(Label, hipe_bb:annot(BB)),
%	       Code = hipe_bb:code(BB),
%	       {Vis1, Code1} = finalize_succ(Fallthrough, CFG, Vis0),
%	       {Vis2, Code2} = finalize_succ(Cond, CFG, Vis1),
%	       {Vis2, [[LblInstr|fill_delay(Code)], Code1, Code2]}
%	 end
%   end.


%finalize_fail_entries(Code, CFG, [], Vis) ->
%   Code;
%finalize_fail_entries(Code, CFG, [E|Es], Vis) ->
%   {Vis0, MoreCode} = finalize_succ(E, CFG, Vis),
%   finalize_fail_entries([Code, MoreCode], CFG, Es, Vis0).


%
% Code is a list of instructions (from one basic block).
%

%fill_delay(Code) ->
%   Code0 = peephole(Code),
%   Codes = split_at_branch(Code0),
%   lists:map(fun fill_delay0/1, Codes).


%
% Code is a list of instructions where a branch/jump 
%

%fill_delay0(Code) ->
%   case catch find_delay(Code) of
%      no_branch ->
%	 Code;
%      {NewCode, _, _} ->
%	 [NewCode | [hipe_sparc:nop_create([])]];
%      {NewCode, Delay} ->
%	 [NewCode | [Delay]]
%   end.



%
% Extracts a delay instruction from a list 
%

%find_delay([Jmp]) ->
%   case hipe_sparc:is_any_branch(Jmp) of
%      true ->
%	 {[Jmp], 
%	  ordsets:from_list(hipe_sparc:uses(Jmp)), 
%	  ordsets:from_list(hipe_sparc:defines(Jmp))};
%      false ->
%	 throw(no_branch)
%   end;
%find_delay([I|Is]) ->
%   case find_delay(Is) of
%      {NewIs, Uses, Defs} ->
%	 IUses = ordsets:from_list(hipe_sparc:uses(I)),
%	 IDefs = ordsets:from_list(hipe_sparc:defines(I)),
%	 NewUses = ordsets:union(Uses, IUses),
%	 NewDefs = ordsets:union(Defs, IDefs),
%	 case is_delay_instr(I) of
%	    true ->
%	       %% Make sure the instruction isn't defining a reg that is 
%	       %% used later or uses a reg that is defined later or
%	       %% defines a reg that is defined later
%	       X = {ordsets:intersection(Uses, IDefs), 
%		    ordsets:intersection(Defs, IUses),
%		    ordsets:intersection(Defs, IDefs)},
%	       case X of
%		  {[], [], []} ->  %% No conflicts, found a delay instr.
%		     {NewIs, I};
%		  _ ->
%		     {[I|NewIs], NewUses, NewDefs}
%	       end;
%	    false ->
%	       {[I|NewIs], NewUses, NewDefs}
%	 end;
%      {NewIs, Delay} ->
%	 {[I|NewIs], Delay}
%   end.


%
% true if I is an instruction that can be moved to a delay slot
%
%

%is_delay_instr(I) ->
%   case hipe_sparc:type(I) of
%      comment -> false;
%      load_address -> false;
%      load_atom -> false;
%
      %% (Happi) Tests have indicated that puting loads 
      %%         in the delayslot can slow down code...
      %%         ... but it can also speed up code.
      %%         the impact is about 10 - 20 % on small bms
      %%         on the average you loose 1-2 % by not putting
      %%         loads in delayslots
      %% load -> false;
%
%      _ -> true
%   end.



%
% Split a list of instructions to a list of lists of instructions
% Where each sublist ends with a branch.
%

%split_at_branch([]) ->
%   [];
%split_at_branch([I]) ->
%   [[I]];
%split_at_branch([I|Is]) ->
%   case hipe_sparc:is_any_branch(I) of
%      true ->
%	 [[I] | split_at_branch(Is)];
%      false ->
%	 [Same|Lists] = split_at_branch(Is),
%	 [[I|Same]|Lists]
%   end.


%
% 
%

%peephole([]) ->
%   [];
%peephole([I|Is]) ->
%   case hipe_sparc:type(I) of
%      move ->
%	 case hipe_sparc:move_src(I) =:= hipe_sparc:move_dest(I) of
%	    true ->
%	       peephole(Is);
%	    false ->
%	       [I | peephole(Is)]
%	 end;
%      _ ->
%	 [I | peephole(Is)]
%   end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


none_visited() ->
   hipe_hash:empty().

visit(X, Vis) -> 
   hipe_hash:update(X, visited, Vis).

visited(X, Vis) ->
   case hipe_hash:lookup(X, Vis) of
      not_found -> false;
      {found,_} -> true
   end.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Replaces big immediates with registers that are defined with
% a 'sethi' and an 'or'. 
%
% NEWSFLASH! This also checks if arg1 to an alu operation is an immediate
% and rectifies that situation.
%
% NEWSFLASH! 990823
% This also checks if the source of a store operation is an immediate
% and rectifies that situation.
%

split_constants(CFG) ->
  Labels = hipe_sparc_cfg:labels(CFG),
  {Low, High} = hipe_sparc_cfg:var_range(CFG),
  ?ASSERT(begin
	    Code = hipe_sparc:sparc_code(hipe_sparc_cfg:linearize(CFG)),
	    RMax = hipe_sparc:highest_reg(Code),
	    RMax =< High
	  end),
  hipe_gensym:set_var(High+1),
  NewCFG = split_bbs(Labels, CFG),
  hipe_sparc_cfg:var_range_update(NewCFG, {Low, hipe_gensym:get_var()}).


split_bbs([], CFG) ->
   CFG;
split_bbs([Lbl|Lbls], CFG) ->
   BB = hipe_sparc_cfg:bb(CFG, Lbl),
   Code = hipe_bb:code(BB),
   case split_instrs(Code, [], unchanged) of
      unchanged ->
	 split_bbs(Lbls, CFG);
      NewCode ->
	 NewCFG = hipe_sparc_cfg:bb_update(CFG, Lbl, hipe_bb:code_update(BB,NewCode)),
	 split_bbs(Lbls, NewCFG)
   end.


split_instrs([], RevCode, unchanged) ->
   unchanged;
split_instrs([], RevCode, changed) ->
   lists:reverse(RevCode);
split_instrs([I0|Is], RevCode, Status) ->
  case fix_addressing_mode(I0) of
      unchanged ->
	 case split_instr(I0) of
	    unchanged ->
	       split_instrs(Is, [I0|RevCode], Status);
	    NewCode ->
	       split_instrs(Is, NewCode++RevCode, changed)
	 end;
      NewCode ->
	 split_instrs(NewCode++Is, RevCode, changed)
   end.


%
% Ensure that correct addressing modes are used.
%
fix_addressing_mode(I) ->
  case hipe_sparc:type(I) of
     alu ->
      Src1 = hipe_sparc:alu_src1(I),
      Src2 = hipe_sparc:alu_src2(I),
      case {hipe_sparc:is_imm(Src1),hipe_sparc:is_imm(Src2),
	    is_commutative(hipe_sparc:alu_operator(I))} of
	{true,false,true} ->
	  I0 = hipe_sparc:alu_src1_update(I, Src2),
	  [hipe_sparc:alu_src2_update(I0, Src1)];
	{true,_,_} ->
	  Tmp = hipe_sparc:mk_new_reg(),
	  Mov = hipe_sparc:move_create(Tmp, Src1, []),
	  NewI = hipe_sparc:alu_src1_update(I, Tmp),
	  [Mov, NewI];
	_ ->
	  unchanged
      end;
    alu_cc ->
       Src1 = hipe_sparc:alu_cc_src1(I),
       Src2 = hipe_sparc:alu_cc_src2(I),
	 case {hipe_sparc:is_imm(Src1),hipe_sparc:is_imm(Src2),
	       is_commutative(hipe_sparc:alu_cc_operator(I))} of
	   {true,false,true} ->
	     I0 = hipe_sparc:alu_cc_src1_update(I, Src2),
	     [hipe_sparc:alu_cc_src2_update(I0, Src1)];
	   {true,_,_} ->
	     Tmp = hipe_sparc:mk_new_reg(),
	     Mov = hipe_sparc:move_create(Tmp, Src1, []),
	     NewI = hipe_sparc:alu_cc_src1_update(I, Tmp),
	     [Mov, NewI];
	   _ ->
	     unchanged
	 end;
      load ->
	 Src0 = hipe_sparc:load_src(I),
	 Off0 = hipe_sparc:load_off(I),
	 case loadstore_operand(Src0, Off0) of
	    {Src1, Off1} ->
	       [hipe_sparc:load_off_update(hipe_sparc:load_src_update(I, Src1), Off1)];
	    NoChange -> unchanged
	 end;
      store ->
	 Dst0 = hipe_sparc:store_dest(I),
	 Off0 = hipe_sparc:store_off(I),
         Src1 = hipe_sparc:store_src(I),
         {I1, Changed} =
     	  case loadstore_operand(Dst0, Off0) of
	   {Dst1, Off1} ->
	       {hipe_sparc:store_off_update(
		  hipe_sparc:store_dest_update(I, Dst1),
		  Off1),
		true};
	    unchanged ->
	       {I, false}
	  end,
         case hipe_sparc:is_imm(Src1) of
	   true ->
	       Tmp = hipe_sparc:mk_new_reg(),
	       Mov = hipe_sparc:move_create(Tmp, Src1, []),
	       NewI = hipe_sparc:store_src_update(I1,Tmp),
	       [Mov, NewI];
	   false ->
	     if Changed == true -> [I1];
	        true -> unchanged
             end
	 end;
      %% XXX: jmp, jmp_link?
      _ -> unchanged
   end.


loadstore_operand(Opnd1, Opnd2) ->
    case hipe_sparc:is_imm(Opnd1) of
	true ->
	    case hipe_sparc:is_imm(Opnd2) of
		true ->
 		    Sum = (hipe_sparc:imm_value(Opnd1) + hipe_sparc:imm_value(Opnd2))
		          band 16#ffffffff,
		    NewOpnd2 = hipe_sparc:mk_imm(Sum),
		    NewOpnd1 = hipe_sparc:mk_reg(hipe_sparc_registers:zero()),
		    {NewOpnd1, NewOpnd2};
		false -> {Opnd2, Opnd1}
	    end;
	false -> unchanged
    end.


is_commutative(Op) ->
   case Op of
      '+' -> true;
      'or' -> true;
      'and' -> true;
      'xor' -> true;
      _ -> false
   end.


split_instr(I) ->
   Uses = hipe_sparc:imm_uses(I),
   case big_constants(Uses) of
      [] -> unchanged;
      {Code, Subst} -> [hipe_sparc:subst(I, Subst) | Code]
   end.

big_constants([]) ->
   {[], []};
big_constants([V|Vs]) ->
   C = hipe_sparc:imm_value(V),
   case is_big(C) of
      true ->
	 NewVar = hipe_sparc:mk_new_reg(),
	 Low = low10(C),
         Code = 
	  if Low =:= 0 ->
	      [hipe_sparc:sethi_create(NewVar, hipe_sparc:mk_imm(high22(C)), [])];
	    true ->	     
	      [hipe_sparc:alu_create(NewVar, NewVar, 'or', 
				     hipe_sparc:mk_imm(Low), []),
	       hipe_sparc:sethi_create(NewVar, hipe_sparc:mk_imm(high22(C)), 
				       [])]
	  end,
	 {MoreCode, MoreSubst} = big_constants(Vs),
	 {Code++MoreCode, [{V, NewVar} | MoreSubst]};
      false ->
	 big_constants(Vs)
   end.


is_big(X) ->
   if X > 4095 ->
	 true;
      X < -4096 ->
	 true;
      true ->
	 false
   end.


high22(X) -> X bsr 10.
low10(X) -> X band 16#3ff.
