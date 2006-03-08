%%% -*- erlang-indent-level: 2 -*-
%%% $Id$
%%% Common wrapper for graph_coloring and coalescing regallocs.

-module(hipe_regalloc_loop).
-export([ra/5, ra_fp/4]).

%%-define(HIPE_INSTRUMENT_COMPILER, true). %% Turn on instrumentation.
-include("../main/hipe.hrl").

ra(Defun, SpillIndex, Options, RegAllocMod, TargetMod) ->
  {NewDefun, Coloring, _NewSpillIndex} =
    ra_common(Defun, SpillIndex, Options, RegAllocMod, TargetMod),
  {NewDefun, Coloring}.

ra_fp(Defun, Options, RegAllocMod, TargetMod) ->
  ra_common(Defun, 0, Options, RegAllocMod, TargetMod).

ra_common(Defun, SpillIndex, Options, RegAllocMod, TargetMod) ->
  ?inc_counter(ra_calls_counter, 1),
  CFG = TargetMod:defun_to_cfg(Defun),
  SpillLimit = TargetMod:number_of_temporaries(CFG),
  alloc(Defun, SpillLimit, SpillIndex, Options, RegAllocMod, TargetMod).

alloc(Defun, SpillLimit, SpillIndex, Options, RegAllocMod, TargetMod) ->
  ?inc_counter(ra_iteration_counter, 1),
  CFG = TargetMod:defun_to_cfg(Defun),
  {Coloring, _NewSpillIndex} =
    RegAllocMod:regalloc(CFG, SpillIndex, SpillLimit, TargetMod, Options),
  {NewDefun, DidSpill} = TargetMod:check_and_rewrite(Defun, Coloring),
  case DidSpill of
    false -> %% No new temps, we are done.
      ?add_spills(Options, _NewSpillIndex),
      TempMap = hipe_temp_map:cols2tuple(Coloring, TargetMod),
      {TempMap2, NewSpillIndex2} = 
	hipe_spillmin:stackalloc(CFG, [], SpillIndex, Options, 
				 TargetMod, TempMap),
      Coloring2 = 
	hipe_spillmin:mapmerge(hipe_temp_map:to_substlist(TempMap), TempMap2),
      %% case proplists:get_bool(verbose_spills, Options) of
      %%   true ->
      %%     ?msg("Num spill slots used: ~p~n", [NewSpillIndex2-SpillIndex]);
      %%   false ->
      %%     ok
      %% end,
      {NewDefun, Coloring2, NewSpillIndex2};
    _ ->
      %% Since SpillLimit is used as a low-water-mark
      %% the list of temps not to spill is uninteresting.
      alloc(NewDefun, SpillLimit, SpillIndex, Options, RegAllocMod, TargetMod)
  end.
