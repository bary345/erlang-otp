%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Copyright (c) 2003 by Erik Stenman.  
%% -*- erlang-indent-level: 2 -*-
%% ====================================================================
%%  Filename : 	hipe_icode_pp.erl
%%  Module   :	hipe_icode_pp
%%  Purpose  :  Pretty-printer for Icode.
%%  Notes    : 
%%  History  :	* 2003-04-16  (stenman@epfl.ch): 
%%               Created.
%%  CVS      :
%%              $Author: tobiasl $
%%              $Date: 2003/04/23 12:31:24 $
%%              $Revision: 1.3 $
%% ====================================================================
%%  Exports  :
%%
%% ____________________________________________________________________
%% 
%%@doc Icode PrettyPrinter
%% 
%%@end
%% ____________________________________________________________________
-module(hipe_icode_pp).
-export([pp/1,	pp/2, pp_instrs/2, pp_exit/1]).



%% - changed pp_instr => pp_instrs + pp_instr as in RTL and Sparc
%% - added pp_exit/1 as in RTL + Sparc.

%%@spec (Icode::hipe_icode:icode()) -> ok
%%
%%@doc Prettyprints Linear Icode on stdout.
%%<p> Badly formed or unknown instructions are printed suronded by three stars "***".</p>
pp(Icode) ->
  pp(standard_io, Icode).

%%@spec (IoDevice::iodevice(), Icode::hipe_icode:icode()) -> ok
%%
%%@doc Prettyprints Linear Icode on IoDevice.
%%<p> Badly formed or unknown instructions are printed suronded by three stars "***".</p>
pp(Dev, Icode) ->
  {Mod, Fun, _Arity} = hipe_icode:icode_fun(Icode),
  Args =  hipe_icode:icode_params(Icode),
  io:format(Dev, "~w:~w(", [Mod, Fun]),
  pp_args(Dev, Args),
  io:format(Dev, ") ->~n", []),
  io:format(Dev, "%% Info:~w\n",
	    [[case hipe_icode:icode_is_closure(Icode) of
		true -> 'Closure'; 
		false -> 'Not a closure'
	      end,
	      case hipe_icode:icode_is_leaf(Icode) of
		true -> 'Leaf function'; 
		false -> 'Not a leaf function'
	      end |
	      hipe_icode:icode_info(Icode)]]),
  pp_instrs(Dev, hipe_icode:icode_code(Icode)),
  io:format(Dev, "%% Data:\n", []),
  hipe_data_pp:pp(Dev, hipe_icode:icode_data(Icode), icode, "").

%%@spec (iodevice(), [hipe_icode:icode_instruction()]) -> ok
%%
%%@doc Prettyprints a list of Icode instrucitons.
%% Badly formed or unknown instructions are printed suronded by three stars "***".
pp_instrs(_Dev, []) ->
  ok;
pp_instrs(Dev, [I|Is]) ->
  case catch pp_instr(Dev, I) of
    {'EXIT',_Rsn} ->
      io:format(Dev, '*** ~w ***~n',[I]);
    _ ->
      ok
  end,
  pp_instrs(Dev, Is).

%% ____________________________________________________________________
%% 
%%@spec (Icode::hipe_icode:icode()) -> ok
%%
%%@doc Prettyprints Linear Icode on stdout.
%% Bad formed or unknown instructions generates an exception.
pp_exit(Icode) ->
  pp_exit(standard_io, Icode).

%%@spec (IoDevice::iodevice(), Icode::hipe_icode:icode()) -> ok
%%
%%@doc Prettyprints Linear Icode on IoDevice.
%% Bad formed or unknown instructions generates an exception.
pp_exit(Dev, Icode) ->
  {Mod, Fun, _Arity} = hipe_icode:icode_fun(Icode),
  Args =  hipe_icode:icode_params(Icode),
  io:format(Dev, "~w:~w(", [Mod, Fun]),
  pp_args(Dev, Args),
  io:format(Dev, ") ->~n", []),
  pp_instrs_exit(Dev, hipe_icode:icode_code(Icode)).

%% Prettyprints a list of Icode instrucitons.
%% Badly formed or unknown instructions generates an exception.
pp_instrs_exit(_Dev, []) ->
  ok;
pp_instrs_exit(Dev, [I|Is]) ->
  case catch pp_instr(Dev, I) of
    {'EXIT',_Rsn} ->
      exit({pp,I});
    _ ->
      ok
  end,
  pp_instrs_exit(Dev, Is).

%% ____________________________________________________________________
%% 
pp_instr(Dev, I) ->
  case hipe_icode:type(I) of 
    label ->
      io:format(Dev, "~p: ", [hipe_icode:label_name(I)]),
      case  hipe_icode:info(I) of
	[] -> io:format(Dev, "~n",[]);
	Info -> io:format(Dev, "~w~n", [Info])
      end;

    comment ->
      io:format(Dev, "    % ~p~n", [hipe_icode:comment_text(I)]);

    phi ->
      io:format(Dev, "    ", []),
      pp_arg(Dev, hipe_icode:phi_dst(I)),
      io:format(Dev, " := phi(", []),
      pp_args(Dev, hipe_icode:phi_args(I)),
      io:format(Dev, ")~n", []);

    mov ->
      io:format(Dev, "    ", []),
      pp_arg(Dev, hipe_icode:mov_dst(I)),
      io:format(Dev, " := ", []),
      pp_arg(Dev, hipe_icode:mov_src(I)),
      io:format(Dev, "~n", []);

    call ->
      case hipe_icode:call_in_guard(I) of
	true ->
	  io:format(Dev, " <G>", []);
	_ ->
	  io:format(Dev, "    ", [])
      end,
      case hipe_icode:call_dst(I) of
	[] ->
	  io:format(Dev, "_ := ", []);
	Dst ->
	  pp_args(Dev, Dst),
	  io:format(Dev, " := ", [])
      end,
      hipe_icode_primops:pp(hipe_icode:call_fun(I), Dev),
      io:format(Dev, "(", []),
      pp_args(Dev, hipe_icode:call_args(I)),
      case hipe_icode:call_continuation(I) of
	[] ->
	  io:format(Dev, ") (~w)", [hipe_icode:call_type(I)]);
	CC ->
	  io:format(Dev, ") (~w) -> ~w",
		    [hipe_icode:call_type(I),CC])
      end,

      case hipe_icode:call_fail(I) of
	[] ->  io:format(Dev, "~n", []);
	Fail ->  io:format(Dev, ", #fail ~w~n", [Fail])
      end;
    enter ->
      io:format(Dev, "    ", []),
      case hipe_icode:enter_fun(I) of
	{Mod, Fun, _Arity} ->
	  io:format(Dev, "~w:~w(", [Mod, Fun]);
	{Fun, _Arity} ->
	  io:format(Dev, "~w(", [Fun]);
	Fun ->
	  io:format(Dev, "~w(", [Fun])
      end,
      pp_args(Dev, hipe_icode:enter_args(I)),
      io:format(Dev, ") (~w) ~n", 
		[hipe_icode:enter_type(I)]);
    return ->
      io:format(Dev, "    return(", []),
      pp_args(Dev, hipe_icode:return_vars(I)),
      io:format(Dev, ")~n", []);
    pushcatch ->
      io:format(Dev, "    pushcatch -> ~w cont ~w~n", 
		[hipe_icode:pushcatch_label(I), 
		 hipe_icode:pushcatch_successor(I)]);
    restore_catch ->
      io:format(Dev, "    ", []),
      case hipe_icode:restore_catch_type(I) of
	'try' ->
	  pp_args(Dev, [hipe_icode:restore_catch_reason_dst(I),
			hipe_icode:restore_catch_type_dst(I)]);
	'catch' ->
	  pp_arg(Dev, hipe_icode:restore_catch_reason_dst(I))
      end,
      io:format(Dev, " := restore_catch(~w)~n",
		[hipe_icode:restore_catch_label(I)]);
    remove_catch ->
      io:format(Dev, "    remove_catch(~w)~n", 
		[hipe_icode:remove_catch_label(I)]);
    fail ->
      Type = case hipe_icode:fail_type(I) of
	       fault2 -> fault;
	       T -> T
	     end,
      io:format(Dev, "    fail(~w, [", [Type]),
      pp_args(Dev, hipe_icode:fail_reason(I)),
      io:put_chars(Dev, "])\n");
    'if' ->
      io:format(Dev, "    if ~w(", [hipe_icode:if_op(I)]),
      pp_args(Dev, hipe_icode:if_args(I)),
      io:format(Dev, ") then ~p (~.2f) else ~p~n", 
		[hipe_icode:if_true_label(I), hipe_icode:if_pred(I),  hipe_icode:if_false_label(I)]);
    switch_val ->
      io:format(Dev, "    switch_val ",[]),
      pp_arg(Dev, hipe_icode:switch_val_arg(I)),
      pp_switch_cases(Dev, hipe_icode:switch_val_cases(I)),
      io:format(Dev, "    fail -> ~w\n", 
		[hipe_icode:switch_val_fail_label(I)]);
    switch_tuple_arity ->
      io:format(Dev, "    switch_tuple_arity ",[]),
      pp_arg(Dev, hipe_icode:switch_tuple_arity_arg(I)),
      pp_switch_cases(Dev,hipe_icode:switch_tuple_arity_cases(I)),
      io:format(Dev, "    fail -> ~w\n", 
		[hipe_icode:switch_tuple_arity_fail_label(I)]);
    type ->
      io:format(Dev, "    if is_", []),
      pp_type(Dev, hipe_icode:type_type(I)),
      io:format(Dev, "(", []),
      pp_arg(Dev, hipe_icode:type_var(I)),
      io:format(Dev, ") then ~p (~.2f) else ~p~n", 
		[hipe_icode:type_true_label(I), hipe_icode:type_pred(I), 
		 hipe_icode:type_false_label(I)]);
    goto ->
      io:format(Dev, "    goto ~p~n", [hipe_icode:goto_label(I)]);
    fmov ->
      io:format(Dev, "    ", []),
      pp_arg(Dev, hipe_icode:fmov_dst(I)),
      io:format(Dev, " f:= ", []),
      pp_arg(Dev, hipe_icode:fmov_src(I)),
      io:format(Dev, "~n", [])
  end.

pp_arg(Dev, {var, V, T}) ->
  case erl_types:t_is_undefined(T) of
    true->
      io:format(Dev, "v~p", [V]);
    _ ->
      io:format(Dev, "v~p (~s)", [V, erl_types:t_to_string(T)])
  end;
pp_arg(Dev, {var, V}) ->
  io:format(Dev, "v~p", [V]);
pp_arg(Dev, {fvar, V}) ->
  io:format(Dev, "fv~p", [V]);
pp_arg(Dev, {reg, V}) -> 
  io:format(Dev, "r~p", [V]);
pp_arg(Dev, C) ->
  io:format(Dev, "~p", [hipe_icode:const_value(C)]).

pp_args(_Dev, []) -> ok;
pp_args(Dev, [A]) ->
  pp_arg(Dev, A);
pp_args(Dev, [A|Args]) ->
  pp_arg(Dev, A),
  io:format(Dev, ", ", []),
  pp_args(Dev, Args).

pp_type(Dev, T) ->
  io:format(Dev, "~w", [T]).

pp_switch_cases(Dev, Cases) ->
  io:format(Dev, " of\n",[]),
  pp_switch_cases(Dev, Cases,1),
  io:format(Dev, "",[]).

pp_switch_cases(Dev, [{Val,L}], _Pos) -> 
  io:format(Dev, "        ",[]),
  pp_arg(Dev, Val),
  io:format(Dev, " -> ~w\n", [L]);
pp_switch_cases(Dev, [{Val, L}|Ls], Pos) -> 
  io:format(Dev, "        ",[]),
  pp_arg(Dev, Val),
  io:format(Dev, " -> ~w;\n", [L]),
  NewPos = Pos,
  %%    case Pos of
  %%      5 -> io:format(Dev, "\n              ",[]),
  %%	   0;
  %%      N -> N + 1
  %%    end,
  pp_switch_cases(Dev, Ls, NewPos);
pp_switch_cases(_Dev, [], _) -> ok.

