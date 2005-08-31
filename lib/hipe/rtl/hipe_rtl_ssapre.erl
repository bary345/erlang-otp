%% -*- erlang-indent-level: 2 -*-
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% File        : hipe_rtl_ssapre.erl
%% Author      : He Bingwen and Fr�d�ric Haziza
%% Description : Performs Partial Redundancy Elimination on SSA form.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% $Id$
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc
%%
%% This module implements the <a href="http://cs.wheaton.edu/%7Etvandrun/writings/spessapre.pdf">Anticipation-SSAPRE algorithm</a>,
%% with several modifications for Partial Redundancy Elimination on SSA form.
%% We actually found problems in this hereabove algorithm, so
%% we implement another version with several advantages:
%% - No loop for Xsi insertions
%% - No fix point iteration for the downsafety part
%% - Safer computations for Will Be Available part
%% - Complexity of the overall algorithm is improved
%%
%% We were supposed to publish these results anyway :D
%%
%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(hipe_rtl_ssapre).
-export([rtl_ssapre/2]).

-include("../main/hipe.hrl").

%%-define(SSAPRE_DEBUG, true          ). %% When defined and true, produces debug printouts
-define(        SETS, ordsets       ). %% Which set implementation module to use
-define(         CFG, hipe_rtl_cfg  ).
-define(         RTL, hipe_rtl      ).
-define(          BB, hipe_bb       ).
-define(        ARCH, hipe_rtl_arch ).
-define(       GRAPH, digraph       ).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Records / Structures
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(xsi_link,{number}). %% Number is the index of the temporary (a Key into the Xsi Tree)
-record(temp,{key,var}).
-record(bottom,{key,var}).
-record(xsi, { inst,  %% Associated instruction
                def,   %% Hypothetical temporary variable that stores the result of the computation
                label, %% Block Label where the xsi is inserted
                opList,%% List of operands
                cba,   %%
                later, %%
                wba
               }).

  -record(pre_candidate, {alu,def}).
 -record(xsi_op,{pred,op}).

 -record(mp,{xsis,maps,preds,defs,uses,ndsSet}).
 -record(block,{type,attributes}).

 -record(eop,{expr,var,stopped_by}).
 -record(insertion,{pred,code,from}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Main function
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

rtl_ssapre(RtlSSACfg,Options) ->

  %%  io:format("~n################ Original CFG ################~n"),
  %%  hipe_rtl_cfg:pp(RtlSSACfg),


  {CFG2,XsiGraph,CFGGraph,MPs}=perform_Xsi_insertion(RtlSSACfg,Options),
  pp_debug("~n~n################ Xsi CFG ################~n",[]),pp_cfg(CFG2,XsiGraph),
  XsiList=?GRAPH:vertices(XsiGraph),
  case length(XsiList) of
    0 ->
      %% No Xsi
      ?option_time(pp_debug("~n~n################ No Xsi Inserted ################~n",[]),"RTL A-SSAPRE No Xsi inserted (skip Downsafety and Will Be Available)",Options),
      ok;
    _ ->
      pp_debug("~n############ Downsafety ##########~n",[]),
      ?option_time(perform_downsafety(MPs,CFGGraph,XsiGraph),"RTL A-SSAPRE Downsafety",Options),
      pp_debug("~n~n################ CFG Graph ################~n",[]),pp_cfggraph(CFGGraph),
      pp_debug("~n############ Will Be Available ##########~n",[]),
      ?option_time(perform_will_be_available(XsiGraph,CFGGraph,Options),"RTL A-SSAPRE WillBeAvailable",Options),
      pp_debug("~n############ No more need for the CFG Graph....Deleting...",[]),
      ?GRAPH:delete(CFGGraph)
  end,
  
  pp_debug("~n~n################ Xsi Graph ################~n",[]),pp_xsigraph(XsiGraph),
  
  pp_debug("~n############ Code Motion ##########~n",[]),
  Labels=?CFG:preorder(CFG2),
  ?option_time(FinalBloodyCFG=perform_code_motion(Labels,CFG2,XsiGraph),"RTL A-SSAPRE Code Motion",Options),
  ?GRAPH:delete(XsiGraph),
 
  %% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  io:format(standard_io,"~n~n############ SSA-Form CHECK ==> ~w~n",[hipe_rtl_ssa:check(FinalBloodyCFG)]),
  %% Do not turn on this check in general, since some CFGs contains garbage, and won't pass the test
  %% The garbage will be cleaned at the unconversion in a later pass
  %% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

  FinalBloodyCFG.

%% ##########################################################################
%% ######################## XSI INSERTION ###################################
%% ##########################################################################

perform_Xsi_insertion(Cfg,Options)->
  init_counters(), %% Init counters for Bottoms and Temps
  XsiGraph=digraph:new([cyclic,private]),
  %% Be carefull, the digraph component is NOT garbaged collected, so don't create 20 millions of instances!
  %% finds the longest depth
  %% Depth-first, preorder traversal over Basic Blocks.
  %%Labels=?CFG:reverse_postorder(Cfg), 
  Labels=?CFG:preorder(Cfg), 

  pp_debug("~n~n############# Finding definitions for computation~n~n",[]),
  ?option_time({Cfg2,XsiGraph}=find_definition_for_computations(Labels,Cfg,XsiGraph),"RTL A-SSAPRE Xsi Insertion, searching from instructions",Options),

  %% Active List creation
  GeneratorXsiList=lists:sort(?GRAPH:vertices(XsiGraph)),
  pp_debug("~n~n############# Inserted Xsis ~w",[GeneratorXsiList]),
  pp_debug("~n~n############# Finding operands~n",[]),
  ?option_time({Cfg3,XsiGraph}=find_operands(Cfg2,XsiGraph,GeneratorXsiList,0),"RTL A-SSAPRE Xsi Insertion, finding operands",Options),

  %% Creating the CFGGraph
  pp_debug("~n~n############# Creating CFG Graph",[]),
  pp_debug("~n############# Labels = ~w",[Labels]),
  CFGGraph=digraph:new([cyclic,private]),
  [StartLabel|Others]=Labels,
                                                % adding the start label as a leaf
  pp_debug("~nAdding a vertex for the start label: ~w",[StartLabel]),
  ?GRAPH:add_vertex(CFGGraph,StartLabel,#block{type=top}),
                                                % Doing the others
  ?option_time(MPs=create_cfggraph(Others,Cfg3,CFGGraph,[],[],[],XsiGraph),"RTL A-SSAPRE Xsi Insertion, creating intermediate 'SSAPRE Graph'",Options),

  %% Return the bloody collected information
  {Cfg3,XsiGraph,CFGGraph,MPs}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init_counters()->
  put({ssapre_temp,temp_count}, 0),
  put({ssapre_index,index_count}, 0).

new_bottom() ->
  V = get({ssapre_index,index_count}),
  put({ssapre_index,index_count}, V+1),
  #bottom{key=V,var=?RTL:mk_new_var()}.

new_temp() ->
  V = get({ssapre_temp,temp_count}),
  put({ssapre_temp,temp_count}, V+1),
  #temp{key=V,var=?RTL:mk_new_var()}.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

find_definition_for_computations([],Cfg,XsiGraph)->
  {Cfg,XsiGraph}; %% No more block to inspect in the depth-first order
find_definition_for_computations([Label|Rest],Cfg,XsiGraph)->
  Code=?BB:code(?CFG:bb(Cfg,Label)),
  {NewCfg,XsiGraph}=find_definition_for_computations_in_block(Label,Code,Cfg,[],XsiGraph),
  find_definition_for_computations(Rest,NewCfg,XsiGraph).

%%===========================================================================
%% Searches from instruction for one block BlockLabel. We process forward over instructions.
find_definition_for_computations_in_block(BlockLabel,[],Cfg,VisitedInstructions,XsiGraph)->
  Code=lists:reverse(VisitedInstructions),
  NewBB=?BB:mk_bb(Code),
  NewCfg=?CFG:bb_add(Cfg,BlockLabel,NewBB),
  {NewCfg,XsiGraph}; %% No more instructions to inspect in this block
find_definition_for_computations_in_block(BlockLabel,[Inst|Rest],Cfg,VisitedInstructions,XsiGraph)->

  %%  pp_debug(" Inspecting instruction: ",[]),pp_instr(Inst,nil),
  case ?RTL:type(Inst) of
    alu ->
      %% Is Inst interesting for SSAPRE? ie is Inst an arithmetic operation which doesn't deal with precoloured?
      %% Note that since we parse forward, we have no 'pre_candidate'-type so far.
      case check_definition(Inst,VisitedInstructions,BlockLabel,Cfg,XsiGraph) of
 	{def_found,Def}->
 	  %% Replacing Inst in Cfg
 	  NewInst=#pre_candidate{alu=Inst,def=Def},
 	  NewVisited=[NewInst|VisitedInstructions],
 	  %% Recurse forward over instructions, same CFG, same XsiGraph
 	  find_definition_for_computations_in_block(BlockLabel,Rest,Cfg,NewVisited,XsiGraph);

 	{merge_point,Xsi}->
          Def=Xsi#xsi.def,
    	  Key=Def#temp.key,
 	  NewInst=#pre_candidate{alu=Inst,def=Def},
          XsiLink=#xsi_link{number=Key},

          %% Adding a vertex to the Xsi Graph
          ?GRAPH:add_vertex(XsiGraph,Key,Xsi),
 	  pp_debug(" Inserting Xsi: ",[]),pp_xsi(Xsi),

          Label=Xsi#xsi.label,
          case BlockLabel==Label of
            false ->
              %% Insert the Xsi in the appropriate block
              Code=hipe_bb:code(?CFG:bb(Cfg,Label)),
              {BeforeCode,AfterCode}=split_for_xsi(lists:reverse(Code),[]),
              NewCode=BeforeCode++[XsiLink|AfterCode],
              NewBB=hipe_bb:mk_bb(NewCode),
              NewCfg=?CFG:bb_add(Cfg,Label,NewBB),
              NewVisited=[NewInst|VisitedInstructions];
            _->
              {BeforeCode,AfterCode}=split_for_xsi(VisitedInstructions,[]),
              TempVisited=BeforeCode++[XsiLink|AfterCode],
              TempVisited2=lists:reverse(TempVisited),
              NewVisited=[NewInst|TempVisited2],
              NewCfg=Cfg
          end,
          find_definition_for_computations_in_block(BlockLabel,Rest,NewCfg,NewVisited,XsiGraph)
      end;
    phi ->
      %% Here we add a sanity cleansing, since we can have a Phi instruction but one predecessor only
      %% In that case, we turn it into a move
      Preds=?CFG:pred(?CFG:pred_map(Cfg),BlockLabel),
      case length(Preds) of
 	1 ->
 	  [P]=Preds,
 	  Dst=?RTL:phi_dst(Inst),
 	  Var=?RTL:phi_arg(Inst,P),
 	  NewInst=?RTL:mk_move(Dst,Var);
 	_ ->
          %%pp_debug("~n####### DEBUG: Phi arglist: ~w",[?RTL:phi_arglist(Inst)]),
 	  NewInst=Inst
      end,
      NewVisited=[NewInst|VisitedInstructions],
      find_definition_for_computations_in_block(BlockLabel,Rest,Cfg,NewVisited,XsiGraph);
    _ ->
      %%pp_debug("~n [L~w] Not concerned with: ~w",[BlockLabel,Inst]),
      %% If the instruction is not a SSAPRE candidate, we skip it and keep on processing instructions
      %% Prepend Inst, so that we have all in reverse order. Easy to parse backwards
      find_definition_for_computations_in_block(BlockLabel,Rest,Cfg,[Inst|VisitedInstructions],XsiGraph)
  end.

%% ##############################################################################################################################
%% We have E as an expression, I has an alu (arithmetic operation),
%% And we inspect backwards the previous instructions to find a definition for E
%% Since we parse in forward order, we know that the previous SSAPRE instruction will have a definition.

check_definition(E,[],BlockLabel,Cfg,XsiGraph)->
  %% No more instructions in that block
  %% No definition found in that block
  %% Search is previous blocks
  Preds=?CFG:pred(?CFG:pred_map(Cfg),BlockLabel),
  %%  pp_debug("~n CHECKING DEFINITION  ####### Is L~w a merge block? It has ~w preds. So far E=",[BlockLabel,length(Preds)]),pp_expr(E),
  case length(Preds) of
    0 ->
      %% Entry Point
      {def_found,bottom};
    1 ->
      %% One predecessor only, we just keep looking for a definition in that block
      [P]=Preds,
      VisitedInstructions=lists:reverse(hipe_bb:code(?CFG:bb(Cfg,P))),
      check_definition(E,VisitedInstructions,P,Cfg,XsiGraph);
    _ ->
      Temp=new_temp(),
      %%It's a merge point
      OpList=[#xsi_op{pred=X}||X<-Preds],
      Xsi=#xsi{inst=E,def=Temp,label=BlockLabel,opList=OpList},
      {merge_point,Xsi} 
  end;
check_definition(E,[CC|Rest],BlockLabel,Cfg,XsiGraph) ->

  SRC1=?RTL:alu_src1(E),
  SRC2=?RTL:alu_src2(E),

  case ?RTL:type(CC) of
    alu ->
      exit({?MODULE,should_not_be_an_alu,{"Why the hell do we still have an alu???",CC}});
    pre_candidate ->
      %% C is the previous instruction
      C=CC#pre_candidate.alu,
      DST=?RTL:alu_dst(C),
      case DST==SRC1 orelse DST==SRC2 of
 	false ->
 	  case check_match(E,C) of
 	    true -> %% It's a computation of E!
 	      %% Get the dst of the alu
 	      {def_found,DST};
 	    _->
 	      check_definition(E,Rest,BlockLabel,Cfg,XsiGraph)
 	  end;
 	true ->
 	  %% Get the definition of C, since C is PRE-candidate AND has been processed before
 	  DEF=CC#pre_candidate.def,
 	  case DEF of
 	    bottom -> 
 	      %% Def(E)=bottom, STOP
 	      {def_found,bottom};
 	    _ -> 
 	      %% Emend E with this def(C)
 	      %%pp_debug("Parameters are E=~w, DST=~w, DEF=~w",[E,DST,DEF]),
 	      F=emend(E,DST,DEF),
 	      check_definition(F,Rest,BlockLabel,Cfg,XsiGraph) %% Continue the search
 	  end
      end;
    move ->
      %% It's a move, we emend E, and continue the definition search
      DST=?RTL:move_dst(CC),
      case SRC1==DST orelse SRC2==DST of
 	true ->
 	  SRC=?RTL:move_src(CC),
 	  F=emend(E,DST,SRC);
 	_ ->
 	  F=E
      end,
      check_definition(F,Rest,BlockLabel,Cfg,XsiGraph); %% Continue the search
    xsi_link ->
      {_K,Xsi}=?GRAPH:vertex(XsiGraph,CC#xsi_link.number),
      C=Xsi#xsi.inst,
      case check_match(C,E) of
 	true -> %% There is a Xsi already with a computation of E!
 	  %% fetch definition of C, and give it to E
 	  {def_found,Xsi#xsi.def};
 	_->
 	  check_definition(E,Rest,BlockLabel,Cfg,XsiGraph)
      end;
    phi -> 
      %% skip them. NOTE: Important to separate this case from the next one
      %% Should we better stop it here and return a Xsi?
      %% Since we've done the sanity cleaning, a phi should be in a merge block
      check_definition(E,Rest,BlockLabel,Cfg,XsiGraph);
    _ ->
      %% Note: the function calls or some other instructions can change the pre-coloured registers
      %% which are able to be redefined. This breaks of course the SSA form.
      %% If there is a redefinition we can give bottom to the computation, and no xsi will be inserted.
      %% (In some sens, the result of the computation is new at that point.)
      case ?ARCH:is_precoloured(SRC1) orelse ?ARCH:is_precoloured(SRC2) of
 	true ->
 	  {def_found,bottom};
 	_->
 	  DC=?RTL:defines(CC),
 	  case lists:member(SRC1,DC) orelse lists:member(SRC2,DC) of
 	    true ->
 	      {def_found,bottom};
 	    _ ->
 	      %% Orthogonal to E, we continue the search
 	      check_definition(E,Rest,BlockLabel,Cfg,XsiGraph)
 	  end
      end
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

check_match(E,C)->
  OpE=?RTL:alu_op(E),
  OpC=?RTL:alu_op(C),
  case OpE==OpC of
    false ->
      false;
    true ->
      Src1E=?RTL:alu_src1(E),
      Src2E=?RTL:alu_src2(E),
      Src1C=?RTL:alu_src1(C),
      Src2C=?RTL:alu_src2(C),
      case Src1E==Src1C of
 	true ->
 	  Src2E==Src2C;
 	false ->
 	  case Src1E==Src2C of
 	    true->
 	      Src2E==Src1C;
 	    false ->
 	      false
 	  end
      end
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% expr_is_constant(E)->
%%   is_number(?RTL:alu_src1(E)) andalso is_number(?RTL:alu_src2(E)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Must be an arithmetic operation, ie ?RTL:type(Expr) == alu
emend(Expr,S,Var) ->
  SRC1=?RTL:alu_src1(Expr),
  case SRC1==S of
    true ->
      NewExpr=?RTL:alu_src1_update(Expr,Var);
    _->
      NewExpr=Expr
  end,
  SRC2=?RTL:alu_src2(NewExpr),
  case SRC2==S of
    true ->
      NewExpr2=?RTL:alu_src2_update(NewExpr,Var);
    _ ->
      NewExpr2=NewExpr
  end,
  NewExpr2.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
split_for_xsi([],Acc)->
  {[],Acc};%%  no_xsi_no_phi_found;
split_for_xsi([I|Rest],Acc) -> %% [I|Rest] in backward order, Acc in order
  case ?RTL:type(I) of
    xsi_link ->
      BeforeCode=[I|Rest],
      {lists:reverse(BeforeCode),Acc};
    phi ->
      BeforeCode=[I|Rest],
      {lists:reverse(BeforeCode),Acc};
    _->
      split_for_xsi(Rest,[I|Acc])
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Phase 1.B : Search for operands
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

find_operands(Cfg,XsiGraph,[],_Count) ->
  {Cfg,XsiGraph};
find_operands(Cfg,XsiGraph,ActiveList,Count) ->
  {NewCfg,TempActiveList}=find_operands_for_active_list(Cfg,XsiGraph,ActiveList,[]),
  NewActiveList=lists:reverse(TempActiveList),
  pp_debug("~n################ Finding operands (iteration ~w): ~w have been introduced. Now ~w in total~n",
 	   [Count+1, length(NewActiveList),length(?GRAPH:vertices(XsiGraph))]),
  find_operands(NewCfg,XsiGraph,NewActiveList,Count+1).


find_operands_for_active_list(Cfg,_XsiGraph,[],ActiveListAcc)->
  {Cfg,ActiveListAcc};
find_operands_for_active_list(Cfg,XsiGraph,[K|Ks],ActiveListAcc) ->
  {_Key,Xsi}=?GRAPH:vertex(XsiGraph,K),
  pp_debug("~n Inspecting operands of : ~n",[]),pp_xsi(Xsi),
  Preds=?CFG:pred(?CFG:pred_map(Cfg),Xsi#xsi.label),
  {NewCfg,NewActiveListAcc}=determine_operands(Xsi,Preds,Cfg,K,XsiGraph,ActiveListAcc),
  {_Key2,Xsi2}=?GRAPH:vertex(XsiGraph,K),
  pp_debug("~n ** Final Xsi: ~n",[]),pp_xsi(Xsi2),
  pp_debug("~n #####################################################~n",[]),
  find_operands_for_active_list(NewCfg,XsiGraph,Ks,NewActiveListAcc).

determine_operands(_Xsi,[],Cfg,_K,_XsiGraph,ActiveAcc)->
  %% All operands have been determined. The CFG is not updated, only the XsiGraph
  {Cfg,ActiveAcc};
determine_operands(Xsi,[P|Ps],Cfg,K,XsiGraph,ActiveAcc) ->
  Label=Xsi#xsi.label,
  ReverseCode=lists:reverse(hipe_bb:code(?CFG:bb(Cfg,Label))),
  VisitedInstructions=get_visited_instructions(Xsi,ReverseCode),
  Res=determine_e_prime(Xsi#xsi.inst,VisitedInstructions,P,XsiGraph),

  case Res of
    operand_is_bottom ->
      NewXsi=xsi_arg_update(Xsi,P,new_bottom()),
      ?GRAPH:add_vertex(XsiGraph,K,NewXsi),
      determine_operands(NewXsi,Ps,Cfg,K,XsiGraph,ActiveAcc);
    {sharing_operand,Op} ->
      NewXsi=xsi_arg_update(Xsi,P,Op),
      ?GRAPH:add_vertex(XsiGraph,K,NewXsi),
      determine_operands(NewXsi,Ps,Cfg,K,XsiGraph,ActiveAcc);  
    {revised_expression,E_prime} ->
      pp_debug(" E' is determined : ",[]),pp_expr(E_prime),
      pp_debug(" and going along the edge L~w~n",[P]),
      %% Go along the edge P
      RevCode=lists:reverse(hipe_bb:code(?CFG:bb(Cfg,P))),
      case check_one_operand(E_prime,RevCode,P,Cfg,K,XsiGraph) of
 	{def_found,Def}->
 	  NewXsi=xsi_arg_update(Xsi,P,Def),
          ?GRAPH:add_vertex(XsiGraph,K,NewXsi),
          determine_operands(NewXsi,Ps,Cfg,K,XsiGraph,ActiveAcc);

 	{expr_found,ChildExpr}->
 	  NewXsi=xsi_arg_update(Xsi,P,ChildExpr),
          ?GRAPH:add_vertex(XsiGraph,K,NewXsi),
          determine_operands(NewXsi,Ps,Cfg,K,XsiGraph,ActiveAcc);

 	{merge_point,XsiChild}->
 	  %% Update that Xsi, give its definition as Operand for the search, and go on
          XsiChildDef=XsiChild#xsi.def,
 	  NewXsi=xsi_arg_update(Xsi,P,XsiChildDef),
          ?GRAPH:add_vertex(XsiGraph,K,NewXsi),

 	  KeyChild=XsiChildDef#temp.key,
 	  XsiChildLink=#xsi_link{number=KeyChild},
          ?GRAPH:add_vertex(XsiGraph,KeyChild,XsiChild),

 	  %% Should not be the same block !!!!!!!
 	  RCode=lists:reverse(hipe_bb:code(?CFG:bb(Cfg,XsiChild#xsi.label))),
 	  {BCode,ACode}=split_code_for_xsi(RCode,[]),

 	  NewCode=BCode++[XsiChildLink|ACode],
 	  NewBB=hipe_bb:mk_bb(NewCode),
 	  NewCfg=?CFG:bb_add(Cfg,XsiChild#xsi.label,NewBB),


 	  pp_debug(" -- ",[]),pp_arg(Xsi#xsi.def),pp_debug(" causes insertion of: ~n",[]),pp_xsi(XsiChild),
          pp_debug(" -- Adding an edge ",[]),pp_arg(Xsi#xsi.def),pp_debug(" -> ",[]),pp_arg(XsiChild#xsi.def),

          %% Adding an edge...
 	  %%?GRAPH:add_edge(XsiGraph,K,KeyChild,"family"),
          ?GRAPH:add_edge(XsiGraph,K,KeyChild),
 	  determine_operands(NewXsi,Ps,NewCfg,K,XsiGraph,[KeyChild|ActiveAcc])
      end
  end.

determine_e_prime(Expr,VisitedInstructions,Pred,XsiGraph)->
  %% MUST FETCH FROM THE XSI TREE, since Xsis are not updated yet in the CFG
  NewExpr=emend_with_phis(Expr,VisitedInstructions,Pred),
  emend_with_processed_xsis(NewExpr,VisitedInstructions,Pred,XsiGraph).

emend_with_phis(EmendedE,[],_)->
  EmendedE;
emend_with_phis(E,[I|Rest],Pred) ->
  case ?RTL:type(I) of
    phi ->
      Dst=?RTL:phi_dst(I),
      UE=?RTL:uses(E), %% Should we get SRC1 and SRC2 instead?
      case lists:member(Dst,UE) of
  	false ->
  	  emend_with_phis(E,Rest,Pred);
  	true ->
  	  NewE=emend(E,Dst,?RTL:phi_arg(I,Pred)),
  	  emend_with_phis(NewE,Rest,Pred)
      end;
    _ ->
      emend_with_phis(E,Rest,Pred)
  end.

emend_with_processed_xsis(EmendedE,[],_,_)->
  {revised_expression,EmendedE};  
emend_with_processed_xsis(E,[I|Rest],Pred,XsiGraph) ->
  case ?RTL:type(I) of
    xsi_link ->
      Key=I#xsi_link.number,
      {_KK,Xsi}=?GRAPH:vertex(XsiGraph,Key),
      Def=Xsi#xsi.def,
      UE=?RTL:uses(E), %% Should we get SRC1 and SRC2 instead?
      case lists:member(Def,UE) of
  	false ->
 	  CE=Xsi#xsi.inst,
 	  case check_match(E,CE) of
 	    true -> %% It's a computation of E!
 	      case xsi_arg(Xsi,Pred) of
 		undetermined_operand ->
 		  exit({?MODULE,check_operand_sharing,"######## �h Dear, we trusted Kostis !!!!!!!!! #############"});
 		XsiOp ->
 		  {sharing_operand,XsiOp} %% They share operands
 	      end;
 	    _->
 	      emend_with_processed_xsis(E,Rest,Pred,XsiGraph)
 	  end;
  	true ->
 	  A=xsi_arg(Xsi,Pred),
 	  %%pp_debug(" ######### xsi_arg(I:~w,Pred:~w) = ~w~n",[I,Pred,A]),
 	  case A of
 	    {bottom,_,_}->
 	      operand_is_bottom;
            #eop{}->
              NewE=emend(E,Def,A#eop.var),
  	      emend_with_processed_xsis(NewE,Rest,Pred,XsiGraph);
            %% {eop,_E,Omega,_StBy}->
            %%               NewE=emend(E,Def,Omega),
            %% 	      emend_with_processed_xsis(NewE,Rest,Pred,XsiGraph);
            undetermined_operand ->
 	      exit({?MODULE,emend_with_processed_xsis,"######## �h Dear, we trusted Kostis, again !!!!!!!!! #############"});
 	    XsiOp ->
 	      NewE=emend(E,Def,XsiOp),
 	      emend_with_processed_xsis(NewE,Rest,Pred,XsiGraph)
 	  end
      end;
    _ ->
      emend_with_processed_xsis(E,Rest,Pred,XsiGraph)
  end.

%% get_visited_instructions(Xsi,[]) ->
%%   pp_debug("~nWe don't find this xsi with def ",[]),pp_arg(Xsi#xsi.def),pp_debug(" in L~w : ",[Xsi#xsi.label]),
%%   exit({?MODULE,no_such_xsi_in_block,"We didn't find that Xsi in the block"});
get_visited_instructions(Xsi,[I|Rest]) ->
  case ?RTL:type(I) of
    xsi_link ->
      XsiDef=Xsi#xsi.def,
      Key=XsiDef#temp.key,
      case I#xsi_link.number==Key of
 	true ->
 	  Rest;
 	false ->
 	  get_visited_instructions(Xsi,Rest)
      end;
    _ ->
      get_visited_instructions(Xsi,Rest)
  end.

split_code_for_xsi([],Acc)->
  {[],Acc};
split_code_for_xsi([I|Rest],Acc)->
  case hipe_rtl:type(I) of
    xsi_link ->
      {lists:reverse([I|Rest]),Acc};
    phi ->
      {lists:reverse([I|Rest]),Acc};
    _ ->
      split_code_for_xsi(Rest,[I|Acc])
  end.

check_one_operand(E,[],BlockLabel,Cfg,XsiKey,XsiGraph)->
  %% No more instructions in that block
  %% No definition found in that block
  %% Search is previous blocks
  Preds=?CFG:pred(?CFG:pred_map(Cfg),BlockLabel),
  case length(Preds) of
    0 ->
      %% Entry Point
      {def_found,new_bottom()};
    1 ->
      %% One predecessor only, we just keep looking for a definition in that block
      [P]=Preds,
      VisitedInstructions=lists:reverse(hipe_bb:code(?CFG:bb(Cfg,P))),
      check_one_operand(E,VisitedInstructions,P,Cfg,XsiKey,XsiGraph);
    _ ->
      %% It's a merge point
      %%Temp=?RTL:mk_new_var(),
      Temp=new_temp(),
      OpList=[#xsi_op{pred=X}||X<-Preds],
      Xsi=#xsi{inst=E,def=Temp,label=BlockLabel,opList=OpList},
      {merge_point,Xsi}
  end;
check_one_operand(E,[CC|Rest],BlockLabel,Cfg,XsiKey,XsiGraph) ->

  SRC1=?RTL:alu_src1(E),
  SRC2=?RTL:alu_src2(E),

  %% C is the previous instruction
  case ?RTL:type(CC) of
    alu ->
      exit({?MODULE,should_not_be_an_alu,{"Why the hell do we still have an alu???",CC}});
    xsi ->
      exit({?MODULE,should_not_be_a_xsi,{"Why the hell do we still have a xsi???",CC}});
    pre_candidate ->
      C=CC#pre_candidate.alu,
      DST=?RTL:alu_dst(C),
      case DST==SRC1 orelse DST==SRC2 of
 	true ->
 	  %% Get the definition of C, since C is PRE-candidate AND has been processed before
 	  DEF=CC#pre_candidate.def,
 	  case DEF of
 	    bottom -> 
 	      %% Def(E)=bottom, STOP
              %% No update of the XsiGraph
 	      {def_found,new_bottom()};
 	    _->
 	      %% Simply emend
 	      F=emend(E,DST,DEF),
 	      pp_debug("~nEmendation : E= ",[]),pp_expr(E),pp_debug(" ==> E'= ",[]),pp_expr(F),pp_debug("~n",[]),
 	      check_one_operand(F,Rest,BlockLabel,Cfg,XsiKey,XsiGraph)
 	  end;
 	false ->
 	  case check_match(C,E) of
 	    true -> %% It's a computation of E!
 	      %% It should give DST and not Def
              %% No update of the XsiGraph, cuz we use DST and not Def
              %% The operand is therefore gonna be a real variable
 	      {def_found,DST};
 	    _->
 	      %% Nothing to do with E
 	      check_one_operand(E,Rest,BlockLabel,Cfg,XsiKey,XsiGraph)
 	  end
      end;
    move ->
      %% It's a move, we emend E, and continue the definition search
      DST=?RTL:move_dst(CC),
      case SRC1==DST orelse SRC2==DST of
 	true ->
 	  SRC=?RTL:move_src(CC),
 	  F=emend(E,DST,SRC),
  	  check_one_operand(F,Rest,BlockLabel,Cfg,XsiKey,XsiGraph); %% Continue the search
  	_ ->
 	  check_one_operand(E,Rest,BlockLabel,Cfg,XsiKey,XsiGraph) %% Continue the search
      end;
    xsi_link ->
      Key=CC#xsi_link.number,
      %% Is Key a family member of XsiDef ?
      {_KK,Xsi}=?GRAPH:vertex(XsiGraph,Key),
      C=Xsi#xsi.inst,
      case check_match(E,C) of
        true -> %% There is a Xsi already with a computation of E!
          %% fetch definition of C, and give it to E
          %% Must update an edge in the XsiGraph, and here, we know it's a Temp
          %% Note: this can create a loop (= a cycle of length 1)
          pp_debug(" -- Found a cycle with match: Adding an edge t~w -> t~w",[XsiKey,Key]),
          ?GRAPH:add_edge(XsiGraph,XsiKey,Key),
          {def_found,Xsi#xsi.def};
        _ ->
          case ?GRAPH:get_path(XsiGraph,Key,XsiKey) of 
            false ->
              %% Is it a loop back to itself???
              case Key==XsiKey of 
                false ->
                  check_one_operand(E,Rest,BlockLabel,Cfg,XsiKey,XsiGraph);
                _->
                  {expr_found,#eop{expr=E,var=?RTL:mk_new_var(),stopped_by=Key}}
              end;
            _ ->
              %% Returning the expression instead of looping
              %% And in case of no match
              ExprOp=#eop{expr=E,var=?RTL:mk_new_var(),stopped_by=Key},
              {expr_found,ExprOp}
          end
      end;
    phi -> %% skip them
      check_one_operand(E,Rest,BlockLabel,Cfg,XsiKey,XsiGraph);
    _ ->
      case ?ARCH:is_precoloured(SRC1) orelse ?ARCH:is_precoloured(SRC2) of
 	true ->
 	  {def_found,new_bottom()};
 	_->
 	  DC=?RTL:defines(CC),
 	  case lists:member(SRC1,DC) orelse lists:member(SRC2,DC) of
 	    true ->
 	      {def_found,new_bottom()};
 	    _ ->
 	      %% Orthogonal to E, we continue the search
 	      check_one_operand(E,Rest,BlockLabel,Cfg,XsiKey,XsiGraph)
 	  end
      end
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%  CREATTING CFGGRAPH  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

create_cfggraph([],_Cfg,CFGGraph,ToBeFactorizedAcc,MPAcc,LateEdges,_XsiGraph)->
  pp_debug("~n~n ############# PostProcessing ~n~w~n",[LateEdges]),
  post_process(LateEdges,CFGGraph),
  pp_debug("~n~n ############# Factorizing ~n~w~n",[ToBeFactorizedAcc]),
  factorize(ToBeFactorizedAcc,CFGGraph),
  MPAcc;
create_cfggraph([Label|Ls],Cfg,CFGGraph,ToBeFactorizedAcc,MPAcc,LateEdges,XsiGraph)->

  Preds=?CFG:pred(?CFG:pred_map(Cfg),Label),
  case length(Preds) of
    0 ->
      exit({?MODULE,do_not_call_on_top,{"Why the hell do we call that function on the start label???",Label}});
    1 ->
      Code=?BB:code(?CFG:bb(Cfg,Label)),
      [P]=Preds,
      Defs=get_defs_in_non_merge_block(Code,[]),
      pp_debug("~nAdding a vertex for ~w",[Label]),
      Succs=?CFG:succ(?CFG:succ_map(Cfg),Label),
      case length(Succs) of
        0 -> %% Exit point
          ?GRAPH:add_vertex(CFGGraph,Label,#block{type=exit}),
          NewToBeFactorizedAcc=ToBeFactorizedAcc;
        _ -> %% Split point
          ?GRAPH:add_vertex(CFGGraph,Label,#block{type=not_mp,attributes={P,Succs}}),
          NewToBeFactorizedAcc=[Label|ToBeFactorizedAcc]
      end,
      pp_debug("~nAdding an edge ~w -> ~w (~w)",[P,Label,Defs]),
      case ?GRAPH:add_edge(CFGGraph,P,Label,Defs) of
        {error,Reason}->
          exit({?MODULE,forget_that_for_christs_sake_bingwen_please,{"Bad edge",Reason}});
        _->
          ok
      end,
      create_cfggraph(Ls,Cfg,CFGGraph,NewToBeFactorizedAcc,MPAcc,LateEdges,XsiGraph);
    _ -> %% Merge point
      Code=?BB:code(?CFG:bb(Cfg,Label)),
      {Defs,Xsis,Maps,Uses}=get_info_in_merge_block(Code,XsiGraph,[],[],gb_trees:empty(),gb_trees:empty()),
      Attributes=#mp{preds=Preds,xsis=Xsis,defs=Defs,maps=Maps,uses=Uses},
      MergeBlock=#block{type=mp,attributes=Attributes},
      pp_debug("~nAdding a vertex for ~w with Defs= ~w",[Label,Defs]),
      ?GRAPH:add_vertex(CFGGraph,Label,MergeBlock),
      %% Add edges
      NewLateEdges=add_edges_for_mp(Preds,Label,LateEdges),
      create_cfggraph(Ls,Cfg,CFGGraph,ToBeFactorizedAcc,[Label|MPAcc],NewLateEdges,XsiGraph)
  end.

get_defs_in_non_merge_block([],Acc)->
  ?SETS:from_list(Acc);
get_defs_in_non_merge_block([Inst|Rest],Acc) ->
  case ?RTL:type(Inst) of
    pre_candidate ->
      Def=Inst#pre_candidate.def,
      case Def of
        #temp{}->
          %%        {temp,Key,_Var}->
          %%          get_defs_in_non_merge_block(Rest,[Key|Acc]);
          get_defs_in_non_merge_block(Rest,[Def#temp.key|Acc]);
 	_-> %% Real variables or bottom
 	  get_defs_in_non_merge_block(Rest,Acc)
      end;
    _  ->
      get_defs_in_non_merge_block(Rest,Acc)
  end.

get_info_in_merge_block([],_XsiGraph,Defs,Xsis,Maps,Uses)->
  {?SETS:from_list(Defs),Xsis,Maps,Uses}; %% Xsis are in backward order
get_info_in_merge_block([Inst|Rest],XsiGraph,Defs,Xsis,Maps,Uses) ->
  case ?RTL:type(Inst) of
    pre_candidate ->
      Def=Inst#pre_candidate.def,
      case Def of
        #temp{}->
          get_info_in_merge_block(Rest,XsiGraph,[Def#temp.key|Defs],Xsis,Maps,Uses);
 	_->
          get_info_in_merge_block(Rest,XsiGraph,Defs,Xsis,Maps,Uses)
      end;
    xsi_link ->
      Key=Inst#xsi_link.number,
      {_Key,Xsi}=?GRAPH:vertex(XsiGraph,Key),
      OpList=xsi_oplist(Xsi),
      {NewMaps,NewUses}=add_map_and_uses(OpList,Key,Maps,Uses),
      get_info_in_merge_block(Rest,XsiGraph,Defs,[Key|Xsis],NewMaps,NewUses);
    _  ->
      get_info_in_merge_block(Rest,XsiGraph,Defs,Xsis,Maps,Uses)
  end.

add_edges_for_mp([],_Label,LateEdges)->
  LateEdges;
add_edges_for_mp([P|Ps],Label,LateEdges)->
  add_edges_for_mp(Ps,Label,[{P,Label}|LateEdges]).

%% Doesn't do anything so far
add_map_and_uses([],_Key,Maps,Uses)->
  {Maps,Uses};
add_map_and_uses([XsiOp|Ops],Key,Maps,Uses)->
  case XsiOp#xsi_op.op of
    #bottom{}->
      case gb_trees:lookup(XsiOp,Maps) of
        {value,V}->
          Set=?SETS:add_element(Key,V);
        _->
          Set=?SETS:from_list([Key])
      end,
      NewMaps=gb_trees:enter(XsiOp,Set,Maps),
      NewUses=Uses;
    #temp{}->
      case gb_trees:lookup(XsiOp,Maps) of
        {value,V}->
          Set=?SETS:add_element(Key,V);
        _->
          Set=?SETS:from_list([Key])
      end,
      NewMaps=gb_trees:enter(XsiOp,Set,Maps),
      Pred=XsiOp#xsi_op.pred,
      OOP=XsiOp#xsi_op.op,
      case gb_trees:lookup(Pred,Uses) of
        {value,VV}->
          SSet=?SETS:add_element(OOP#temp.key,VV);
        _->
          SSet=?SETS:from_list([OOP#temp.key])
      end,
      NewUses=gb_trees:enter(Pred,SSet,Uses);
    #eop{}->
      case gb_trees:lookup(XsiOp,Maps) of
        {value,V}->
          Set=?SETS:add_element(Key,V);
        _->
          Set=?SETS:from_list([Key])
      end,
      NewMaps=gb_trees:enter(XsiOp,Set,Maps),
      Pred=XsiOp#xsi_op.pred,
      Op=XsiOp#xsi_op.op,
      case gb_trees:lookup(Pred,Uses) of
        {value,VV}->
          SSet=?SETS:add_element(Op#eop.stopped_by,VV);
        _->
          SSet=?SETS:from_list([Op#eop.stopped_by])
      end,
      NewUses=gb_trees:enter(Pred,SSet,Uses);
    _->
      NewMaps=Maps,
      NewUses=Uses
  end,
  add_map_and_uses(Ops,Key,NewMaps,NewUses).

post_process([],_CFGGraph)->ok;
post_process([E|Es],CFGGraph)->
  {Pred,Label}=E,
  {_PP,Block}=?GRAPH:vertex(CFGGraph,Label),
  Att=Block#block.attributes,
  Uses=Att#mp.uses,
  case gb_trees:lookup(Pred,Uses) of
    {value,Set}->
      SetToAdd=Set;
    _->
      SetToAdd=?SETS:new()
  end,
  %%pp_debug("~nAdding an edge ~w -> ~w (~w)",[Pred,Label,SetToAdd]),
  ?GRAPH:add_edge(CFGGraph,Pred,Label,SetToAdd),
  post_process(Es,CFGGraph).

factorize([],_CFGGraph)->ok;
factorize([P|Ps],CFGGraph)->
  [OE|OEs]=?GRAPH:out_edges(CFGGraph,P),
  %%pp_debug("~nIn_degrees ~w : ~w",[P,?GRAPH:in_degree(CFGGraph,P)]),
  [InEdge]=?GRAPH:in_edges(CFGGraph,P),
  {E,V1,V2,Label}=?GRAPH:edge(CFGGraph,InEdge),
  {_OEE,_OEV1,_OEV2,LOE}=?GRAPH:edge(CFGGraph,OE),
  List=shoot_info_upwards(OEs,LOE,CFGGraph),
  NewLabel=?SETS:union(Label,List),
  ?GRAPH:add_edge(CFGGraph,E,V1,V2,NewLabel),
  factorize(Ps,CFGGraph).

shoot_info_upwards([],Acc,_CFGGraph)->Acc;
shoot_info_upwards([E|Es],Acc,CFGGraph) ->
  {_E,_V1,_V2,Set}=?GRAPH:edge(CFGGraph,E),
  NewAcc=?SETS:intersection(Acc,Set),
  case ?SETS:size(NewAcc) of
    0 ->NewAcc;
    _ ->
      shoot_info_upwards(Es,NewAcc,CFGGraph)
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  DOWNSAFETY   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

perform_downsafety([],_G,_XsiG)->
  ok;
perform_downsafety([MP|MPs],G,XG) ->
  {V,Block}=?GRAPH:vertex(G,MP),
  NDS=?SETS:new(),
  Att=Block#block.attributes,
  Maps=Att#mp.maps,
  Defs=Att#mp.defs,
  OutEdges=?GRAPH:out_edges(G,MP),
  %%pp_debug("~n Inspection Maps : ~w",[Maps]),
  NewNDS=parse_keys(gb_trees:keys(Maps),Maps,OutEdges,G,Defs,NDS,XG),
  NewAtt=Att#mp{ndsSet=NewNDS},
  ?GRAPH:add_vertex(G,V,Block#block{attributes=NewAtt}),
  pp_debug("~n Not Downsafe at L~w: ~w",[V,NewNDS]),
  %%io:format(standard_io,"~n Not Downsafe at L~w: ~w",[V,NewNDS]),
  perform_downsafety(MPs,G,XG).

parse_keys([],_Maps,_OutEdges,_G,_Defs,NDS,_XsiG)->
  NDS;
parse_keys([M|Ms],Maps,OutEdges,G,Defs,NDS,XsiG)->
  KillerSet=gb_trees:get(M,Maps),
  %%pp_debug("~n Inspection ~w -> ~w",[M,KillerSet]),
  TempSet=?SETS:intersection(KillerSet,Defs),
  case ?SETS:size(TempSet) of
    0 ->
      NewNDS=getNDS(M,KillerSet,NDS,OutEdges,G,XsiG);
    _->
      %% One Xsi which has M as operand has killed it
      %% M is then Downsafe, and is not added to the NotDownsafeSet (NDS)
      NewNDS=NDS
  end,
  parse_keys(Ms,Maps,OutEdges,G,Defs,NewNDS,XsiG).

getNDS(_M,_KillerSet,NDS,[],_G,_XsiG)->
  NDS;
getNDS(M,KillerSet,NDS,[E|Es],G,XsiG) ->
  {_EE,_V1,_V2,Label}=?GRAPH:edge(G,E),
  Set=?SETS:intersection(KillerSet,Label),
  %%   pp_debug("~n ######## Intersection between KillerSet: ~w and Label: ~w",[KillerSet,Label]),
  %%   pp_debug("~n ######## ~w",[Set]),
  case ?SETS:size(Set) of
    0 ->
      %% M is not downsafe
      ?SETS:add_element(M,NDS);
    _ ->
      %% Try the other edges
      getNDS(M,KillerSet,NDS,Es,G,XsiG)
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  WILL BE AVAILABLE  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

perform_will_be_available(XsiGraph,CFGGraph,Options) ->
  Keys=?GRAPH:vertices(XsiGraph),
  pp_debug("~n############ Can Be Available ##########~n",[]),
  ?option_time(perform_can_be_available(Keys,XsiGraph,CFGGraph),"RTL A-SSAPRE WillBeAvailable - Compute CanBeAvailable",Options),
  pp_debug("~n############ Later ##########~n",[]),
  ?option_time(perform_later(Keys,XsiGraph),"RTL A-SSAPRE WillBeAvailable - Compute Later",Options).

perform_can_be_available([],_XsiGraph,_CFGGraph)->ok;
perform_can_be_available([Key|Keys],XsiGraph,CFGGraph)->

  {V,Xsi}=?GRAPH:vertex(XsiGraph,Key),
  case Xsi#xsi.cba of
    undefined ->
      {_VV,Block}=?GRAPH:vertex(CFGGraph,Xsi#xsi.label),
      Att=Block#block.attributes,
      NDS=Att#mp.ndsSet,
      OpList=?SETS:from_list(xsi_oplist(Xsi)),
      Set=?SETS:intersection(NDS,OpList),
      case ?SETS:size(Set) of
        0 ->
          ?GRAPH:add_vertex(XsiGraph,V,Xsi#xsi{cba=true}),
          perform_can_be_available(Keys,XsiGraph,CFGGraph);
        _ ->
          case length([X || #temp{key=X} <- ?SETS:to_list(Set)]) of
            0 ->
              ?GRAPH:add_vertex(XsiGraph,V,Xsi#xsi{cba=false}),
              ImmediateParents=?GRAPH:in_neighbours(XsiGraph,Key),
              propagate_cba(ImmediateParents,XsiGraph,Xsi#xsi.def,CFGGraph);
            _ ->
              ok
          end,
          perform_can_be_available(Keys,XsiGraph,CFGGraph)
      end;
    _ -> %% True or False => recurse
      perform_can_be_available(Keys,XsiGraph,CFGGraph)
  end.

propagate_cba([],_XG,_Def,_CFGG)->ok;
propagate_cba([IPX|IPXs],XsiGraph,XsiDef,CFGGraph)->
  {V,IPXsi}=?GRAPH:vertex(XsiGraph,IPX),
  {_VV,Block}=?GRAPH:vertex(CFGGraph,IPXsi#xsi.label),
  Att=Block#block.attributes,
  NDS=Att#mp.ndsSet,
  List=?SETS:to_list(?SETS:intersection(NDS,?SETS:from_list(xsi_oplist(IPXsi)))),
  case IPXsi#xsi.cba of
    false ->
      ok;
    _ ->
      case lists:keymember(XsiDef,#xsi_op.op,List) of
        true->
          ?GRAPH:add_vertex(XsiGraph,V,IPXsi#xsi{cba=false}),
          ImmediateParents=?GRAPH:in_neighbours(XsiGraph,IPX),
          propagate_cba(ImmediateParents,XsiGraph,IPXsi#xsi.def,CFGGraph);
        _ ->
          ok
      end
  end,
  propagate_cba(IPXs,XsiGraph,XsiDef,CFGGraph).

perform_later([],_XsiGraph)->ok;
perform_later([Key|Keys],XsiGraph) ->

  {V,Xsi}=?GRAPH:vertex(XsiGraph,Key),
  pp_debug("~n DEBUG : inspecting later of ~w (~w)~n",[Key,Xsi#xsi.later]),
  case Xsi#xsi.later of
    undefined ->
      OpList=xsi_oplist(Xsi),
      case parse_ops(OpList) of
        has_temp ->
          perform_later(Keys,XsiGraph);
        has_real ->

          case Xsi#xsi.cba of
            true ->
              ?GRAPH:add_vertex(XsiGraph,V,Xsi#xsi{later=false,wba=true});
            undefined ->
              ?GRAPH:add_vertex(XsiGraph,V,Xsi#xsi{later=false,wba=true});
            _ ->
              ?GRAPH:add_vertex(XsiGraph,V,Xsi#xsi{later=false,wba=false})
          end,
          AllParents=digraph_utils:reaching([Key],XsiGraph),
          propagate_later(AllParents,XsiGraph),
          perform_later(Keys,XsiGraph);
        _ -> %% Just contains bottoms and/or expressions
          ?GRAPH:add_vertex(XsiGraph,V,Xsi#xsi{later=true}),
          perform_later(Keys,XsiGraph)
      end;
    _ -> %% True or False => recurse
      perform_later(Keys,XsiGraph)
  end.

propagate_later([],_XG)->ok;
propagate_later([IPX|IPXs],XsiGraph)->
  {V,IPXsi}=?GRAPH:vertex(XsiGraph,IPX),
  case IPXsi#xsi.later of
    false ->ok;
    _ ->
      case IPXsi#xsi.cba of
        true ->
          ?GRAPH:add_vertex(XsiGraph,V,IPXsi#xsi{later=false,wba=true});
        undefined ->
          ?GRAPH:add_vertex(XsiGraph,V,IPXsi#xsi{later=false,wba=true});
        _ ->
          ?GRAPH:add_vertex(XsiGraph,V,IPXsi#xsi{later=false,wba=false})
      end,
      propagate_later(IPXs,XsiGraph)
  end.


parse_ops([])->
  fangpi; %% It means "fart" in chinese :D
parse_ops([Op|Ops]) ->
  case Op#xsi_op.op of
    #temp{}->
      has_temp;
    #bottom{} ->
      parse_ops(Ops);
    #eop{} ->
      parse_ops(Ops);
    _ ->
      has_real
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  CODE MOTION  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

perform_code_motion([],Cfg,_XsiG) ->
  Cfg;
perform_code_motion([L|Labels],Cfg,XsiG) ->
  Code=?BB:code(?CFG:bb(Cfg,L)),
  pp_debug("~n################  Code Motion in L~w~nCode to move: ~n",[L]),
  pp_instrs(Code,XsiG),
  NewCfg=code_motion_in_block(L,Code,Cfg,XsiG,[],[]),
  pp_debug("~n################  Code Motion successful in L~w",[L]),
  perform_code_motion(Labels,NewCfg,XsiG).

code_motion_in_block(Label,[],Cfg,_XsiG,Visited,InsertionsAcc)->
  %% Redirect, insert block, 
  %% Redirect Phis in block
  pp_debug(" ~n~n Making insertions",[]),
  {TempCfg,Code}=make_insertions(Label,InsertionsAcc,Cfg,Visited),
  %% re-create the block..
  NewBB=?BB:mk_bb(Code),
  pp_debug(" ~n~n Re-creating the block with :~n",[]),
  pp_instrs(Code,nil),
  NewCfg=?CFG:bb_add(TempCfg,Label,NewBB),
  NewCfg;
code_motion_in_block(L,[Inst|Insts],Cfg,XsiG,Visited,InsertionsAcc) ->

  pp_debug("~nInspecting Inst : ~w~n",[Inst]),
  case ?RTL:type(Inst) of
    phi ->
      code_motion_in_block(L,Insts,Cfg,XsiG,[Inst|Visited],InsertionsAcc);
    pre_candidate ->
      Def=Inst#pre_candidate.def,
      Alu=Inst#pre_candidate.alu,
      case Def of
        bottom ->
          code_motion_in_block(L,Insts,Cfg,XsiG,[Alu|Visited],InsertionsAcc);
        #temp{}->
          Key=Def#temp.key,
          {_V,Xsi}=?GRAPH:vertex(XsiG,Key),
          case Xsi#xsi.wba of
            true ->
              %% Turn into a move
              Dst=?RTL:alu_dst(Alu),
              Move=?RTL:mk_move(Dst,Def#temp.var),
              pp_instr(Inst#pre_candidate.alu,nil),pp_debug(" ==> ",[]),pp_instr(Move,nil),
              code_motion_in_block(L,Insts,Cfg,XsiG,[Move|Visited],InsertionsAcc);
            _ ->
              code_motion_in_block(L,Insts,Cfg,XsiG,[Alu|Visited],InsertionsAcc)
          end;
        _ ->
          %% Turn into a move
          Dst=?RTL:alu_dst(Alu),
          Move=?RTL:mk_move(Dst,Def),
          pp_instr(Alu,nil),pp_debug(" ==> ",[]),pp_instr(Move,nil),
          code_motion_in_block(L,Insts,Cfg,XsiG,[Move|Visited],InsertionsAcc)
      end;
    xsi_link ->
      Key=Inst#xsi_link.number,
      {_V,Xsi}=?GRAPH:vertex(XsiG,Key),      
      case Xsi#xsi.wba of
        true ->
          %% Xsi is a WBA, it might trigger insertions
          OpList=xsi_oplist(Xsi),
          pp_debug(" This Xsi is a 'Will be available'",[]),
          {NewOpList,NewInsertionsAcc}=get_insertions(OpList,[],InsertionsAcc,Visited,Xsi#xsi.inst,XsiG),
          NewXsi=xsi_oplist_update(Xsi,NewOpList),
          code_motion_in_block(L,Insts,Cfg,XsiG,[NewXsi|Visited],NewInsertionsAcc);
        _ ->
          pp_debug(" This Xsi is not a 'Will be available'",[]),
          code_motion_in_block(L,Insts,Cfg,XsiG,Visited,InsertionsAcc)
      end;
    _ ->
      code_motion_in_block(L,Insts,Cfg,XsiG,[Inst|Visited],InsertionsAcc)
  end.

get_insertions([],OpAcc,InsertionsAcc,_Visited,_Expr,_XsiG)->
  {OpAcc,InsertionsAcc};
get_insertions([XsiOp|Ops],OpAcc,InsertionsAcc,Visited,Expr,XsiG) ->

  Pred=XsiOp#xsi_op.pred,
  Op=XsiOp#xsi_op.op,
  case Op of
    #bottom{} ->
      case lists:keysearch(Pred, #insertion.pred , InsertionsAcc) of
        {value,Insertion} ->
          From=Insertion#insertion.from,
          case lists:keysearch(Op,1,From) of
            false -> 
              pp_debug("~nThere has been insertions along the edge L~w already, but not for that operand | Op=",[Pred]),pp_arg(Op),
              Dst=Op#bottom.var,
              Expr2=?RTL:alu_dst_update(Expr,Dst),
              Inst=manufacture_computation(Pred,Expr2,Visited),
              Code=Insertion#insertion.code,
              NewInsertion=Insertion#insertion{pred=Pred,from=[{Op,Dst}|From],code=[Inst|Code]},
              NewInsertionsAcc=lists:keyreplace(Pred, #insertion.pred,InsertionsAcc, NewInsertion);
            {value,{_,Val}} ->
              pp_debug("~nThere has been insertions along the edge L~w already, and for that operand too | Op=",[Pred]),pp_arg(Op),
              Dst=Val,
              NewInsertionsAcc=InsertionsAcc
          end;
        false ->
          pp_debug("~nThere has been no insertion along the edge L~w, (and not for that operand, of course)| Op=",[Pred]),pp_arg(Op),
          Dst=Op#bottom.var,
          Expr2=?RTL:alu_dst_update(Expr,Dst),
          Inst=manufacture_computation(Pred,Expr2,Visited),
          NewInsertion=#insertion{pred=Pred,from=[{Op,Dst}],code=[Inst]},
          NewInsertionsAcc=[NewInsertion|InsertionsAcc]
      end;
    #eop{} ->
      %% We treat expressions like bottoms
      %% The value must be recomputed, and therefore not available...
      case lists:keysearch(Pred, #insertion.pred , InsertionsAcc) of
        {value,Insertion} ->
          From=Insertion#insertion.from,
          case lists:keysearch(Op,1,From) of
            false -> 
              pp_debug("~nThere has been insertions along the edge L~w already, but not for that operand | Op=",[Pred]),pp_arg(Op),
              Dst=Op#eop.var,
              Expr2=?RTL:alu_dst_update(Expr,Dst),
              Inst=manufacture_computation(Pred,Expr2,Visited),
              Code=Insertion#insertion.code,
              NewInsertion=Insertion#insertion{pred=Pred,from=[{Op,Dst}|From],code=[Inst|Code]},
              NewInsertionsAcc=lists:keyreplace(Pred, #insertion.pred,InsertionsAcc, NewInsertion);
            {value,{_,Val}} ->
              pp_debug("~nThere has been insertions along the edge L~w already, and for that operand too | Op=",[Pred]),pp_arg(Op),
              Dst=Val,
              NewInsertionsAcc=InsertionsAcc
          end;
        false ->
          pp_debug("~nThere has been no insertion along the edge L~w, (and not for that operand, of course | Op=",[Pred]),pp_arg(Op),
          Dst=Op#eop.var,
          Expr2=?RTL:alu_dst_update(Expr,Dst),
          Inst=manufacture_computation(Pred,Expr2,Visited),
          NewInsertion=#insertion{pred=Pred,from=[{Op,Dst}],code=[Inst]},
          NewInsertionsAcc=[NewInsertion|InsertionsAcc]
      end;
    #temp{} ->
      case lists:keysearch(Pred, #insertion.pred , InsertionsAcc) of
        {value,Insertion} ->
          From=Insertion#insertion.from,
          case lists:keysearch(Op,1,From) of
            false -> 
              pp_debug("~nThere has been insertions along the edge L~w already, but not for that operand | Op=",[Pred]),pp_arg(Op),
              Key=Op#temp.key,
              {_V,Xsi}=?GRAPH:vertex(XsiG,Key),      
              case Xsi#xsi.wba of
                true ->
                  pp_debug("~nBut the operand is a WBA Xsi: no need for insertion",[]),
                  Dst=Op#temp.var,
                  NewInsertionsAcc=InsertionsAcc;
                _ ->
                  pp_debug("~nBut the operand is a NOT WBA Xsi: we must make an insertion",[]),
                  Dst=?RTL:mk_new_var(),
                  Expr2=?RTL:alu_dst_update(Expr,Dst),
                  Inst=manufacture_computation(Pred,Expr2,Visited),
                  Code=Insertion#insertion.code,
                  NewInsertion=Insertion#insertion{pred=Pred,from=[{Op,Dst}|From],code=[Inst|Code]},
                  NewInsertionsAcc=lists:keyreplace(Pred, #insertion.pred,InsertionsAcc, NewInsertion)
              end;
            {value,{_,Val}} ->
              pp_debug("~nThere has been insertions along the edge L~w already, and for that operand too (Op=~w)",[Pred,Op]),
              pp_debug("~nThis means, this temp is a WBA Xsi's definition",[]),
              Dst=Val,
              NewInsertionsAcc=InsertionsAcc
          end;
        false ->
          pp_debug("~nThere has been no insertion along the edge L~w, (and not for that operand, of course | Op=",[Pred]),pp_arg(Op),
          Key=Op#temp.key,
          {_V,Xsi}=?GRAPH:vertex(XsiG,Key),
          case Xsi#xsi.wba of
            true ->
              pp_debug("~nBut the operand is a WBA Xsi: no need for insertion",[]),
              Dst=Op#temp.var,
              NewInsertionsAcc=InsertionsAcc;
            _ ->
              pp_debug("~nBut the operand is a NOT WBA Xsi: we must make an insertion",[]),
              Dst=?RTL:mk_new_var(),
              Expr2=?RTL:alu_dst_update(Expr,Dst),
              Inst=manufacture_computation(Pred,Expr2,Visited),
              NewInsertion=#insertion{pred=Pred,from=[{Op,Dst}],code=[Inst]},
              NewInsertionsAcc=[NewInsertion|InsertionsAcc]
          end
      end;
    _ ->
      pp_debug("~nThe operand (Op=",[]),pp_arg(Op),pp_debug(") is a real variable, no need for insertion along L~w",[Pred]),
      Dst=Op,
      NewInsertionsAcc=InsertionsAcc
  end,
  NewXsiOp=XsiOp#xsi_op{op=Dst},
  get_insertions(Ops,[NewXsiOp|OpAcc],NewInsertionsAcc,Visited,Expr,XsiG).


manufacture_computation(_Pred,Expr,[])->
  S1=?RTL:alu_src1(Expr),
  S2=?RTL:alu_src2(Expr),
  case S1 of
    #temp{}->
      NewInst=?RTL:alu_src1_update(Expr,S1#temp.var);
    _ ->
      NewInst=Expr
  end,
  case S2 of
    #temp{}->
      NewExpr=?RTL:alu_src2_update(NewInst,S2#temp.var);
    _ ->
      NewExpr=NewInst
  end,
  pp_debug("~n Manufactured computation : ~w",[NewExpr]),
  NewExpr;
manufacture_computation(Pred,Expr,[I|Rest]) ->
  %%pp_debug("~n Expr = ~w",[Expr]),
  SRC1=?RTL:alu_src1(Expr),
  SRC2=?RTL:alu_src2(Expr),

  case ?RTL:type(I) of
    xsi_link ->
      exit({?MODULE,should_not_be_a_xsi_link,{"Why the hell do we still have a xsi link???",I}});
    xsi ->
      DST=I#xsi.def,
      Arg=xsi_arg(I,Pred),
      case DST==SRC1 of
  	true ->
          NewInst=?RTL:alu_src1_update(Expr,Arg);
  	false ->
          NewInst=Expr
      end,
      case DST==SRC2 of
        true ->
          NewExpr=?RTL:alu_src2_update(NewInst,Arg);
        _ ->
          NewExpr=NewInst
      end,
      manufacture_computation(Pred,NewExpr,Rest);
    phi ->
      DST=?RTL:phi_dst(I),
      Arg=?RTL:phi_arg(I,Pred),
      case DST==SRC1 of
  	true ->
          NewInst=?RTL:alu_src1_update(Expr,Arg);
  	false ->
          NewInst=Expr
      end,
      case DST==SRC2 of
        true ->
          NewExpr=?RTL:alu_src1_update(NewInst,Arg);
        _ ->
          NewExpr=NewInst
      end,
      manufacture_computation(Pred,NewExpr,Rest)
  end.

make_insertions(_L,[],Cfg,Visited)->
  Code=clean_xsis(Visited,[]),
  pp_debug("~nOnce the insertions finished, it returns the code : ~n",[]),
  pp_instrs(Code,nil),
  {Cfg,Code}; 
make_insertions(L,[I|Is],Cfg,Visited) ->

  CodeToInsert=I#insertion.code,
  case length(CodeToInsert) of
    0 ->
      pp_debug("~n There is nothing to insert along L~w",[I#insertion.pred]),
      make_insertions(L,Is,Cfg,Visited);
    _ ->
      pp_debug("~n There is something to insert along L~w -> L~w",[I#insertion.pred,L]),
      Pred=I#insertion.pred,
      Succs=?CFG:succ(?CFG:succ_map(Cfg),Pred),
      case length(Succs) of
        0 ->
          exit({?MODULE,pas_possible,{"Burp, Pas possible",L}});
        1 ->
          %% Add at the end of the pred
          pp_debug("~nBut L~p has one successor only",[Pred]),
          [Last|Code]=lists:reverse(?BB:code(?CFG:bb(Cfg,Pred))),
          CodeToInsertTemp=CodeToInsert++Code,
          NewCode=lists:reverse(CodeToInsertTemp)++[Last],

          pp_debug("~n Inserting in Predecessor L~p~n",[Pred]),

          NewBB=?BB:mk_bb(NewCode),
          NewCfg=?CFG:bb_add(Cfg,Pred,NewBB),
          make_insertions(L,Is,NewCfg,Visited); %% No need for redirection of Visited
        _ ->
          pp_debug("~nCritical edge",[]),
          %% Critical edge
          NewLabel=?RTL:mk_new_label(),
          NewLabelName=?RTL:label_name(NewLabel),
          %% Redirect the Phis in the Visited acc
          NewVisited=redirect_phis_and_xsis(Visited,[],Pred,NewLabelName),

          Code=lists:reverse([?RTL:mk_goto(L)|CodeToInsert]),
          BBToInsert=?BB:mk_bb(Code),

          TempCfg=?CFG:bb_add(Cfg,NewLabelName,BBToInsert),
          pp_debug("~n Inserting a new label L~p (critical edge L~p -> L~p)~n",[NewLabelName,Pred,L]),
          NewCfg=?CFG:redirect(TempCfg,Pred,L,NewLabelName), %% redirect(CFG,From,ToOld,ToNew)

          make_insertions(L,Is,NewCfg,NewVisited)
      end
  end.

redirect_phis_and_xsis([],Acc,_Old,_New)->
  lists:reverse(Acc);
redirect_phis_and_xsis([I|Rest],Acc,Old,New) ->
  case ?RTL:type(I) of
    phi ->
      pp_debug("~nRedirecting Phi from L~p to L~p",[Old,New]),
      Phi=?RTL:phi_redirect_pred(I,Old,New),
      redirect_phis_and_xsis(Rest,[Phi|Acc],Old,New);
    xsi ->
      OpList=[{Pred,Var} || #xsi_op{pred=Pred,op=Var} <- xsi_oplist(I)],
      Def=I#xsi.def,	 
      TempPhi1=?RTL:mk_phi(Def#temp.var),
      TempPhi2=?RTL:phi_arglist_update(TempPhi1,OpList),
      pp_debug("~n Xsi is turned into Phi : ~w",[TempPhi2]),
      pp_debug("~nRedirecting Phi from L~p to L~p",[Old,New]),
      Phi=?RTL:phi_redirect_pred(TempPhi2,Old,New),
      redirect_phis_and_xsis(Rest,[Phi|Acc],Old,New);
    _ ->
      redirect_phis_and_xsis(Rest,[I|Acc],Old,New)
  end.

clean_xsis([],Acc)->
  Acc;
clean_xsis([I|Rest],Acc) ->
  case ?RTL:type(I) of
    xsi ->
      OpList=[{Pred,Var} || #xsi_op{pred=Pred,op=Var} <- xsi_oplist(I)],
      Def=I#xsi.def,	 
      TempPhi=?RTL:mk_phi(Def#temp.var),
      Phi=?RTL:phi_arglist_update(TempPhi,OpList),
      pp_debug("~n Xsi is turned into Phi : ~w",[Phi]),
      clean_xsis(Rest,[Phi|Acc]);
    _ ->
      clean_xsis(Rest,[I|Acc])
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  XSI INTERFACE  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

xsi_oplist(#xsi{opList=OpList}) -> case OpList of undefined -> [];_->OpList end.
xsi_oplist_update(Xsi,NewOpList) -> Xsi#xsi{opList=NewOpList}.
xsi_arg(Xsi, Pred) ->
  case lists:keysearch(Pred, #xsi_op.pred ,xsi_oplist(Xsi)) of
    false ->
      undetermined_operand;
    {value,R} ->
      R#xsi_op.op
  end.
xsi_arg_update(Xsi,Pred,Op)->
  NewOpList=lists:keyreplace(Pred, #xsi_op.pred, xsi_oplist(Xsi), #xsi_op{pred=Pred,op=Op}),
  Xsi#xsi{opList=NewOpList}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%% PRETTY-PRINTING %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-ifndef(SSAPRE_DEBUG).

pp_debug(_,_) ->ok.
%%pp_cfg(Cfg,_)->?CFG:pp(Cfg).
pp_cfg(_,_)->ok.
pp_instr(_,_) ->ok.
pp_instrs(_,_) ->ok.
pp_expr(_)->ok.
pp_xsi(_)->ok.
pp_arg(_)->ok.
pp_xsigraph(_)->ok.
pp_cfggraph(_)->ok.
%% pp_xsigraph(G)->
%%   Vertices=lists:sort(?GRAPH:vertices(G)),
%%   io:format(standard_io, "Size of the Xsi Graph: ~w", [length(Vertices)]).
%% pp_cfggraph(G)->
%%   Vertices=lists:sort(?GRAPH:vertices(G)),
%%   io:format(standard_io, "Size of the CFG Graph: ~w", [length(Vertices)]).

-endif.
-ifdef(SSAPRE_DEBUG).

pp_debug(Str, Args) ->
  io:format(standard_io, Str, Args).

pp_cfg(Cfg,Graph)->
  Labels=?CFG:preorder(Cfg),
  pp_blocks(Labels,Cfg,Graph).

pp_blocks([],_,_) ->
  ok;
pp_blocks([L|Ls],Cfg,Graph) ->
  Code=hipe_bb:code(?CFG:bb(Cfg,L)),
  io:format(standard_io,"~n########## Label L~w~n",[L]),
  pp_instrs(Code,Graph),
  pp_blocks(Ls,Cfg,Graph).

pp_instrs([],_) ->
  ok;
pp_instrs([I|Is],Graph) ->
  pp_instr(I,Graph),
  pp_instrs(Is,Graph).

pp_xsi_link(Key,Graph)->
  {_Key,Xsi}=?GRAPH:vertex(Graph,Key),
  pp_xsi(Xsi).

pp_xsi(Xsi)->
  io:format(standard_io, "    [L~w] ", [Xsi#xsi.label]),
  A=Xsi#xsi.inst,
  io:format(standard_io, "[", []),pp_expr(A),
  io:format(standard_io, "] Xsi(", []),pp_xsi_args(xsi_oplist(Xsi)),
  io:format(standard_io, ") (", []),pp_xsi_def(Xsi#xsi.def),
  io:format(standard_io, ") cba=~w, later=~w~n", [Xsi#xsi.cba,Xsi#xsi.later]).

pp_instr(I,Graph) ->
  case ?RTL:type(I) of
    alu ->
      io:format(standard_io, "    ", []),
      pp_arg(?RTL:alu_dst(I)),
      io:format(standard_io, " <- ", []),
      pp_expr(I),
      io:format(standard_io, "~n", []);
    _ ->
      case catch ?RTL:pp_instr(standard_io, I) of
 	{'EXIT', _} -> 
 	  case ?RTL:type(I) of
 	    pre_candidate ->
 	      pp_pre(I);
 	    xsi ->
 	      pp_xsi(I);
 	    xsi_link ->
 	      pp_xsi_link(I#xsi_link.number,Graph);
 	    _->
 	      io:format(standard_io,"*** ~w ***~n", [I])
 	  end;
 	_ ->
 	  ok
      end
  end.

pp_pre(I)->
  A=I#pre_candidate.alu,
  io:format(standard_io, "    ", []),
  pp_arg(?RTL:alu_dst(A)),
  io:format(standard_io, " <- ", []),pp_expr(A),
  io:format(standard_io, " [ ", []),pp_arg(I#pre_candidate.def),
  %%io:format(standard_io, "~w", [I#pre_candidate.def]),
  io:format(standard_io, " ]~n",[]).

pp_expr(I)->
  pp_arg(?RTL:alu_src1(I)),
  io:format(standard_io, " ~w ", [?RTL:alu_op(I)]),
  pp_arg(?RTL:alu_src2(I)).

pp_arg(Arg)->
  case Arg of
    bottom ->
      io:format(standard_io, "_|_", []);
    {bottom,N,Var} ->
      io:format(standard_io, "_|_:~w (", [N]),pp_arg(Var),io:format(standard_io,")",[]);
    {temp,_N,_Var}->
      pp_xsi_def(Arg);
    {eop,Expr,Var,_StBy} ->
      io:format(standard_io,"{",[]),pp_expr(Expr),io:format(standard_io,"}(",[]),pp_arg(Var),io:format(standard_io,")",[]);
    undefined ->
      io:format(standard_io, "...", []); %%"undefined", []);
    _->
      case ?RTL:type(Arg) of
        alu->
          pp_expr(Arg);      
        _->
          ?RTL:pp_arg(standard_io, Arg)
      end
  end.

pp_args([]) ->
  ok;
pp_args(undefined) ->
  io:format(standard_io, "...,...,...", []);
pp_args([A]) ->
  pp_arg(A);
pp_args([A|As]) ->
  pp_arg(A),
  io:format(standard_io, ", ", []),
  pp_args(As).

pp_xsi_args([]) -> ok;
pp_xsi_args([XsiOp]) ->
  io:format(standard_io, "{~w| ", [XsiOp#xsi_op.pred]),
  pp_arg(XsiOp#xsi_op.op),
  io:format(standard_io, "}", []);
pp_xsi_args([XsiOp|Args]) ->
  io:format(standard_io, "{~w| ", [XsiOp#xsi_op.pred]),
  pp_arg(XsiOp#xsi_op.op),
  io:format(standard_io, "}, ", []),
  pp_xsi_args(Args);
pp_xsi_args(Args) ->
  pp_args(Args).

pp_xsi_def(Arg)->
  D=Arg#temp.key,
  V=Arg#temp.var,
  io:format(standard_io, "t~w (", [D]),pp_arg(V),io:format(standard_io,")",[]).

pp_cfggraph(G)->
  Vertices=lists:sort(?GRAPH:vertices(G)),
  io:format(standard_io, "Size of the CFG Graph: ~w ~n", [length(Vertices)]),
  pp_cfgvertex(Vertices,G).

pp_xsigraph(G)->
  Vertices=lists:sort(?GRAPH:vertices(G)),
  io:format(standard_io, "Size of the Xsi Graph: ~w ~n", [length(Vertices)]),
  pp_xsivertex(Vertices,G).

pp_xsivertex([],_G)->
  ok;
pp_xsivertex([Key|Keys],G)->
  {V,Xsi}=?GRAPH:vertex(G,Key),
  OutNeighbours=?GRAPH:out_neighbours(G,V),
  pp_debug(" ~w -> ~w",[V,OutNeighbours]),pp_xsi(Xsi),
  pp_xsivertex(Keys,G).

pp_cfgvertex([],_G)->
  ok;
pp_cfgvertex([Key|Keys],G)->
  {V,Block}=?GRAPH:vertex(G,Key),
  case Block#block.type of
    mp ->
      pp_debug("~n Block ~w's attributes: ~n",[V]),
      pp_attributes(Block),
      pp_debug("~n Block ~w's edges: ~n",[V]),
      pp_edges(G,?GRAPH:in_edges(G,Key),?GRAPH:out_edges(G,Key));
    _->
      ok
  end,
  pp_cfgvertex(Keys,G).

pp_attributes(Block)->
  Att=Block#block.attributes,
  case Att of
    undefined->
      ok;
    _ ->
      pp_debug("        Maps: ~n",[]),pp_maps(gb_trees:keys(Att#mp.maps),Att#mp.maps),
      pp_debug("        Uses: ~n",[]),pp_uses(gb_trees:keys(Att#mp.uses),Att#mp.uses),
      pp_debug("        Defs: ~w~n",[Att#mp.defs]),
      pp_debug("        Xsis: ~w~n",[Att#mp.xsis]),
      pp_debug("        NDS : ",[]),pp_nds(?SETS:to_list(Att#mp.ndsSet))
  end.

pp_maps([],_Maps)->ok;
pp_maps([K|Ks],Maps)->
  pp_debug("              ",[]),pp_arg(K#xsi_op.op),pp_debug("-> ~w~n",[?SETS:to_list(gb_trees:get(K,Maps))]),
  pp_maps(Ks,Maps).

pp_uses([],_Maps)->ok;
pp_uses([K|Ks],Maps)->
  pp_debug("              ~w -> ~w~n",[K,?SETS:to_list(gb_trees:get(K,Maps))]),
  pp_uses(Ks,Maps).

pp_nds([])->pp_debug("~n",[]);
pp_nds(undefined)->pp_debug("None",[]);
pp_nds([K])->
  pp_arg(K#xsi_op.op),pp_debug("~n",[]);
pp_nds([K|Ks])->
  pp_arg(K#xsi_op.op),pp_debug(", ",[]),
  pp_nds(Ks).

pp_edges(_G,[],[]) ->ok;
pp_edges(G,[],[OUT|OUTs])->
  {_E,V1,V2,Label}=?GRAPH:edge(G,OUT),
  pp_debug(" Out edge ~w -> ~w (~w)~n",[V1,V2,?SETS:to_list(Label)]),
  pp_edges(G,[],OUTs);
pp_edges(G,[IN|INs],Outs)->
  {_E,V1,V2,Label}=?GRAPH:edge(G,IN),
  pp_debug("  In edge ~w -> ~w (~w)~n",[V1,V2,?SETS:to_list(Label)]),
  pp_edges(G,INs,Outs).


-endif.

%% //////////////////
%% // End of the file
