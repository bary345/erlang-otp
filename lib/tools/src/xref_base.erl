%% ``The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved via the world wide web at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% The Initial Developer of the Original Code is Ericsson Utvecklings AB.
%% Portions created by Ericsson are Copyright 2000, Ericsson Utvecklings
%% AB. All Rights Reserved.''
%% 
%%     $Id$
%%
-module(xref_base).

-export([new/0, new/1, delete/1,
	 add_directory/2, add_directory/3,
	 add_module/2, add_module/3,
	 add_application/2, add_application/3,
	 replace_module/3, replace_module/4,
	 replace_application/3, replace_application/4,
	 remove_module/2, remove_application/2, remove_release/2,
	 add_release/2, add_release/3,
	 get_library_path/1, set_library_path/2, set_library_path/3,
	 set_up/1, set_up/2,
	 q/2, q/3, info/1, info/2, info/3, update/1, update/2, 
	 forget/1, forget/2, variables/1, variables/2,
	 analyze/2, analyze/3, analysis/1,
	 get_default/2, set_default/3,
	 get_default/1, set_default/2]).

-export([format_error/1]).

%% Internal exports.
-export([abst/4]).
-export([inter_graph/6]).
%% The following functions are exported for testing purposes only:
-export([do_add_module/3, do_add_application/2, do_add_release/2, 
	 do_remove_module/2]).

-import(lists, 
	[filter/2, flatten/1, foldl/3, map/2, member/2, reverse/1, sort/1]).

-import(xsets, 
	[composition1/2, difference/2, difference_of_families/2, 
	 domain/1, empty_set/0, family_of_subsets/1, family_partition/2,
	 family_to_relation/1, family_union/1, from_list/1, from_term/1,
	 image/2, intersection_of_families/2, inverse/1,
	 is_empty_set/1, multiple_compositions/2, no_elements/1,
	 partition/2, projection/2, range/1,
	 relation/1, relation_to_family/1, restriction/2,
	 restriction/3, from_sets/1, specification/2,
	 substitution/2, to_external/1, type/1, union/2,
	 union_of_families/1, union_of_families/2]).

-include("xref.hrl").

-define(Suffix, ".beam").

%-define(debug, true).

-ifdef(debug).
-define(FORMAT(P, A), io:format(P, A)).
-else.
-define(FORMAT(P, A), ok).
-endif.

%%
%%  Exported functions
%%

new() ->
    new([]).

%% -> {ok, InitialState}
new(Options) ->
    case xref_utils:options(Options, [{xref_mode,[functions,modules]}]) of
	{[[OM]], []} ->
	    {ok, #xref{mode = OM}};
	_ ->
	    error({invalid_options, Options})
    end.

%% -> ok
%% Need not be called by the server.
delete(State) when State#xref.variables == not_set_up ->
    ok;
delete(State) ->
    Fun = fun({X, _}) ->
		  case catch digraph:info(X) of
		      Info when list(Info) ->
			  true = digraph:delete(X);
		      _Else ->
			  ok
		  end
	     end,
    map(Fun, dict:dict_to_list(State#xref.variables)),
    ok.

add_directory(State, Dir) ->
    add_directory(State, Dir, []).
    
%% -> {ok, Modules, NewState} | Error
add_directory(State, Dir, Options) ->
    ValOptions = option_values([builtins, recurse, verbose, warnings], State),
    case xref_utils:options(Options, ValOptions) of
	{[[OB], [OR], [OV], [OW]], []} ->
	    catch do_add_directory(Dir, [], OB, OR, OV, OW, State);
	_ ->
	    error({invalid_options, Options})
    end.

add_module(State, File) ->
    add_module(State, File, []).

%% -> {ok, Module, NewState} | Error
add_module(State, File, Options) ->
    ValOptions = option_values([builtins, verbose, warnings], State),
    case xref_utils:options(Options, ValOptions) of
	{[[OB], [OV], [OW]], []} ->
	    Splitname = xref_utils:split_filename(File, ?Suffix),
	    case catch do_add_module(Splitname, [], OB, OV, OW, State) of
		{ok, [Module], NewState} ->
		    {ok, Module, NewState};
		{ok, [], NewState} ->
		    error({no_debug_info, File});
		Error ->
		    Error
	    end;
	_ ->
	    error({invalid_options, Options})
    end.

add_application(State, AppDir) ->
    add_application(State, AppDir, []).

%% -> {ok, AppName, NewState} | Error
add_application(State, AppDir, Options) ->
    OptVals = option_values([builtins, verbose, warnings], State),
    ValidOptions = [{name, ["", fun check_name/1]} | OptVals],
    case xref_utils:options(Options, ValidOptions) of
	{[ApplName, [OB], [OV], [OW]], []} ->
	    catch do_add_application(AppDir, [], ApplName, OB, OV, OW, State);
	_ ->
	    error({invalid_options, Options})
    end.

replace_module(State, Module, File) ->
    replace_module(State, Module, File, []).

%% -> {ok, Module, NewState} | Error
replace_module(State, Module, File, Options) ->
    ValidOptions = option_values([verbose, warnings], State),
    case xref_utils:options(Options, ValidOptions) of
	{[[OV], [OW]], []} ->
	    catch do_replace_module(Module, File, OV, OW, State);
	_ ->
	    error({invalid_options, Options})
    end.

replace_application(State, Appl, Dir) ->
    replace_application(State, Appl, Dir, []).

%% -> {ok, AppName, NewState} | Error
replace_application(State, Appl, Dir, Options) ->
    ValidOptions = option_values([builtins, verbose, warnings], State),
    case xref_utils:options(Options, ValidOptions) of
	{[[OB], [OV], [OW]], []} ->
	    catch do_replace_application(Appl, Dir, OB, OV, OW, State);
	_ ->
	    error({invalid_options, Options})
    end.

%% -> {ok, NewState} | Error
remove_module(State, Mod) ->
    case catch do_remove_module(State, Mod) of
	{ok, _OldXMod, NewState} ->
	    {ok, NewState};
	Error ->
	    Error
    end.

%% -> {ok, NewState} | Error
remove_application(State, Appl) ->
    case catch do_remove_application(State, Appl) of
	{ok, _OldXApp, NewState} ->
	    {ok, NewState};
	Error ->
	    Error
    end.

%% -> {ok, NewState} | Error
remove_release(State, Rel) ->
    case catch do_remove_release(State, Rel) of
	{ok, _OldXRel, NewState} ->
	    {ok, NewState};
	Error ->
	    Error
    end.

add_release(State, RelDir) ->
    add_release(State, RelDir, []).

%% -> {ok, ReleaseName, NewState} | Error
add_release(State, RelDir, Options) ->
    ValidOptions0 = option_values([builtins, verbose, warnings], State),
    ValidOptions = [{name, ["", fun check_name/1]} | ValidOptions0],
    case xref_utils:options(Options, ValidOptions) of
	{[RelName, [OB], [OV], [OW]], []} ->
	    catch do_add_release(RelDir, RelName, OB, OV, OW, State);
	_ ->
	    error({invalid_options, Options})
    end.

get_library_path(State) ->
    {ok, State#xref.library_path}.

set_library_path(State, Path) ->
    set_library_path(State, Path, []).

%% -> {ok, NewState} | Error
set_library_path(State, code_path, _Options) ->
    S1 = State#xref{library_path = code_path, libraries = dict:new()},
    {ok, take_down(S1)};
set_library_path(State, Path, Options) ->
    case is_path(Path) of
	true ->
	    ValidOptions = option_values([verbose], State),
	    case xref_utils:options(Options, ValidOptions) of
		{[[OV]], []} ->
		    do_add_libraries(Path, OV, State);
		_ ->
		    error({invalid_options, Options})
	    end;
	false ->
	    error({invalid_path, Path})
    end.

set_up(State) ->
    set_up(State, []).

%% -> {ok, NewState} | Error
set_up(State, Options) ->
    ValidOptions = option_values([verbose], State),
    case xref_utils:options(Options, ValidOptions) of
	{[[Verbose]], []} ->
	    do_set_up(State, Verbose);
	_ ->
	    error({invalid_options, Options})
    end.

q(S, Q) ->
    q(S, Q, []).

%% -> {{ok, Answer}, NewState} | {Error, NewState}
q(S, Q, Options) when atom(Q) ->
    q(S, atom_to_list(Q), Options);
q(S, Q, Options) ->
    case is_string(Q, 1) of
	true -> 
	    case set_up(S, Options) of
		{ok, S1} ->
		    case xref_compiler:compile(Q, S1#xref.variables) of
			{NewT, Ans} ->
			    {{ok, Ans}, S1#xref{variables = NewT}};
			Error ->
			    {Error, S1}
		    end;
		Error ->
		    {Error, S}
	    end;
	false ->
	    {error({invalid_query, Q}), S}
    end.

%% -> InfoList
info(State) ->
    D0 = sort(dict:dict_to_list(State#xref.modules)),
    D = map(fun({_M, XMod}) -> XMod end, D0),
    NoApps = length(dict:dict_to_list(State#xref.applications)),
    NoRels = length(dict:dict_to_list(State#xref.releases)),
    No = no_sum(State, D),
    [{library_path, State#xref.library_path}, {mode, State#xref.mode},
     {no_releases, NoRels}, {no_applications, NoApps}] ++ No.

info(State, What) ->
    do_info(State, What).

%% -> [{what(), InfoList}]
info(State, What, Qual) ->
    catch do_info(State, What, Qual).

update(State) ->
    update(State, []).

%% -> {ok, NewState, Modules} | Error
update(State, Options) ->
    ValidOptions = option_values([verbose, warnings], State),
    case xref_utils:options(Options, ValidOptions) of
	{[[OV],[OW]], []} ->
	    catch do_update(OV, OW, State);
	_ ->
	    error({invalid_options, Options})
    end.

%% -> {ok, NewState}
forget(State) ->
    {U, _P} = do_variables(State),
    {ok, foldl(fun(V, S) -> {ok, NS} = forget(S, V), NS end, State, U)}.

%% -> {ok, NewState} | Error
forget(State, Variable) when State#xref.variables == not_set_up ->
    error({not_user_variable, Variable});
forget(State, Variable) when atom(Variable) ->
    forget(State, [Variable]);
forget(State, Variables) ->
    Vars = State#xref.variables,
    do_forget(Variables, Vars, Variables, State).
    
variables(State) ->
    variables(State, [user]).

%% -> {{ok, Answer}, NewState} | {Error, NewState}
%% Answer = [{vartype(), [VariableName]}]
variables(State, Options) ->
    ValidOptions = option_values([verbose], State),
    case xref_utils:options(Options, [user, predefined | ValidOptions]) of
	{[User,Predef,[OV]],[]} ->
	    case do_set_up(State, OV) of
		{ok, NewState} ->
		    {U, P} = do_variables(NewState),
		    R1 = if User == true -> [{user, U}]; true -> [] end,
		    R = if 
			    Predef == true -> [{predefined,P} | R1]; 
			    true -> R1 
			end,
		    {{ok, R}, NewState};
		Error ->
		    {Error, State}
	    end;
	_ ->
	    {error({invalid_options, Options}), State}
    end.

analyze(State, Analysis) ->
    analyze(State, Analysis, []).

%% -> {{ok, Answer}, NewState} | {Error, NewState}
analyze(State, Analysis, Options) ->
    case analysis(Analysis) of
	P when list(P) -> 
	    q(State, P, Options);
	Error ->
	    {Error, State}
    end.

%% -> string() | Error
analysis(undefined_function_calls) ->
    "XC || (XU - X - B)";
analysis(undefined_functions) ->
    %% "XU * (L + U)" is an equivalent, but the following works when
    %% L is not available.
    "XU - X - B";
analysis(locals_not_used) ->
    %% The Inter Call Graph is used to get local functions that are not
    %% used (indirectly) from any export: "(domain EE + range EE) * L".
    %% But then we only get locals that make some calls, so we add
    %% locals that are not used at all: "L * (UU + XU - LU)".
    "L * (UU + XU - LU + domain EE + range EE)";
analysis(exports_not_used) ->
    %% Local calls are not considered here. "X * UU" would do otherwise.
    "X - XU";
analysis({call, F}) ->
    make_query("range (E | ~p : Fun)", [F]);
analysis({use, F}) ->
    make_query("domain (E || ~p : Fun)", [F]);
analysis({module_call, M}) ->
    make_query("range (ME | ~p : Mod)", [M]);
analysis({module_use, M}) ->
    make_query("domain (ME || ~p : Mod)", [M]);
analysis({application_call, A}) ->
    make_query("range (AE | ~p : App)", [A]);
analysis({application_use, A}) ->
    make_query("domain (AE || ~p : App)", [A]);
analysis({release_call, R}) ->
    make_query("range (RE | ~p : Rel)", [R]);
analysis({release_use, R}) ->
    make_query("domain (RE || ~p : Rel)", [R]);
analysis(Culprit) ->
    error({unknown_analysis, Culprit}).

%% -> {ok, OldValue, NewState} | Error
set_default(State, Option, Value) ->
    case get_default(State, Option) of
	{ok, OldValue} ->
	    Values = option_values([Option], State),
	    case xref_utils:options([{Option,Value}], Values) of
		{_, []} ->
		    NewState = set_def(Option, Value, State),
		    {ok, OldValue, NewState};
		{_, Unknown} ->
		    error({invalid_options, Unknown})
	    end;
	Error ->
	    Error
    end.

%% -> {ok, Value} | Error
get_default(State, Option) ->
    case catch current_default(State, Option) of
	{'EXIT', _} ->
	    error({invalid_options, [Option]});
	Value ->
	    {ok, Value}
    end.

%% -> [{Option, Value}]
get_default(State) ->
    Fun = fun(O) -> V = current_default(State, O), {O, V} end, 
    map(Fun, [builtins, recurse, verbose, warnings]).

%% -> {ok, NewState} -> Error
set_default(State, Options) ->
    Opts = [builtins, recurse, verbose, warnings],
    ValidOptions = option_values(Opts, State),
    case xref_utils:options(Options, ValidOptions) of
	{Values = [[_], [_], [_], [_]], []} ->
	    {ok, set_defaults(Opts, Values, State)};
	_ ->
	    error({invalid_options, Options})
    end.

format_error({error, Module, Error}) ->
    Module:format_error(Error);
format_error({invalid_options, Options}) ->
    io_lib:format("Unknown option(s) or invalid option value(s): ~p~n", 
		  [Options]);
format_error({no_debug_info, FileName}) ->
    io_lib:format("The BEAM file ~p has no debug info~n", [FileName]);
format_error({invalid_path, Term}) ->
    io_lib:format("A path (a list of strings) was expected: ~p~n", [Term]);
format_error({invalid_query, Term}) ->
    io_lib:format("A query (a string or an atom) was expected: ~p~n", [Term]);
format_error({not_user_variable, Variable}) ->
    io_lib:format("~p is not a user variable~n", [Variable]);
format_error({unknown_analysis, Term}) ->
    io_lib:format("~p is not a predefined analysis~n", [Term]);
format_error({module_mismatch, Module, ReadModule}) ->
    io_lib:format("Name of read module ~p does not match analyzed module ~p~n",
		  [ReadModule, Module]);
format_error({release_clash, {Release, Dir, OldDir}}) ->
    io_lib:format("The release ~p read from ~p clashes with release "
		  "already read from ~p~n", [Release, Dir, OldDir]);
format_error({application_clash, {Application, Dir, OldDir}}) ->
    io_lib:format("The application ~p read from ~p clashes with application "
		  "already read from ~p~n", [Application, Dir, OldDir]);
format_error({module_clash, {Module, Dir, OldDir}}) ->
    io_lib:format("The module ~p read from ~p clashes with module "
		  "already read from ~p~n", [Module, Dir, OldDir]);
format_error({no_such_release, Name}) ->
    io_lib:format("There is no analyzed release ~p~n", [Name]);
format_error({no_such_application, Name}) ->
    io_lib:format("There is no analyzed application ~p~n", [Name]);
format_error({no_such_module, Name}) ->
    io_lib:format("There is no analyzed module ~p~n", [Name]);
format_error({no_such_info, Term}) ->
    io_lib:format("~p is not one of 'modules', 'applications', "
		  "'releases' and 'libraries'~n", [Term]);
format_error(E) ->
    io_lib:format("~p~n", [E]).

%%
%%  Local functions
%%

check_name([N]) when atom(N) -> true;
check_name(_) -> false.

do_update(OV, OW, State) ->
    Changed = updated_modules(State),
    Fun = fun({Mod,File}, S) ->
		  {ok, _M, NS} = do_replace_module(Mod, File, OV, OW, S),
		  NS
	  end,
    NewState = foldl(Fun, State, Changed),
    {ok, NewState, to_external(domain(relation(Changed)))}.

%% -> [{Module, File}]
updated_modules(State) ->
    Fun = fun({M,XMod}, L) ->
		  RTime = XMod#xref_mod.mtime,
		  File = module_file(XMod),
		  case xref_utils:file_info(File) of
		      {ok, {_, file, readable, MTime}} when MTime /= RTime ->
			  [{M,File} | L];
		      _Else -> 
			  L
		  end
	  end,
    foldl(Fun, [], dict:dict_to_list(State#xref.modules)).

do_forget([Variable | Variables], Vars, Vs, State) ->
    case dict:find(Variable, Vars) of
	{ok, #xref_var{vtype = user}} ->
	    do_forget(Variables, Vars, Vs, State);
	_ ->
	    error({not_user_variable, Variable})
    end;
do_forget([], Vars, Vs, State) ->
    Fun = fun(V, VT) ->
		  {ok, #xref_var{value = Value}} = dict:find(V, VT),
		  VT1 = xref_compiler:update_graph_counter(Value, -1, VT),
		  dict:erase(V, VT1)
	  end,
    NewVars = foldl(Fun, Vars, Vs),
    NewState = State#xref{variables = NewVars},
    {ok, NewState}.

%% -> {ok, Module, State} | throw(Error)
do_replace_module(Module, File, OV, OW, State) ->
    {ok, OldXMod, State1} = do_remove_module(State, Module),
    OldApp = OldXMod#xref_mod.app_name,
    OB = OldXMod#xref_mod.builtins,
    Splitname = xref_utils:split_filename(File, ?Suffix),
    case do_add_module(Splitname, OldApp, OB, OV, OW, State1) of
	{ok, [Module], NewState} ->
	    {ok, Module, NewState};
	{ok, [ReadModule], _State} ->
	    throw_error({module_mismatch, Module, ReadModule});
	{ok, [], NewState} ->
	    throw_error({no_debug_info, File})
    end.

do_replace_application(Appl, Dir, OB, OV, OW, State) ->
    {ok, OldXApp, State1} = do_remove_application(State, Appl),
    Rel = OldXApp#xref_app.rel_name,
    N = OldXApp#xref_app.name,
    %% The application name is kept; the name of Dir is not used
    %% as source for a "new" application name.
    do_add_application(Dir, Rel, [N], OB, OV, OW, State1).

%% -> {ok, ReleaseName, NewState} | throw(Error)
do_add_release(Dir, RelName, OB, OV, OW, State) ->
    case xref_utils:release_directory(Dir, true, "ebin") of
	{ok, ReleaseDirName, ApplDir, Dirs} ->
	    ApplDirs = xref_utils:select_last_application_version(Dirs),
	    Release = case RelName of 
			  [[]] -> ReleaseDirName;
			  [Name] -> Name
		      end,
	    XRel = #xref_rel{name = Release, dir = ApplDir},
	    NewState = do_add_release(State, XRel),
	    add_rel_appls(ApplDirs, [Release], OB, OV, OW, NewState);
	Error ->
	    throw(Error)
    end.

do_add_release(S, XRel) ->
    Release = XRel#xref_rel.name,
    case dict:find(Release, S#xref.releases) of
	{ok, OldXRel} ->
	    Dir = XRel#xref_rel.dir,
	    OldDir = OldXRel#xref_rel.dir,
	    throw_error({release_clash, {Release, Dir, OldDir}});
	error ->
	    D1 = dict:store(Release, XRel, S#xref.releases),
	    S#xref{releases = D1}
    end.

add_rel_appls([ApplDir | ApplDirs], Release, OB, OV, OW, State) ->
    {ok, _AppName,  NewState} = 
	add_appldir(ApplDir, Release, [[]], OB, OV, OW, State),
    add_rel_appls(ApplDirs, Release, OB, OV, OW, NewState);
add_rel_appls([], [Release], _OB, _OV, _OW, NewState) ->
    {ok, Release, NewState}.

do_add_application(Dir0, Release, Name, OB, OV, OW, State) ->
    case xref_utils:select_application_directories([Dir0], "ebin") of
	{ok, [ApplD]} ->
	    add_appldir(ApplD, Release, Name, OB, OV, OW, State);
	Error ->
	    throw(Error)
    end.

%% -> {ok, AppName, NewState} | throw(Error)
add_appldir(ApplDir, Release, Name, OB, OV, OW, OldState) ->
    {AppName0, Vsn, Dir} = ApplDir,
    AppName = case Name of
		  [[]] -> AppName0;
		  [N] -> N
	      end,
    AppInfo = #xref_app{name = AppName, rel_name = Release, 
			vsn = Vsn, dir = Dir},
    State1 = do_add_application(OldState, AppInfo),
    {ok, _Modules, NewState} = 
	do_add_directory(Dir, [AppName], OB, false, OV, OW, State1),
    {ok, AppName, NewState}.

%% -> State | throw(Error)
do_add_application(S, XApp) ->
    Application = XApp#xref_app.name,
    case dict:find(Application, S#xref.applications) of
	{ok, OldXApp} ->
	    Dir = XApp#xref_app.dir,
	    OldDir = OldXApp#xref_app.dir,
	    throw_error({application_clash, {Application, Dir, OldDir}});
	error ->
	    D1 = dict:store(Application, XApp, S#xref.applications),
	    S#xref{applications = D1}
    end.

%% -> {ok, Modules, NewState} | throw(Error)
do_add_directory(Dir, AppName, Bui, Rec, Ver, War, State) ->
    {FileNames, Errors, Jams, Unreadable} =
	xref_utils:scan_directory(Dir, Rec, [?Suffix], [".jam"]),
    warnings(War, jam, Jams),	
    warnings(War, unreadable, Unreadable),
    case Errors of
	[] ->
	    do_add_modules(FileNames, AppName, Bui, Ver, War, State, []);
	[Error | _] ->
	    throw(Error)
    end.

do_add_modules([], _AppName, _OB, _OV, _OW, State, Modules) ->
    {ok, sort(Modules), State};
do_add_modules([File | Files], AppName, OB, OV, OW, State, Modules) ->
    {ok, M, NewState} = do_add_module(File, AppName, OB, OV, OW, State),
    do_add_modules(Files, AppName, OB, OV, OW, NewState, M ++ Modules).

%% -> {ok, Module, State} | throw(Error)
%% Options: verbose, warnings, builtins
do_add_module({Dir, Basename}, AppName, Builtins, Verbose, Warnings, State) ->
    File = filename:join(Dir, Basename),
    {ok, M, Bad, NewState} = 
	do_add_module1(Dir, File, AppName, Builtins, Verbose, Warnings, State),
    BadAttrs = map(fun(B) -> [File,B] end, Bad),
    warnings(Warnings, xref_attr, BadAttrs),
    {ok, M, NewState}.

do_add_module1(Dir, File, AppName, Builtins, Verbose, Warnings, State) ->
    message(Verbose, reading_beam, [File]),
    Mode = State#xref.mode,
    case xref_utils:subprocess(?MODULE, abst, [self(), File, Builtins, Mode],
				[link, {min_heap_size,100000}]) of
	{ok, M, no_abstract_code} when Verbose == true ->
	    message(Verbose, skipped_beam, []),
	    {ok, [], [], State};
	{ok, M, no_abstract_code} when Verbose == false ->
	    message(Warnings, no_debug_info, [File]),
	    {ok, [], [], State};
	{ok, M, Data, Unres}  ->
	    message(Verbose, done, []),
	    %% Unresolved = map(fun({L,MFA}) -> [File,L,MFA] end, Unres),
	    %% warnings(Warnings, unresolved, Unresolved),
	    NoUnres = length(Unres),
	    case NoUnres of
		0 -> ok;
		1 -> warnings(Warnings, unresolved_summary1, [[M]]);
		N -> warnings(Warnings, unresolved_summary, [[M, N]])
	    end,
	    T = case xref_utils:file_info(File) of
		    {ok, {_, _, _, Time}} -> Time;
		    Error -> throw(Error)
		end,
	    XMod = #xref_mod{name = M, app_name = AppName, dir = Dir, 
			     mtime = T, builtins = Builtins,
			     no_unresolved = NoUnres},
	    do_add_module(State, XMod, Data);
	Error ->
	    message(Verbose, error, []),
	    throw(Error)
    end.

abst(Pid, File, Builtins, Mode) ->
    Reply = abst0(File, Builtins, Mode),
    Pid ! {self(), Reply}.
	    
abst0(File, Builtins, Mode) when Mode == functions ->
    case beam_lib:chunks(File, [abstract_code, exports]) of
	{ok, {M, [{abstract_code, NoA},_X]}} when NoA == no_abstract_code ->
	    {ok, M, NoA};
	{ok, {M, [{abstract_code, {abstract_v1, Forms}}, {exports,X0}]}} ->
	    X = xref_utils:fa_to_mfa(X0, M),
	    xref_reader:module(M, Forms, Builtins, X);
	Error when element(1, Error) == error ->
	    Error
    end;
abst0(File, Builtins, Mode) when Mode == modules ->
    case beam_lib:chunks(File, [exports, imports]) of
	{ok, {Mod, [{exports,X0}, {imports,I0}]}} ->
	    X1 = xref_utils:fa_to_mfa(X0, Mod),
	    X = filter(fun(MFA) -> not (predef_fun())(MFA) end, X1),
	    I = case Builtins of
		    true ->
			I0;
		    false ->
			Fun = fun({M,F,A}) -> 
				      not erlang:is_builtin(M, F, A) 
			      end,
			filter(Fun, I0)
		end,
	    {ok, Mod, {X, I}, []};
	Error when element(1, Error) == error ->
	    Error
    end.

%% -> {ok, Module, Bad, State} | throw(Error)
%% Assumes:
%% L U X is a subset of dom DefAt
%% dom CallAt = LC U XC
%% Attrs is collected from the attribute 'xref' (experimental).
do_add_module(S, XMod, Data) ->
    M = XMod#xref_mod.name,
    case dict:find(M, S#xref.modules) of
	{ok, OldXMod}  ->
	    BF2 = module_file(XMod),
	    BF1 = module_file(OldXMod),
	    throw_error({module_clash, {M, BF1, BF2}});
	error ->
	    do_add_module(S, M, XMod, Data)
    end.

%%do_add_module(S, M, _XMod, Data)->
%%    {ok, M, [], S};
do_add_module(S, M, XMod, Data) when S#xref.mode == functions ->
    {DefAt0, LPreCAt0, XPreCAt0, LC0, XC0, X0, Attrs} = Data,
    %% Bad is a list of bad values of 'xref' attributes.
    {ALC0,AXC0,Bad0} = Attrs,
    FET = [tspec(fun_edge)],
    PCA = [tspec(pre_call_at)],

    XPreCAt1 = xref_utils:xset(XPreCAt0, PCA),
    LPreCAt1 = xref_utils:xset(LPreCAt0, PCA),
    DefAt = xref_utils:xset(DefAt0, [tspec(def_at)]),
    X1 = xref_utils:xset(X0, [tspec(func)]),
    XC1 = xref_utils:xset(XC0, FET),
    LC1 = xref_utils:xset(LC0, FET),
    AXC1 = xref_utils:xset(AXC0, PCA),
    ALC1 = xref_utils:xset(ALC0, PCA),

    DefinedFuns = domain(DefAt),
    {AXC, ALC, Bad, LPreCAt2, XPreCAt2} = 
	extra_edges(AXC1, ALC1, Bad0, DefinedFuns),
    LPreCAt = union(LPreCAt1, LPreCAt2),
    XPreCAt = union(XPreCAt1, XPreCAt2),
    NoCalls = no_elements(LPreCAt) + no_elements(XPreCAt),
    LCallAt = relation_to_family(LPreCAt),
    XCallAt = relation_to_family(XPreCAt),
    CallAt = union_of_families(LCallAt, XCallAt),
    %% Local and exported functions with no definitions are removed.
    L = difference(DefinedFuns, X1),
    X = difference(DefinedFuns, L),
    XC = union(XC1, AXC),
    LC = union(LC1, ALC),

    %% {EE, ECallAt} = inter_graph(X, L, LC, XC, LCallAt, XCallAt),
    {EE, ECallAt} = xref_utils:subprocess(?MODULE, inter_graph, 
				      [self(), X, L, LC, XC, CallAt],
				      [link, {min_heap_size,100000}]),

    [DefAt2,L2,X2,LCallAt2,XCallAt2,CallAt2,LC2,XC2,EE2,ECallAt2] =
	pack([DefAt,L,X,LCallAt,XCallAt,CallAt,LC,XC,EE,ECallAt]),

    %% Foo = [DefAt2,L2,X2,LCallAt2,XCallAt2,CallAt2,LC2,XC2,EE2,ECallAt2],
    %% io:format("{~p, ~p, ~p},~n", [M, pack:lsize(Foo), pack:usize(Foo)]),

    LU = range(LC2),

    FunFuns = xref_utils:xset(xref_utils:all_funfuns(), [tspec(func)]),
    Unres = restriction(2, XC2, FunFuns),
    LPredefined = predefined_funs(LU),

    MS = xref_utils:xset(M, atom),
    T = from_sets({MS,DefAt2,L2,X2,LCallAt2,XCallAt2,CallAt2,
		   LC2,XC2,LU,EE2,ECallAt2,Unres,LPredefined}),

    NoUnres = XMod#xref_mod.no_unresolved,
    Info = no_info(X2, L2, LC2, XC2, EE2, Unres, NoCalls, NoUnres),

    XMod1 = XMod#xref_mod{data = T, info = Info},
    S1 = S#xref{modules = dict:store(M, XMod1, S#xref.modules)},
    {ok, [M], Bad, take_down(S1)};
do_add_module(S, M, XMod, Data) when S#xref.mode == modules ->
    {X0, I0} = Data,
    X1 = xref_utils:xset(X0, [tspec(func)]),
    I1 = xref_utils:xset(I0, [tspec(func)]),
    [X2, I2] = pack([X1, I1]),
    MS = xref_utils:xset(M, atom),
    T = from_sets({MS, X2, I2}),
    Info = [],
    XMod1 = XMod#xref_mod{data = T, info = Info},
    S1 = S#xref{modules = dict:store(M, XMod1, S#xref.modules)},
    {ok, [M], [], take_down(S1)}.

%% Extra edges gathered from the attribute 'xref' (experimental)
extra_edges(CAX, CAL, Bad0, F) ->
    AXC0 = domain(CAX),
    ALC0 = domain(CAL),
    AXC = restriction(AXC0, F),
    ALC = restriction(2, restriction(ALC0, F), F),
    LPreCAt2 = restriction(CAL, ALC),
    XPreCAt2 = restriction(CAX, AXC),
    Bad = Bad0 ++ to_external(difference(AXC0, AXC)) 
	       ++ to_external(difference(ALC0, ALC)),
    {AXC, ALC, Bad, LPreCAt2, XPreCAt2}.

no_info(X, L, LC, XC, EE, Unres, NoCalls, NoUnresCalls) ->
    NoUnres = no_elements(Unres),
    [{no_calls, {NoCalls-NoUnresCalls, NoUnresCalls}}, 
     {no_function_calls, {no_elements(LC), no_elements(XC)-NoUnres, NoUnres}},
     {no_functions, {no_elements(L), no_elements(X)}},
     {no_inter_function_calls, no_elements(EE)}].

inter_graph(Pid, X, L, LC, XC, CallAt) ->
    Pid ! {self(), inter_graph(X, L, LC, XC, CallAt)}.

%% Inter Call Graph.
%inter_graph(_X, _L, _LC, _XC, _CallAt) ->
%    {empty_set(), empty_set()};
inter_graph(X, L, LC, XC, CallAt) ->
    G = xref_utils:relation_to_graph(LC),

    Reachable0 = digraph_utils:reachable_neighbours(to_external(X), G),
    Reachable = xref_utils:xset(Reachable0, [tspec(func)]),
    % XL includes exports and locals that are not used by any exports
    % (the locals are tacitly ignored in the comments below).
    XL = union(difference(L, Reachable), X),

    % Immediate local calls between the module's own exports are qualified.
    LEs = restriction(restriction(2, LC, XL), XL),
    % External calls to the module's exports are qualified.
    XEs = restriction(XC, XL),
    Es = union(LEs, XEs),

    E1 = to_external(restriction(difference(LC, LEs), XL)),
    R0 = xref_utils:xset(reachable(E1, G, []), 
			 [{tspec(func), tspec(fun_edge)}]),
    true = digraph:delete(G),
    
    % RL is a set of indirect local calls to exports.
    RL = restriction(R0, XL),
    % RX is a set of indirect external calls to exports.
    RX = composition1(R0, XC),
    R = union(RL, inverse(RX)),

    EE0 = substitution(fun({Ee2,{Ee1,_L}}) -> {Ee1,Ee2} end, R),
    EE = union(Es, EE0),

    % The first call in each chain, {e1,l}, contributes with the line
    % number(s) l.
    ECAllAt0 = substitution(fun({Ee2,{Ee1,Ls}}) -> {{Ee1,Ls},{Ee1,Ee2}} end,R),
    ECAllAt1 = composition1(ECAllAt0, CallAt),
    ECAllAt2 = union(ECAllAt1, restriction(CallAt, Es)),
    ECAllAt = union_of_families(partition(fun(A) -> A end, ECAllAt2)),

    ?FORMAT("XL=~p~nXEs=~p~nLEs=~p~nE1=~p~nR0=~p~nRL=~p~nRX=~p~nR=~p~n"
	    "EE=~p~nECAllAt0=~p~nECAllAt1=~p~nECAllAt=~p~n~n",
	    [XL, XEs, LEs, E1, R0, RL, RX, R, EE, 
	     ECAllAt0, ECAllAt1, ECAllAt]),
    {EE, ECAllAt}.

%% -> set of {V2,{V1,L1}}
reachable([E = {_X, L} | Xs], G, R) ->
    Ns = digraph_utils:reachable([L], G),
    reachable(Xs, G, reach(Ns, E, R));
reachable([], _G, R) ->
    R.

reach([N | Ns], E, L) ->
    reach(Ns, E, [{N, E} | L]);
reach([], _E, L) ->
    L.

tspec(func)        -> {atom, atom, atom};
tspec(fun_edge)    -> {tspec(func), tspec(func)};
tspec(def_at)      -> {tspec(func), atom};
tspec(pre_call_at) -> {tspec(fun_edge), atom}.

%% -> {ok, OldXrefRel, NewState} | throw(Error)
do_remove_release(S, RelName) ->
    case dict:find(RelName, S#xref.releases) of
	error ->
	    throw_error({no_such_release, RelName});
	{ok, XRel} ->
	    S1 = take_down(S),
	    S2 = remove_rel(S1, RelName),
	    {ok, XRel, S2}
    end.

%% -> {ok, OldXrefApp, NewState} | throw(Error)
do_remove_application(S, AppName) ->
    case dict:find(AppName, S#xref.applications) of
	error ->
	    throw_error({no_such_application, AppName});
	{ok, XApp} ->
	    S1 = take_down(S),
	    S2 = remove_apps(S1, [AppName]),
	    {ok, XApp, S2}
    end.

%% -> {ok, OldXMod, NewState} | throw(Error)
do_remove_module(S, Module) ->
    case dict:find(Module, S#xref.modules) of
	error ->
	    throw_error({no_such_module, Module});
	{ok, XMod} ->
	    S1 = take_down(S),
	    {ok, XMod, remove_modules(S1, [Module])}
    end.

remove_rel(S, RelName) ->
    Rels = [RelName],
    Fun = fun({A,XApp}, L) when XApp#xref_app.rel_name == Rels ->
		  [A | L];
	     (_, L) -> L
	  end,
    Apps = foldl(Fun, [], dict:dict_to_list(S#xref.applications)),
    S1 = remove_apps(S, Apps),
    NewReleases = remove_erase(Rels, S1#xref.releases),
    S1#xref{releases = NewReleases}.

remove_apps(S, Apps) ->
    Fun = fun({M,XMod}, L) ->
		  case XMod#xref_mod.app_name of
		      [] -> L;
		      [AppName] -> [{AppName,M} | L]
		  end
	  end,
    Ms = foldl(Fun, [], dict:dict_to_list(S#xref.modules)),
    Modules = to_external(image(relation(Ms), from_list(Apps))),
    S1 = remove_modules(S, Modules),
    NewApplications = remove_erase(Apps, S1#xref.applications),
    S1#xref{applications = NewApplications}.

remove_modules(S, Modules) ->
    NewModules = remove_erase(Modules, S#xref.modules),
    S#xref{modules = NewModules}.

remove_erase([K | Ks], D) ->
    remove_erase(Ks, dict:erase(K, D));
remove_erase([], D) ->
    D.

do_add_libraries(Path, Verbose, State) ->
    message(Verbose, lib_search, []),
    {C, E} = xref_utils:list_path(Path, [?Suffix]),    
    message(Verbose, done, []),
    MDs = to_external(relation_to_family(relation(C))),
    %% message(Verbose, lib_check, []),
    Reply = check_file(MDs, [], E, Path, State),
    %% message(Verbose, done, []),
    Reply.

%%check_file([{_M, [{_N, Dir, File} | _]} | MDs], L, E, Path, State) ->
%%    case beam_lib:version(filename:join(Dir, File)) of
%%	{ok, {Module, _Version}} ->
%%	    XLib = #xref_lib{name = Module, dir = Dir},
%%	    check_file(MDs, [{Module,XLib} | L], E, Path, State);
%%	Error ->
%%	    check_file(MDs, L, [Error | E], Path, State)
%%    end;
check_file([{Module, [{_N, Dir, _File} | _]} | MDs], L, E, Path, State) ->
    XLib = #xref_lib{name = Module, dir = Dir},
    check_file(MDs, [{Module,XLib} | L], E, Path, State);
check_file([], L, [], Path, State) ->
    D = dict:list_to_dict(L),
    State1 = State#xref{library_path = Path, libraries = D},
    %% Take down everything, that's simplest.
    NewState = take_down(State1),
    {ok, NewState};
check_file([], _L, [E | _], _Path, _State) ->
    E.

%% -> {ok, NewState} | Error
%% Finding libraries may fail.
do_set_up(S, _VerboseOpt) when S#xref.variables /= not_set_up ->
    {ok, S};
do_set_up(S, VerboseOpt) ->
    message(VerboseOpt, set_up, []),
    Reply = (catch do_set_up(S)),
    message(VerboseOpt, done, []),
    Reply.

%% If data has been supplied using add_module/9 (and that is the only
%% sanctioned way), then DefAt, L, X, LCallAt, XCallAt, CallAt, XC, LC, 
%% and LU are  guaranteed to be functions (with all supplied 
%% modules as domain (disregarding unknown modules, that is, modules 
%% not supplied but hosting unknown functions)).
%% As a consequence, V and E are also functions. V is defined for unknown
%% modules also.
%% UU is also a function (thanks to xsets:difference_of_families/2...).
%% XU on the other hand can be a partial function (that is, not defined 
%% for all modules). O is derived from XU, so O is also partial.
%% The inverse variables - LC_1, XC_1, E_1 and EE_1 - are all partial.
%% B is also partial.
do_set_up(S) when S#xref.mode == functions ->
    ModDictList = dict:dict_to_list(S#xref.modules),
    [DefAt0, L, X0, LCallAt, XCallAt, CallAt, LC, XC, LU, 
     EE, ECallAt, UC, LPredefined] = make_families(ModDictList, 14),
    
    {XC_1, XU, XPredefined} = do_set_up_1(XC),
    LC_1 = user_family(family_union(LC)),
    E_1 = union_of_families(XC_1, LC_1),
    Predefined = union_of_families(XPredefined, LPredefined),

    %% Add "hidden" functions to the exports.
    X1 = union_of_families(X0, Predefined),

    F = union_of_families(L, X1),
    V = union_of_families(F, XU),
    E = union_of_families(LC, XC),

    M = domain(V),
    M2A = make_M2A(ModDictList),
    {A2R,A} = make_A2R(S#xref.applications),
    R = from_list(dict:fetch_keys(S#xref.releases)),

    %% Converting from edges of functions to edges of modules.
    VEs = family_union(E),
    ME = substitution(fun({{M1,_F1,_A1},{M2,_F2,_A2}}) -> {M1,M2} end, VEs),
    ME2AE = multiple_compositions({M2A, M2A}, ME),

    AE = range(ME2AE),
    AE2RE = multiple_compositions({A2R, A2R}, AE),
    RE = range(AE2RE),

    %% Undef is the union of U0 and Lib:
    {Undef, U0, Lib} = make_libs(XU, F, S#xref.library_path, S#xref.libraries),
    {B, U} = make_builtins(U0),
    % If we have 'used' too, then there will be a set LU U XU...
    UU = difference_of_families(difference_of_families(F, LU), XU),
    DefAt = make_defat(Undef, DefAt0),

    %% Inter Call Graph.
    EE_1 = user_family(family_union(EE)),

    ?FORMAT("DefAt ~p~n", [DefAt]),
    ?FORMAT("U=~p~nLib=~p~nB=~p~nLU=~p~nXU=~p~nUU=~p~n", [U,Lib,B,LU,XU,UU]),
    ?FORMAT("E_1=~p~nLC_1=~p~nXC_1=~p~n", [E_1,LC_1,XC_1]),
    ?FORMAT("EE=~p~nEE_1=~p~nECallAt=~p~n", [EE, EE_1, ECallAt]),

    AM = domain(F),
    LM = domain(Lib),
    UM = difference(difference(domain(U), AM), LM),
    X = union_of_families(X1, Lib),

    UC_1 = user_family(family_union(UC)),

    Vs = [{'L',L}, {'X',X},{'F',F},{'U',U},{'B',B},{'UU',UU},
	  {'XU',XU},{'LU',LU},{'V',V},{v,V},
	  {'LC',{LC,LC_1}},{'XC',{XC,XC_1}},{'E',{E,E_1}},{e,{E,E_1}},
	  {'EE',{EE,EE_1}},{'UC',{UC,UC_1}},
	  {'M',M},{'A',A},{'R',R},
	  {'AM',AM},{'UM',UM},{'LM',LM},
	  {'ME',ME},{'AE',AE},{'RE',RE},
	  {me2ae, ME2AE},{ae, AE2RE},{m2a, M2A},{a2r, A2R},
	  {def_at, DefAt}, {call_at, CallAt}, {e_call_at, ECallAt},
	  {l_call_at, LCallAt}, {x_call_at, XCallAt}],
    finish_set_up(S, Vs);
do_set_up(S) when S#xref.mode == modules ->
    ModDictList = dict:dict_to_list(S#xref.modules),
    [X0, I0] = make_families(ModDictList, 3),
    I = family_union(I0),
    AM = domain(X0),
    
    {XU, Predefined} = make_predefined(I, AM),
    %% Add "hidden" functions to the exports.
    X1 = union_of_families(X0, Predefined),
    V = union_of_families(X1, XU),

    M = union(AM, domain(XU)),
    M2A = make_M2A(ModDictList),
    {A2R,A} = make_A2R(S#xref.applications),
    R = from_list(dict:fetch_keys(S#xref.releases)),
    
    ME = substitution(fun({M1,{M2,_F2,_A2}}) -> {M1,M2} end, 
		      family_to_relation(I0)),
    ME2AE = multiple_compositions({M2A, M2A}, ME),

    AE = range(ME2AE),
    AE2RE = multiple_compositions({A2R, A2R}, AE),
    RE = range(AE2RE),

    %% Undef is the union of U0 and Lib:
    {_Undef, U0, Lib} = 
	make_libs(XU, X1, S#xref.library_path,S#xref.libraries),
    {B, U} = make_builtins(U0),

    LM = domain(Lib),
    UM = difference(difference(domain(U), AM), LM),
    X = union_of_families(X1, Lib),

    Empty = empty_set(),
    Vs = [{'X',X},{'U',U},{'B',B},{'XU',XU},{v,V}, 
	  {e,{Empty,Empty}},
	  {'M',M},{'A',A},{'R',R},
	  {'AM',AM},{'UM',UM},{'LM',LM},
	  {'ME',ME},{'AE',AE},{'RE',RE},
	  {me2ae, ME2AE},{ae, AE2RE},{m2a, M2A},{a2r, A2R},
	  {def_at, Empty}, {call_at, Empty}, {e_call_at, Empty},
	  {l_call_at, Empty}, {x_call_at, Empty}],
    finish_set_up(S, Vs).

finish_set_up(S, Vs) ->
    T = do_finish_set_up(Vs, dict:new()),
    S1 = S#xref{variables = T},
    %% io:format("~p <= state <= ~p~n", [pack:lsize(S), pack:usize(S)]),
    {ok, S1}.
    
do_finish_set_up([{Key, Value} | Vs], T) ->
    {Type, OType} = var_type(Key),
    Val = #xref_var{name = Key, value = Value, vtype = predef, 
		    otype = OType, type = Type},
    T1 = dict:store(Key, Val, T),
    do_finish_set_up(Vs, T1);
do_finish_set_up([], T) ->
    T.

var_type('B')  -> {function, vertex};
var_type('F')  -> {function, vertex};
var_type('L')  -> {function, vertex};
var_type('LU') -> {function, vertex};
var_type('U')  -> {function, vertex};
var_type('UU') -> {function, vertex};
var_type('V')  -> {function, vertex};
var_type('X')  -> {function, vertex};
var_type('XU') -> {function, vertex};
var_type('A')  -> {application, vertex};
var_type('AM') -> {module, vertex};
var_type('LM') -> {module, vertex};
var_type('M')  -> {module, vertex};
var_type('UM') -> {module, vertex};
var_type('R')  -> {release, vertex};
var_type('E')  -> {function, edge};
var_type('EE') -> {function, edge};
var_type('LC') -> {function, edge};
var_type('UC') -> {function, edge};
var_type('XC') -> {function, edge};
var_type('AE') -> {application, edge};    
var_type('ME') -> {module, edge};    
var_type('RE') -> {release, edge};    
var_type(_)    -> {foo, bar}.

make_families(ModDictList, N) ->
    Fun1 = fun({_,XMod}) -> XMod#xref_mod.data end,
    Ss = from_sets(map(Fun1, ModDictList)),
    %% io:format("~n~p <= module data <= ~p~n", 
    %%           [pack:lsize(Ss), pack:usize(Ss)]),
    make_fams(N, Ss, []).

make_fams(1, _Ss, L) ->
    L;
make_fams(I, Ss, L) ->
    Fun = fun(R) -> {element(1, R), element(I, R)} end,
    make_fams(I-1, Ss, [substitution(Fun, Ss) | L]).

make_M2A(ModDictList) ->
    Fun = fun({M,XMod}) -> {M, XMod#xref_mod.app_name} end,
    Mod0 = family_of_subsets(map(Fun, ModDictList)),
    Mod = family_to_relation(Mod0),
    Mod.

make_A2R(ApplDict) ->
    AppDict = dict:dict_to_list(ApplDict),
    Fun = fun({A,XApp}) -> {A, XApp#xref_app.rel_name} end,
    Appl0 = family_of_subsets(map(Fun, AppDict)), 
    AllApps = domain(Appl0),
    Appl = family_to_relation(Appl0),
    {Appl, AllApps}.

do_set_up_1(XC) ->
    %% Call Graph cross reference...
    XCp = family_union(XC),
    XC_1 = user_family(XCp),

    %% I - functions used externally from some module
    %% XU  - functions used externally per module.
    I = range(XCp),

    {XU, XPredefined} = make_predefined(I, domain(XC)),
    {XC_1, XU, XPredefined}.

make_predefined(I, CallingModules) ->
    XPredefined0 = predefined_funs(I),
    XPredefined1 = inverse(projection(1, XPredefined0)),
    %% predefined funs in undefined modules are still undefined...
    XPredefined2 = restriction(XPredefined1, CallingModules),
    XPredefined = relation_to_family(XPredefined2),
    XU = family_partition(1, I),
    {XU, XPredefined}.

predefined_funs(Functions) ->
    specification(predef_fun(), Functions).

predef_fun() ->
    PredefinedFuns = xref_utils:predefined_functions(),
    fun({_M,?VAR_EXPR,_A}) -> true;
       ({_M,F,A}) -> member({F,A}, PredefinedFuns)
       end.

make_defat(Undef, DefAt0) ->
    % Complete DefAt with unknown functions:
    DAL0 = map(fun({M,Vs}) -> {M,map(fun(A) -> {A,0} end,Vs)} end, 
	       to_external(Undef)),
    DAL = xref_utils:xset(DAL0, type(DefAt0)),
    union_of_families(DefAt0, DAL).

%% -> {Unknown U Lib, Unknown, Lib} | throw(Error)
make_libs(XU, F, LibPath, LibDict) ->
    Undef = difference_of_families(XU, F),
    UM = domain(family_to_relation(Undef)),
    Fs = case is_empty_set(UM) of
	     true ->
		 [];
	     false when LibPath == code_path ->
		 BFun = fun(M, A) -> case xref_utils:find_beam(M) of
					 {ok, File} -> [File | A];
					 _ -> A
				     end
			end,
		 foldl(BFun, [], to_external(UM));
	     false ->
		 Libraries = dict:dict_to_list(LibDict),
		 Lb = restriction(relation(Libraries), UM),
		 MFun = fun({M,XLib}) -> 
				#xref_lib{dir = Dir} = XLib,
				xref_utils:module_filename(Dir, M)
			end,
		 map(MFun, to_external(Lb))
	     end,
    Fun = fun(FileName) -> 
		  case beam_lib:chunks(FileName, [exports]) of
		      {ok, {M, [{exports,X}]}} ->
			  Exports = xref_utils:fa_to_mfa(X, M),
			  {M, Exports};
		      Error ->
			  throw(Error)
		  end
	  end,
    LF = from_term(map(Fun, Fs)),
    %% Undef is the first argument to make sure that the whole of LF
    %% becomes garbage:
    Lib = intersection_of_families(Undef, LF),
    U = difference_of_families(Undef, Lib),
    {Undef, U, Lib}.

make_builtins(U0) ->
    Tmp = family_to_relation(U0),
    Fun2 = fun({_M, {erts_debug, apply, 4}}) -> true;
	      ({_M,{M,F,A}}) -> erlang:is_builtin(M, F, A) end,
    B = relation_to_family(specification(Fun2, Tmp)),
    U = difference_of_families(U0, B),
    {B, U}.

% Returns a family, that may not be defined for all modules.
user_family(R) ->
    family_partition(fun({_MFA1, {M2,_,_}}) -> M2 end, R).

do_variables(State) ->
    Fun = fun({Name, #xref_var{vtype = user}}, {P,U}) -> 
		  {P,[Name | U]};
	     ({Name, #xref_var{vtype = predef}}, A={P,U}) -> 
		  case atom_to_list(Name) of
		      [H|_] when H>= $a, H=<$z -> A;
		      _Else -> {[Name | P], U}
		  end;
	     ({{tmp, V}, _}, A) -> 
		  io:format("Bug in ~p: temporary ~p~n", [?MODULE, V]), A;
	     (_V, A) -> A
	  end,
    {U,P} = foldl(Fun, {[],[]}, dict:dict_to_list(State#xref.variables)),
    {sort(P), sort(U)}.

%% Throws away the variables derived from raw data.
take_down(S) when S#xref.variables == not_set_up ->
    S;
take_down(S) ->
    S#xref{variables = not_set_up}.

make_query(Format, Args) ->
    flatten(io_lib:format(Format, Args)).

set_defaults([O | Os], [[V] | Vs], State) ->
    NewState = set_def(O, V, State),
    set_defaults(Os, Vs, NewState);
set_defaults([], [], State) ->
    State.

set_def(builtins, Value, State) ->
    State#xref{builtins_default = Value};
set_def(recurse, Value, State) ->
    State#xref{recurse_default = Value};
set_def(verbose, Value, State) ->
    State#xref{verbose_default = Value};
set_def(warnings, Value, State) ->
    State#xref{warnings_default = Value}.

option_values([Option | Options], State) ->
    Default = current_default(State, Option),
    [{Option, [Default,true,false]} | option_values(Options, State)];
option_values([], _State) ->
    [].

current_default(State, builtins) ->
    State#xref.builtins_default;
current_default(State, recurse) ->
    State#xref.recurse_default;
current_default(State, verbose) ->
    State#xref.verbose_default;
current_default(State, warnings) ->
    State#xref.warnings_default.

%% sets are used here to avoid long execution times
do_info(S, modules) ->
    D = sort(dict:dict_to_list(S#xref.modules)),
    map(fun({_M,XMod}) -> mod_info(XMod) end, D);
do_info(S, applications) ->
    AppMods = to_external(relation_to_family(relation(app_mods(S)))),
    Sum = sum_mods(S, AppMods),
    map(fun(AppSum) -> app_info(AppSum, S) end, Sum);
do_info(S, releases) ->
    {RA, RRA} = rel_apps(S),
    rel_apps_sums(RA, RRA, S);
do_info(S, libraries) ->
    D = sort(dict:dict_to_list(S#xref.libraries)),
    map(fun({_L,XLib}) -> lib_info(XLib) end, D);
do_info(_S, I) ->
    error({no_such_info, I}).
		      
do_info(S, Type, E) when atom(E) ->
    do_info(S, Type, [E]);
do_info(S, modules, Modules0) when list(Modules0) ->
    Modules = to_external(from_list(Modules0)),
    XMods = find_info(Modules, S#xref.modules, no_such_module),
    map(fun(XMod) -> mod_info(XMod) end, XMods);
do_info(S, applications, Applications) when list(Applications) ->
    _XA = find_info(Applications, S#xref.applications, no_such_application),
    AM = relation(app_mods(S)),
    App = from_list(Applications),
    AppMods_S = relation_to_family(restriction(AM, App)),
    AppSums = sum_mods(S, to_external(AppMods_S)),
    map(fun(AppSum) -> app_info(AppSum, S) end, AppSums);
do_info(S, releases, Releases) when list(Releases) ->
    _XR = find_info(Releases, S#xref.releases, no_such_release),
    {AR, RRA} = rel_apps(S),
    AR_S = restriction(2, relation(AR), from_list(Releases)),
    rel_apps_sums(to_external(AR_S), RRA, S);
do_info(S, libraries, Libraries0) when list(Libraries0) ->
    Libraries = to_external(from_list(Libraries0)),
    XLibs = find_info(Libraries, S#xref.libraries, no_such_library),
    map(fun(XLib) -> lib_info(XLib) end, XLibs);
do_info(_S, I, J) when list(J) ->
    throw_error({no_such_info, I}).

find_info([E | Es], Dict, Error) ->
    case dict:find(E, Dict) of
	error ->
	    throw_error({Error, E});
	{ok, X} ->
	    [X | find_info(Es, Dict, Error)]
    end;
find_info([], _Dict, _Error) ->    
    [].

%% -> {[{AppName, RelName}], [{RelName, XApp}]}
rel_apps(S) ->
    D = sort(dict:dict_to_list(S#xref.applications)),
    Fun = fun({_A, XApp}, Acc={AR, RRA}) ->
		  case XApp#xref_app.rel_name of
		      [] -> Acc;
		      [R] ->
			  AppName = XApp#xref_app.name,
			  {[{AppName, R} | AR], [{R, XApp} | RRA]}
		  end
	  end,
    foldl(Fun, {[], []}, D).

%% -> [{{RelName, [XApp]}, Sums}]
rel_apps_sums(AR, RRA0, S) ->
    AppMods = app_mods(S), % [{AppName, XMod}]
    RRA1 = relation_to_family(relation(RRA0)),
    RRA = inverse(projection(1, RRA1)), 
    %% RRA is [{RelName,{RelName,[XApp]}}]
    RelMods = composition1(relation(AR), relation(AppMods)),
    RelAppsMods = composition1(RRA, RelMods),
    RelsAppsMods = to_external(relation_to_family(RelAppsMods)),
    %% [{{RelName, [XApp]}, [XMod]}]
    Sum = sum_mods(S, RelsAppsMods),
    map(fun(RelAppsSums) -> rel_info(RelAppsSums, S) end, Sum).

%% -> [{AppName, XMod}]
app_mods(S) ->
    D = sort(dict:dict_to_list(S#xref.modules)),
    Fun = fun({_M,XMod}, Acc) -> 
		  case XMod#xref_mod.app_name of
		      [] -> Acc;
		      [AppName] -> [{AppName, XMod} | Acc]
		  end
	  end,
    foldl(Fun, [], D).

mod_info(XMod) ->
    #xref_mod{name = M, app_name = AppName, builtins = BuiltIns, 
	       dir = Dir, info = Info} = XMod,
    App = sup_info(AppName),
    {M, [{application, App}, {builtins, BuiltIns}, {directory, Dir} | Info]}.

app_info({AppName, ModSums}, S) ->
    XApp = dict:fetch(AppName, S#xref.applications),
    #xref_app{rel_name = RelName, vsn = Vsn, dir = Dir} = XApp,
    Release = sup_info(RelName),
    {AppName, [{directory,Dir}, {release, Release}, {version,Vsn} | ModSums]}.
    
rel_info({{RelName, XApps}, ModSums}, S) ->
    NoApps = length(XApps),
    XRel = dict:fetch(RelName, S#xref.releases),
    Dir = XRel#xref_rel.dir,
    {RelName, [{directory, Dir}, {no_applications, NoApps} | ModSums]}.

lib_info(XLib) ->
    #xref_lib{name = LibName, dir = Dir} = XLib,
    {LibName, [{directory,Dir}]}.

sup_info([]) -> [];
sup_info([Name]) ->
    [Name].

sum_mods(S, AppsMods) ->
    sum_mods(S, AppsMods, []).

sum_mods(S, [{N, XMods} | NX], L) ->
    sum_mods(S, NX, [{N, no_sum(S, XMods)} | L]);
sum_mods(_S, [], L) ->
    reverse(L).

no_sum(S, L) when S#xref.mode == functions ->
    no_sum(L, 0, 0, 0, 0, 0, 0, 0, 0, length(L));
no_sum(S, L) when S#xref.mode == modules ->
    [{no_analyzed_modules, length(L)}].

no_sum([XMod | D], C0, UC0, LC0, XC0, UFC0, L0, X0, EV0, NoM) ->
    [{no_calls, {C,UC}}, 
     {no_function_calls, {LC,XC,UFC}},
     {no_functions, {L,X}},
     {no_inter_function_calls, EV}] = XMod#xref_mod.info,
    no_sum(D, C0+C, UC0+UC, LC0+LC, XC0+XC, UFC0+UFC, L0+L, X0+X, EV0+EV, NoM);
no_sum([], C, UC, LC, XC, UFC, L, X, EV, NoM) ->
    [{no_analyzed_modules, NoM},
     {no_calls, {C,UC}}, 
     {no_function_calls, {LC,XC,UFC}},
     {no_functions, {L,X}}, 
     {no_inter_function_calls, EV}].

is_path([S | Ss]) ->
    case is_string(S, 31) of
	true -> 
	    is_path(Ss);
	false ->
	    false
    end;
is_path([]) -> 
    true;
is_path(_) -> 
    false.

is_string([], _) ->
    false;
is_string(Term, C) ->
    is_string1(Term, C).

is_string1([H | T], C) when H > C, H < 127 -> 
    is_string1(T, C);
is_string1([], _) -> 
    true;
is_string1(_, _) -> 
    false.
    
module_file(XMod) ->
    xref_utils:module_filename(XMod#xref_mod.dir, XMod#xref_mod.name).

warnings(_Flag, _Message, []) -> true;
warnings(Flag, Message, [F | Fs]) ->
    message(Flag, Message, F),
    warnings(Flag, Message, Fs).

%% pack(term()) -> term()
%%
%% The identify function. The returned term does not use more heap
%% than the given term. Tuples that are equal (==/2) are made 
%% "the same".
%%
%% The process dictionary is used because it seems to be faster than
%% anything else right now...
%%
%pack(T) -> T;
pack(T) ->    
    PD = erase(),
    NT = pack1(T),
    %% true = T == NT,
    %% io:format("erasing ~p elements...~n", [length(erase())]),
    erase(), % wasting heap (and time)...
    map(fun({K,V}) -> put(K, V) end, PD),
    NT.

pack1(C) when constant(C) ->
    C;
pack1([T | Ts]) ->
    %% don't store conscells...
    [pack1(T) | pack1(Ts)];
%% Optimization.
pack1(T={Mod,Fun,_}) when atom(Mod), atom(Fun) -> % MFA
    case get(T) of
	undefined -> put(T, T), T;
	NT -> NT
    end;
pack1({C, L}) when list(L) -> % CallAt
    {pack1(C), L};
pack1({MFA, L}) when integer(L) -> % DefAt
    {pack1(MFA), L};
%% End optimization.
pack1([]) ->
    [];
pack1(T) -> % when tuple(T)
    case get(T) of
	undefined ->
	    NT = tpack(T, size(T), []),
	    put(NT, NT),
	    NT;
	NT ->
	    NT
    end.

tpack(_T, 0, L) ->
    list_to_tuple(L);
tpack(T, I, L) ->
    tpack(T, I-1, [pack1(element(I, T)) | L]).

message(true, What, Arg) ->
    case What of
	reading_beam ->
	    io:format("~s... ", Arg);
	skipped_beam ->
	    io:format("skipped (no debug information)~n", Arg);
	no_debug_info ->
	    io:format("Skipping ~s (no debug information)~n", Arg);
	unresolved ->
	    io:format("~s:~p: Unresolved call to ~p~n", Arg);
	unresolved_summary1 ->
	    io:format("~p: 1 unresolved call~n", Arg);
	unresolved_summary ->
	    io:format("~p: ~p unresolved calls~n", Arg);
	jam ->
	    io:format("Skipping ~s (probably JAM file)~n", [Arg]);
	unreadable ->
	    io:format("Skipping ~s (unreadable)~n", [Arg]);
	xref_attr ->
	    io:format("~s: Skipping xref attribute ~p~n", Arg);
	lib_search ->
	    io:format("Scanning library path for BEAM files... ", []);
	lib_check ->
	    io:format("Checking library files... ", []);
	set_up ->
	    io:format("Setting up...", Arg);
	done ->
	    io:format("done~n", Arg);
	error ->
	    io:format("error~n", Arg);
	Else ->
	    io:format("~p~n", [Else])
    end;
message(_, _, _) ->
    true.

throw_error(Reason) ->
    throw(error(Reason)).

error(Reason) ->
    {error, ?MODULE, Reason}.