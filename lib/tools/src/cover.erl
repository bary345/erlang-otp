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
%% Portions created by Ericsson are Copyright 1999, Ericsson Utvecklings
%% AB. All Rights Reserved.''
%% 
%%     $Id$
%%
-module(cover).

%%
%% This module implements the Erlang coverage tool. The module named
%% cover_web implements a user interface for the coverage tool to run
%% under webtool.
%% 
%% ARCHITECTURE
%% The coverage tool consists of one process on each node involved in
%% coverage analysis. The process is registered as 'cover_server'
%% (?SERVER).  All cover_servers in the distributed system are linked
%% together.  The cover_server on the 'main' node is in charge, and it
%% traps exits so it can detect nodedown or process crashes on the
%% remote nodes. This process is implemented by the functions
%% init_main/1 and main_process_loop/1. The cover_server on the remote
%% nodes are implemented by the functions init_remote/2 and
%% remote_process_loop/1.
%%
%% TABLES
%% Each nodes has an ets table named 'cover_internal_data_table'
%% (?COVER_TABLE).  This table contains the coverage data and is
%% continously updated when cover compiled code is executed.
%% 
%% The main node owns a table named
%% 'cover_collected_remote_data_table' (?COLLECTION_TABLE). This table
%% contains data which is collected from remote nodes (either when a
%% remote node is stopped with cover:stop/1 or when analysing. When
%% analysing, data is even moved from the ?COVER_TABLE on the main
%% node to the ?COLLECTION_TABLE.
%%
%% The main node also has a table named 'cover_binary_code_table'
%% (?BINARY_TABLE). This table contains the binary code for each cover
%% compiled module. This is necessary so that the code can be loaded
%% on remote nodes that are started after the compilation.
%%


%% External exports
-export([start/0, start/1,
	 compile/1, compile/2, compile_module/1, compile_module/2,
	 compile_directory/0, compile_directory/1, compile_directory/2,
	 compile_beam/1, compile_beam_directory/0, compile_beam_directory/1,
	 analyse/1, analyse/2, analyse/3, analyze/1, analyze/2, analyze/3,
	 analyse_to_file/1, analyse_to_file/2, analyse_to_file/3,
	 analyze_to_file/1, analyze_to_file/2, analyze_to_file/3,
	 export/1, export/2, import/1,
	 modules/0, imported/0, imported_modules/0, which_nodes/0, is_compiled/1,
	 reset/1, reset/0,
	 stop/0, stop/1]).
-export([remote_start/1]).
%-export([bump/5]).
-export([transform/4]). % for test purposes

-record(main_state, {compiled=[],           % [{Module,File}]
		     imported=[],           % [{Module,File,ImportFile}]
		     stopper,               % undefined | pid()
		     nodes=[]}).            % [Node]

-record(remote_state, {compiled=[],         % [{Module,File}]
		       main_node}).         % atom()

-record(bump, {module   = '_',              % atom()
	       function = '_',              % atom()
	       arity    = '_',              % integer()
	       clause   = '_',              % integer()
	       line     = '_'               % integer()
	      }).
-define(BUMP_REC_NAME,bump).

-record(vars, {module,                      % atom() Module name
	       vsn,                         % atom()
	       
	       init_info=[],                % [{M,F,A,C,L}]

	       function,                    % atom()
	       arity,                       % int()
	       clause,                      % int()
	       lines,                       % [int()]
	       depth,                       % int()
	       is_guard=false               % boolean
	      }).

-define(COVER_TABLE, 'cover_internal_data_table').
-define(BINARY_TABLE, 'cover_binary_code_table').
-define(COLLECTION_TABLE, 'cover_collected_remote_data_table').
-define(TAG, cover_compiled).
-define(SERVER, cover_server).

-include_lib("stdlib/include/ms_transform.hrl").

%%%----------------------------------------------------------------------
%%% External exports
%%%----------------------------------------------------------------------

%% start() -> {ok,Pid} | {error,Reason}
%%   Pid = pid()
%%   Reason = {already_started,Pid} | term()
start() ->
    case whereis(?SERVER) of
	undefined ->
	    Starter = self(),
	    Pid = spawn(fun() -> init_main(Starter) end),
	    Ref = erlang:monitor(process,Pid),
	    Return = 
		receive 
		    {?SERVER,started} -> 
			{ok,Pid};
		    {'DOWN', Ref, _Type, _Object, Info} -> 
			{error,Info}
		end,
	    erlang:demonitor(Ref),
	    Return;
	Pid ->
	    {error,{already_started,Pid}}
    end.

%% start(Nodes) -> {ok,StartedNodes}
%%   Nodes = Node | [Node,...]
%%   Node = atom()
start(Node) when atom(Node) ->
    start([Node]);
start(Nodes) ->
    call({start_nodes,remove_myself(Nodes,[])}).

%% compile(ModFile) ->
%% compile(ModFile, Options) ->
%% compile_module(ModFile) -> Result
%% compile_module(ModFile, Options) -> Result
%%   ModFile = Module | File
%%     Module = atom()
%%     File = string()
%%   Options = [Option]
%%     Option = {i,Dir} | {d,Macro} | {d,Macro,Value}
%%   Result = {ok,Module} | {error,File}
compile(ModFile) ->
    compile_module(ModFile, []).
compile(ModFile, Options) ->
    compile_module(ModFile, Options).
compile_module(ModFile) when atom(ModFile);
			     list(ModFile) ->
    compile_module(ModFile, []).
compile_module(Module, Options) when atom(Module), list(Options) ->
    compile_module(atom_to_list(Module), Options);
compile_module(File, Options) when list(File), list(Options) ->
    WithExt = case filename:extension(File) of
		  ".erl" ->
		      File;
		  _ ->
		      File++".erl"
	      end,
    AbsFile = filename:absname(WithExt),
    [R] = compile_modules([AbsFile], Options),
    R.

%% compile_directory() ->
%% compile_directory(Dir) ->
%% compile_directory(Dir, Options) -> [Result] | {error,Reason}
%%   Dir = string()
%%   Options - see compile/1
%%   Result - see compile/1
%%   Reason = eacces | enoent
compile_directory() ->
    case file:get_cwd() of
	{ok, Dir} ->
	    compile_directory(Dir, []);
	Error ->
	    Error
    end.
compile_directory(Dir) when list(Dir) ->
    compile_directory(Dir, []).
compile_directory(Dir, Options) when list(Dir), list(Options) ->
    case file:list_dir(Dir) of
	{ok, Files} ->
	    
	    %% Filter out all erl files (except cover.erl)
	    ErlFileNames =
		lists:filter(fun("cover.erl") ->
				     false;
				(File) ->
				     case filename:extension(File) of
					 ".erl" -> true;
					 _ -> false
				     end
			     end,
			     Files),

	    %% Create a list of .erl file names (incl path) and call
	    %% compile_modules/2 with the list of file names.
	    ErlFiles = lists:map(fun(ErlFileName) ->
					 filename:join(Dir, ErlFileName)
				 end,
				 ErlFileNames),
	    compile_modules(ErlFiles, Options);
	Error ->
	    Error
    end.

compile_modules(Files,Options) ->
    Options2 = lists:filter(fun(Option) ->
				    case Option of
					{i, Dir} when list(Dir) -> true;
					{d, _Macro} -> true;
					{d, _Macro, _Value} -> true;
					_ -> false
				    end
			    end,
			    Options),
    compile_modules(Files,Options2,[]).

compile_modules([File|Files], Options, Result) ->
    R = call({compile, File, Options}),
    compile_modules(Files,Options,[R|Result]);
compile_modules([],_Opts,Result) ->
    reverse(Result).


%% compile_beam(ModFile) -> Result | {error,Reason}
%%   ModFile - see compile/1
%%   Result - see compile/1
%%   Reason = non_existing | already_cover_compiled
compile_beam(Module) when atom(Module) ->
    case code:which(Module) of
	non_existing -> 
	    {error,non_existing};
	?TAG ->
	    compile_beam(Module,?TAG);
	File ->
	    compile_beam(Module,File)
    end;
compile_beam(File) when list(File) ->
    {WithExt,WithoutExt}
	= case filename:rootname(File,".beam") of
	      File ->
		  {File++".beam",File};
	      Rootname ->
		  {File,Rootname}
	      end,
    AbsFile = filename:absname(WithExt),
    Module = list_to_atom(filename:basename(WithoutExt)),
    compile_beam(Module,AbsFile).

compile_beam(Module,File) ->
    call({compile_beam,Module,File}).
    


%% compile_beam_directory(Dir) -> [Result] | {error,Reason}
%%   Dir - see compile_directory/1
%%   Result - see compile/1
%%   Reason = eacces | enoent
compile_beam_directory() ->
    case file:get_cwd() of
	{ok, Dir} ->
	    compile_beam_directory(Dir);
	Error ->
	    Error
    end.
compile_beam_directory(Dir) when list(Dir) ->
    case file:list_dir(Dir) of
	{ok, Files} ->
	    
	    %% Filter out all beam files (except cover.beam)
	    BeamFileNames =
		lists:filter(fun("cover.beam") ->
				     false;
				(File) ->
				     case filename:extension(File) of
					 ".beam" -> true;
					 _ -> false
				     end
			     end,
			     Files),

	    %% Create a list of .beam file names (incl path) and call
	    %% compile_beam/1 for each such file name
	    BeamFiles = lists:map(fun(BeamFileName) ->
					  filename:join(Dir, BeamFileName)
				  end,
				  BeamFileNames),
	    compile_beams(BeamFiles);
	Error ->
	    Error
    end.

compile_beams(Files) ->
    compile_beams(Files,[]).
compile_beams([File|Files],Result) ->
    R = compile_beam(File),
    compile_beams(Files,[R|Result]);
compile_beams([],Result) ->
    reverse(Result).


%% analyse(Module) ->
%% analyse(Module, Analysis) ->
%% analyse(Module, Level) ->
%% analyse(Module, Analysis, Level) -> {ok,Answer} | {error,Error}
%%   Module = atom()
%%   Analysis = coverage | calls
%%   Level = line | clause | function | module
%%   Answer = {Module,Value} | [{Item,Value}]
%%     Item = Line | Clause | Function
%%      Line = {M,N}
%%      Clause = {M,F,A,C}
%%      Function = {M,F,A}
%%        M = F = atom()
%%        N = A = C = integer()
%%     Value = {Cov,NotCov} | Calls
%%       Cov = NotCov = Calls = integer()
%%   Error = {not_cover_compiled,Module}
analyse(Module) ->
    analyse(Module, coverage).
analyse(Module, Analysis) when Analysis==coverage; Analysis==calls ->
    analyse(Module, Analysis, function);
analyse(Module, Level) when Level==line; Level==clause; Level==function;
			    Level==module ->
    analyse(Module, coverage, Level).
analyse(Module, Analysis, Level) when atom(Module),
				      Analysis==coverage; Analysis==calls,
				      Level==line; Level==clause;
				      Level==function; Level==module ->
    call({{analyse, Analysis, Level}, Module}).

analyze(Module) -> analyse(Module).
analyze(Module, Analysis) -> analyse(Module, Analysis).
analyze(Module, Analysis, Level) -> analyse(Module, Analysis, Level).

%% analyse_to_file(Module) ->
%% analyse_to_file(Module, Options) ->
%% analyse_to_file(Module, OutFile) ->
%% analyse_to_file(Module, OutFile, Options) -> {ok,OutFile} | {error,Error}
%%   Module = atom()
%%   OutFile = string()
%%   Options = [Option]
%%     Option = html
%%   Error = {not_cover_compiled,Module} | no_source_code_found |
%%           {file,File,Reason}
%%     File = string()
%%     Reason = term()
analyse_to_file(Module) when atom(Module) ->
    analyse_to_file(Module, outfilename(Module,[]), []).
analyse_to_file(Module, []) when atom(Module) ->
    analyse_to_file(Module, outfilename(Module,[]), []);
analyse_to_file(Module, Options) when atom(Module),
				      list(Options), atom(hd(Options)) ->
    analyse_to_file(Module, outfilename(Module,Options), Options);
analyse_to_file(Module, OutFile) when atom(Module), list(OutFile) ->
    analyse_to_file(Module, OutFile, []).
analyse_to_file(Module, OutFile, Options) when atom(Module), list(OutFile) ->
    call({{analyse_to_file, OutFile, Options}, Module}).

analyze_to_file(Module) -> analyse_to_file(Module).
analyze_to_file(Module, OptOrOut) -> analyse_to_file(Module, OptOrOut).
analyze_to_file(Module, OutFile, Options) -> 
    analyse_to_file(Module, OutFile, Options).

outfilename(Module,Opts) ->
    case lists:member(html,Opts) of
	true ->
	    atom_to_list(Module)++".COVER.html";
	false ->
	    atom_to_list(Module)++".COVER.out"
    end.

%% export(File)
%% export(File,Module) -> ok | {error,Reason}
%%   File = string(); file to write the exported data to
%%   Module = atom()
export(File) ->
    export(File, '_').
export(File, Module) ->
    call({export,File,Module}).

%% import(File) -> ok | {error, Reason}
%%   File = string(); file created with cover:export/1,2
import(File) ->
    call({import,File}).

%% modules() -> [Module]
%%   Module = atom()
modules() ->
   call(modules).

%% imported_modules() -> [Module]
%%   Module = atom()
imported_modules() ->
   call(imported_modules).

%% imported() -> [ImportFile]
%%   ImportFile = string()
imported() ->
   call(imported).

%% which_nodes() -> [Node]
%%   Node = atom()
which_nodes() ->
   call(which_nodes).

%% is_compiled(Module) -> {file,File} | false
%%   Module = atom()
%%   File = string()
is_compiled(Module) when atom(Module) ->
    call({is_compiled, Module}).

%% reset(Module) -> ok | {error,Error}
%% reset() -> ok
%%   Module = atom()
%%   Error = {not_cover_compiled,Module}
reset(Module) when atom(Module) ->
    call({reset, Module}).
reset() ->
    call(reset).

%% stop() -> ok
stop() ->
    call(stop).

stop(Node) when atom(Node) ->
    stop([Node]);
stop(Nodes) ->
    call({stop,remove_myself(Nodes,[])}).

%% bump(Module, Function, Arity, Clause, Line)
%%   Module = Function = atom()
%%   Arity = Clause = Line = integer()
%% This function is inserted into Cover compiled modules, once for each
%% executable line.
%bump(Module, Function, Arity, Clause, Line) ->
%    Key = #bump{module=Module, function=Function, arity=Arity, clause=Clause,
%		line=Line},
%    ets:update_counter(?COVER_TABLE, Key, 1).

call(Request) ->
    Ref = erlang:monitor(process,?SERVER),
    receive {'DOWN', Ref, _Type, _Object, noproc} -> 
	    erlang:demonitor(Ref),
	    start(),
	    call(Request)
    after 0 ->
	    ?SERVER ! {self(),Request},
	    Return = 
		receive 
		    {'DOWN', Ref, _Type, _Object, Info} -> 
			exit(Info);
		    {?SERVER,Reply} -> 
			Reply
		end,
	    erlang:demonitor(Ref),
	    Return
    end.

reply(From, Reply) ->
    From ! {?SERVER,Reply}.
is_from(From) ->
    is_pid(From).

remote_call(Node,Request) ->
    Ref = erlang:monitor(process,{?SERVER,Node}),
    receive {'DOWN', Ref, _Type, _Object, noproc} -> 
	    erlang:demonitor(Ref),
	    {error,node_dead}
    after 0 ->
	    {?SERVER,Node} ! Request,
	    Return = 
		receive 
		    {'DOWN', Ref, _Type, _Object, _Info} -> 
			{error,node_dead};
		    {?SERVER,Reply} -> 
			Reply
		end,
	    erlang:demonitor(Ref),
	    Return
    end.
    
remote_reply(MainNode,Reply) ->
    {?SERVER,MainNode} ! {?SERVER,Reply}.

%%%----------------------------------------------------------------------
%%% cover_server on main node
%%%----------------------------------------------------------------------

init_main(Starter) ->
    register(?SERVER,self()),
    ets:new(?COVER_TABLE, [set, public, named_table]),
    ets:new(?BINARY_TABLE, [set, named_table]),
    ets:new(?COLLECTION_TABLE, [set, public, named_table]),
    process_flag(trap_exit,true),
    Starter ! {?SERVER,started},
    main_process_loop(#main_state{}).

main_process_loop(State) ->
    receive
	{From, {start_nodes,Nodes}} ->
	    ThisNode = node(),
	    StartedNodes = 
		lists:foldl(
		  fun(Node,Acc) ->
			  case rpc:call(Node,cover,remote_start,[ThisNode]) of
			      {ok,RPid} ->
				  link(RPid),
				  [Node|Acc];
			      Error ->
				  io:format("Could not start cover on ~w: ~p\n",
					    [Node,Error]),
				  Acc
			  end
		  end,
		  [],
		  Nodes),

	    %% In case some of the compiled modules have been unloaded they 
	    %% should not be loaded on the new node.
	    {_LoadedModules,Compiled} = 
		get_compiled_still_loaded(State#main_state.nodes,
					  State#main_state.compiled),
	    remote_load_compiled(StartedNodes,Compiled),
	    
	    State1 = 
		State#main_state{nodes = State#main_state.nodes ++ StartedNodes,
				 compiled = Compiled},
	    reply(From, {ok,StartedNodes}),
	    main_process_loop(State1);

	{From, {compile, File, Options}} ->
	    case do_compile(File, Options) of
		{ok, Module} ->
		    remote_load_compiled(State#main_state.nodes,[{Module,File}]),
		    reply(From, {ok, Module}),
		    Compiled = add_compiled(Module, File,
					    State#main_state.compiled),
		    Imported = remove_imported(Module,State#main_state.imported),
		    main_process_loop(State#main_state{compiled = Compiled,
						       imported = Imported});
		error ->
		    reply(From, {error, File}),
		    main_process_loop(State)
	    end;

	{From, {compile_beam, Module, BeamFile0}} ->
	    Compiled0 = State#main_state.compiled,
	    case get_beam_file(Module,BeamFile0,Compiled0) of
		{ok,BeamFile} ->
		    {Reply,Compiled} = 
			case do_compile_beam(Module,BeamFile) of
			    {ok, Module} ->
				remote_load_compiled(State#main_state.nodes,
						     [{Module,BeamFile}]),
				C = add_compiled(Module,BeamFile,Compiled0),
				{{ok,Module},C};
			    error ->
				{{error, BeamFile}, Compiled0};
			    {error,Reason} -> % no abstract code
				{{error, {Reason, BeamFile}}, Compiled0}
			end,
		    reply(From,Reply),
		    Imported = remove_imported(Module,State#main_state.imported),
		    main_process_loop(State#main_state{compiled = Compiled,
						       imported = Imported});
		{error,no_beam} ->
		    %% The module has first been compiled from .erl, and now
		    %% someone tries to compile it from .beam
		    reply(From, 
			  {error,{already_cover_compiled,no_beam_found,Module}}),
		    main_process_loop(State)
	    end;

	{From, {export,OutFile,Module}} ->
	    case file:open(OutFile,[write,binary,raw]) of
		{ok,Fd} ->
		    Reply = 
			case Module of
			    '_' ->
				export_info(State#main_state.imported),
				collect(State#main_state.nodes),
				do_export_table(State#main_state.compiled,
						State#main_state.imported,
						Fd);
			    _ ->
				export_info(Module,State#main_state.imported),
				case is_loaded(Module, State) of
				    {loaded, File} ->
					[{Module,Clauses}] = 
					    ets:lookup(?COVER_TABLE,Module),
					collect(Module, Clauses,
						State#main_state.nodes),
					do_export_table([{Module,File}],[],Fd);
				    {imported, File, ImportFiles} ->
					%% don't know if I should allow this - 
					%% export a module which is only imported
					Imported = [{Module,File,ImportFiles}],
					do_export_table([],Imported,Fd);
				    _NotLoaded ->
					{error,{not_cover_compiled,Module}}
				end
			end,
		    file:close(Fd),
		    reply(From, Reply);
		{error,Reason} ->
		    reply(From, {error, {cant_open_file,OutFile,Reason}})
	    
	    end,
	    main_process_loop(State);
	
	{From, {import,File}} ->
	    case file:open(File,[read,binary,raw]) of
		{ok,Fd} ->
		    Imported = do_import_to_table(Fd,File,
						  State#main_state.imported),
		    reply(From, ok),
		    main_process_loop(State#main_state{imported=Imported});
		{error,Reason} ->
		    reply(From, {error, {cant_open_file,File,Reason}}),
		    main_process_loop(State)
	    end;

	{From, modules} ->
	    %% Get all compiled modules which are still loaded
	    {LoadedModules,Compiled} = 
		get_compiled_still_loaded(State#main_state.nodes,
					  State#main_state.compiled),
	    
	    reply(From, LoadedModules),
	    main_process_loop(State#main_state{compiled=Compiled});

	{From, imported_modules} ->
	    %% Get all modules with imported data
	    ImportedModules = lists:map(fun({Mod,_File,_ImportFile}) -> Mod end,
					State#main_state.imported),
	    reply(From, ImportedModules),
	    main_process_loop(State);

	{From, imported} ->
	    %% List all imported files
	    reply(From, get_all_importfiles(State#main_state.imported,[])),
	    main_process_loop(State);

	{From, which_nodes} ->
	    %% List all imported files
	    reply(From, State#main_state.nodes),
	    main_process_loop(State);

	{From, reset} ->
	    lists:foreach(
	      fun({Module,_File}) -> 
		      do_reset_main_node(Module,State#main_state.nodes)
	      end, 
	      State#main_state.compiled),
	    reply(From, ok),
	    main_process_loop(State#main_state{imported=[]});

	{From, {stop,Nodes}} ->
	    remote_collect('_',Nodes,true),
	    reply(From, ok),
	    State1 = State#main_state{nodes=State#main_state.nodes--Nodes},
	    main_process_loop(State1);

	{From, stop} ->
	    lists:foreach(
	      fun(Node) -> 
		      remote_call(Node,{remote,stop})
	      end,
	      State#main_state.nodes),
	    reload_originals(State#main_state.compiled),
	    reply(From, ok);

	{From, {Request, Module}} ->
	    case is_loaded(Module, State) of
		{loaded, File} ->
		    {Reply,State1} = 
			case Request of
			    {analyse, Analysis, Level} ->
				analyse_info(Module,State#main_state.imported),
				[{Module,Clauses}] = 
				    ets:lookup(?COVER_TABLE,Module),
				collect(Module,Clauses,State#main_state.nodes),
				R = do_analyse(Module, Analysis, Level, Clauses),
				{R,State};
			    
			    {analyse_to_file, OutFile, Opts} ->
				R = case find_source(File) of
					{beam,_BeamFile} ->
					    {error,no_source_code_found};
					ErlFile ->
					    Imported = State#main_state.imported,
					    analyse_info(Module,Imported),
					    [{Module,Clauses}] = 
						ets:lookup(?COVER_TABLE,Module),
					    collect(Module, Clauses,
						    State#main_state.nodes),
					    HTML = lists:member(html,Opts),
					    do_analyse_to_file(Module,OutFile,
							       ErlFile,HTML)
				    end,
				{R,State};
			    
			    is_compiled ->
				{{file, File},State};
			    
			    reset ->
				R = do_reset_main_node(Module,
						       State#main_state.nodes),
				Imported = 
				    remove_imported(Module,
						    State#main_state.imported),
				{R,State#main_state{imported=Imported}}
			end,
		    reply(From, Reply),
		    main_process_loop(State1);
		
		{imported,File,_ImportFiles} ->
		    {Reply,State1} = 
			case Request of
			    {analyse, Analysis, Level} ->
				analyse_info(Module,State#main_state.imported),
				[{Module,Clauses}] = 
				    ets:lookup(?COLLECTION_TABLE,Module),
				R = do_analyse(Module, Analysis, Level, Clauses),
				{R,State};
			    
			    {analyse_to_file, OutFile, Opts} ->
				R = case find_source(File) of
					{beam,_BeamFile} ->
					    {error,no_source_code_found};
					ErlFile ->
					    Imported = State#main_state.imported,
					    analyse_info(Module,Imported),
					    HTML = lists:member(html,Opts),
					    do_analyse_to_file(Module,OutFile,
							   ErlFile,HTML)
				    end,
				{R,State};
			    
			    is_compiled ->
				{false,State};
			    
			    reset ->
				R = do_reset_collection_table(Module),
				Imported = 
				    remove_imported(Module,
						    State#main_state.imported),
				{R,State#main_state{imported=Imported}}
			end,
		    reply(From, Reply),
		    main_process_loop(State1);		    
		
		NotLoaded ->
		    Reply = 
			case Request of
			    is_compiled ->
				false;
			    _ ->
				{error, {not_cover_compiled,Module}}
			end,
		    Compiled = 
			case NotLoaded of
			    unloaded ->
				do_clear(Module),
				remote_unload(State#main_state.nodes,[Module]),
				update_compiled([Module],
						State#main_state.compiled);
			    false ->
				State#main_state.compiled
			end,
		    reply(From, Reply),
		    main_process_loop(State#main_state{compiled=Compiled})
	    end;
	
	{'EXIT',Pid,_Reason} ->
	    %% Exit is trapped on the main node only, so this will only happen 
	    %% there. I assume that I'm only linked to cover_servers on remote 
	    %% nodes, so this must be one of them crashing. 
	    %% Remove node from list!
	    State1 = State#main_state{nodes=State#main_state.nodes--[node(Pid)]},
	    main_process_loop(State1);
	
	get_status ->
	    io:format("~p~n",[State]),
	    main_process_loop(State)
    end.





%%%----------------------------------------------------------------------
%%% cover_server on remote node
%%%----------------------------------------------------------------------

init_remote(Starter,MainNode) ->
    register(?SERVER,self()),
    ets:new(?COVER_TABLE, [set, public, named_table]),
    Starter ! {self(),started},
    remote_process_loop(#remote_state{main_node=MainNode}).



remote_process_loop(State) ->
    receive 
	{remote,load_compiled,Compiled} ->
	    Compiled1 = load_compiled(Compiled,State#remote_state.compiled),
	    remote_reply(State#remote_state.main_node, ok),
	    remote_process_loop(State#remote_state{compiled=Compiled1});

	{remote,unload,UnloadedModules} ->
	    unload(UnloadedModules),
	    Compiled = 
		update_compiled(UnloadedModules, State#remote_state.compiled),
	    remote_reply(State#remote_state.main_node, ok),
	    remote_process_loop(State#remote_state{compiled=Compiled});

	{remote,reset,Module} ->
	    do_reset(Module),
	    remote_reply(State#remote_state.main_node, ok),
	    remote_process_loop(State);

	{remote,collect,Module,CollectorPid} ->
	    MS = 
		case Module of
		    '_' -> ets:fun2ms(fun({M,C}) when is_atom(M) -> C end);
		    _ -> ets:fun2ms(fun({M,C}) when M=:=Module -> C end)
		end,
	    AllClauses = lists:flatten(ets:select(?COVER_TABLE,MS)),
	    
	    %% Sending clause by clause in order to avoid large lists
	    lists:foreach(
	      fun({M,F,A,C,_L}) ->
		      Pattern = 
			  {#bump{module=M, function=F, arity=A, clause=C}, '_'},
		      Bumps = ets:match_object(?COVER_TABLE, Pattern),
		      %% Reset
		      lists:foreach(fun({Bump,_N}) ->
					    ets:insert(?COVER_TABLE, {Bump,0})
				    end,
				    Bumps),
		      CollectorPid ! {chunk,Bumps}
	      end,
	      AllClauses),
	    CollectorPid ! done,
	    remote_reply(State#remote_state.main_node, ok),
	    remote_process_loop(State);

	{remote,stop} ->
	    reload_originals(State#remote_state.compiled),
	    remote_reply(State#remote_state.main_node, ok);

	get_status ->
	    io:format("~p~n",[State]),
	    remote_process_loop(State);

	M ->
	    io:format("WARNING: remote cover_server received\n~p\n",[M]),
	    case M of
		{From,_} ->
		    case is_from(From) of
			true ->
			    reply(From,{error,not_main_node});
		        false ->
			    ok
		    end;
		_ ->
		    ok
	    end,
	    remote_process_loop(State)
	    
    end.


reload_originals([{Module,_File}|Compiled]) ->
    do_reload_original(Module),
    reload_originals(Compiled);
reload_originals([]) ->
    ok.

do_reload_original(Module) ->
    case code:which(Module) of
	?TAG ->
	    code:purge(Module),
	    case code:load_file(Module) of
		{module, Module} ->
		    ignore;
		{error, _Reason2} ->
		    code:delete(Module)
				  end;
	_ ->
	    ignore
    end.

load_compiled([{Module,File,Binary,InitialTable}|Compiled],Acc) ->
    NewAcc = 
	case code:load_binary(Module, ?TAG, Binary) of
	    {module,Module} ->
		insert_initial_data(InitialTable),
		add_compiled(Module, File, Acc);
	    _  ->
		Acc
	end,
    load_compiled(Compiled,NewAcc);
load_compiled([],Acc) ->
    Acc.

insert_initial_data([Item|Items]) ->
    ets:insert(?COVER_TABLE, Item),
    insert_initial_data(Items);
insert_initial_data([]) ->
    ok.
    

unload([Module|Modules]) ->
    do_clear(Module),
    do_reload_original(Module),
    unload(Modules);
unload([]) ->
    ok.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

%%%--Handling of remote nodes--------------------------------------------

%% start the cover_server on a remote node
remote_start(MainNode) ->
    case whereis(?SERVER) of
	undefined ->
	    Starter = self(),
	    Pid = spawn(fun() -> init_remote(Starter,MainNode) end),
	    Ref = erlang:monitor(process,Pid),
	    Return = 
		receive 
		    {Pid,started} -> 
			{ok,Pid};
		    {'DOWN', Ref, _Type, _Object, Info} -> 
			{error,Info}
		end,
	    erlang:demonitor(Ref),
	    Return;
	Pid ->
	    {error,{already_started,Pid}}
    end.

%% Load a set of cover compiled modules on remote nodes
remote_load_compiled(Nodes,Compiled0) ->
    Compiled = lists:map(fun get_data_for_remote_loading/1,Compiled0),
    lists:foreach(
      fun(Node) -> 
	      remote_call(Node,{remote,load_compiled,Compiled})
      end,
      Nodes).

%% Read all data needed for loading a cover compiled module on a remote node
%% Binary is the beam code for the module and InitialTable is the initial
%% data to insert in ?COVER_TABLE.
get_data_for_remote_loading({Module,File}) ->
    [{Module,Binary}] = ets:lookup(?BINARY_TABLE,Module),
    %%! The InitialTable list will be long if the module is big - what to do??
    InitialTable = ets:select(?COVER_TABLE,ms(Module)),
    {Module,File,Binary,InitialTable}.

%% Create a match spec which returns the clause info {Module,InitInfo} and 
%% all #bump keys for the given module with 0 number of calls.
ms(Module) ->
    ets:fun2ms(fun({Module,InitInfo})  -> 
		       {Module,InitInfo};
		  ({Key,_}) when is_record(Key,bump),Key#bump.module==Module -> 
		       {Key,0}
	       end).

%% Unload modules on remote nodes
remote_unload(Nodes,UnloadedModules) ->
    lists:foreach(
      fun(Node) -> 
	      remote_call(Node,{remote,unload,UnloadedModules})
      end,
      Nodes).    

%% Reset one or all modules on remote nodes
remote_reset(Module,Nodes) ->
    lists:foreach(
      fun(Node) -> 
	      remote_call(Node,{remote,reset,Module})
      end,
      Nodes).        

%% Collect data from remote nodes - used for analyse or stop(Node)
remote_collect(Module,Nodes,Stop) ->
    CollectorPid = spawn(fun() -> collector_proc(length(Nodes)) end),
    lists:foreach(
      fun(Node) -> 
	      remote_call(Node,{remote,collect,Module,CollectorPid}),
	      if Stop -> remote_call(Node,{remote,stop});
		 true -> ok
	      end
      end,
      Nodes).

%% Process which receives chunks of data from remote nodes - either when
%% analysing or when stopping cover on the remote nodes.
collector_proc(0) ->
    ok;
collector_proc(N) ->
    receive 
	{chunk,Chunk} ->
	    insert_in_collection_table(Chunk),
	    collector_proc(N);
	done ->
	    collector_proc(N-1)
    end.

insert_in_collection_table([{Key,Val}|Chunk]) ->
    insert_in_collection_table(Key,Val),
    insert_in_collection_table(Chunk);
insert_in_collection_table([]) ->
    ok.

insert_in_collection_table(Key,Val) ->
    case ets:member(?COLLECTION_TABLE,Key) of
	true ->
	    ets:update_counter(?COLLECTION_TABLE,
			       Key,Val);
	false ->
	    ets:insert(?COLLECTION_TABLE,{Key,Val})
    end.


remove_myself([Node|Nodes],Acc) when Node=:=node() ->
    remove_myself(Nodes,Acc);
remove_myself([Node|Nodes],Acc) ->
    remove_myself(Nodes,[Node|Acc]);
remove_myself([],Acc) ->
    Acc.
    

%%%--Handling of modules state data--------------------------------------

analyse_info(_Module,[]) ->
    ok;
analyse_info(Module,Imported) ->
    imported_info("Analysis",Module,Imported).

export_info(_Module,[]) ->
    ok;
export_info(Module,Imported) ->
    imported_info("Export",Module,Imported).

export_info([]) ->
    ok;
export_info(Imported) ->
    AllImportFiles = get_all_importfiles(Imported,[]),
    io:format("Export includes data from imported files\n~p\n",[AllImportFiles]).

get_all_importfiles([{_M,_F,ImportFiles}|Imported],Acc) ->
    NewAcc = do_get_all_importfiles(ImportFiles,Acc),
    get_all_importfiles(Imported,NewAcc);
get_all_importfiles([],Acc) ->
    Acc.

do_get_all_importfiles([ImportFile|ImportFiles],Acc) ->
    case lists:member(ImportFile,Acc) of
	true ->
	    do_get_all_importfiles(ImportFiles,Acc);
	false ->
	    do_get_all_importfiles(ImportFiles,[ImportFile|Acc])
    end;
do_get_all_importfiles([],Acc) ->
    Acc.

imported_info(Text,Module,Imported) ->
    case lists:keysearch(Module,1,Imported) of
	{value,{Module,_File,ImportFiles}} ->
	    io:format("~s includes data from imported files\n~p\n",
		      [Text,ImportFiles]);
	false ->
	    ok
    end.
    
    

add_imported(Module, File, ImportFile, Imported) ->
    add_imported(Module, File, filename:absname(ImportFile), Imported, []).

add_imported(M, F1, ImportFile, [{M,_F2,ImportFiles}|Imported], Acc) ->
    case lists:member(ImportFile,ImportFiles) of
	true ->
	    io:fwrite("WARNING: Module ~w already imported from ~p~n"
		      "Not importing again!~n",[M,ImportFile]),
	    dont_import;
	false ->
	    NewEntry = {M, F1, [ImportFile | ImportFiles]},
	    {ok, reverse([NewEntry | Acc]) ++ Imported}
    end;
add_imported(M, F, ImportFile, [H|Imported], Acc) ->
    add_imported(M, F, ImportFile, Imported, [H|Acc]);
add_imported(M, F, ImportFile, [], Acc) ->
    {ok, reverse([{M, F, [ImportFile]} | Acc])}.
    
%% Removes a module from the list of imported modules and writes a warning
%% This is done when a module is compiled.
remove_imported(Module,Imported) ->
    case lists:keysearch(Module,1,Imported) of
	{value,{Module,_,ImportFiles}} ->
	    io:fwrite("WARNING: Deleting data for module ~w imported from~n"
		      "~p~n",[Module,ImportFiles]),
	    lists:keydelete(Module,1,Imported);
	false ->
	    Imported
    end.

%% Adds information to the list of compiled modules, preserving time order
%% and without adding duplicate entries.
add_compiled(Module, File1, [{Module,_File2}|Compiled]) ->
    [{Module,File1}|Compiled];
add_compiled(Module, File, [H|Compiled]) ->
    [H|add_compiled(Module, File, Compiled)];
add_compiled(Module, File, []) ->
    [{Module,File}].

is_loaded(Module, State) ->
    case get_file(Module, State#main_state.compiled) of
	{ok, File} ->
	    case code:which(Module) of
		?TAG -> {loaded, File};
		_ -> unloaded
	    end;
	false ->
	    case get_file(Module,State#main_state.imported) of
		{ok,File,ImportFiles} ->
		    {imported, File, ImportFiles};
		false ->
		    false
	    end
    end.

get_file(Module, [{Module, File}|_T]) ->
    {ok, File};
get_file(Module, [{Module, File, ImportFiles}|_T]) ->
    {ok, File, ImportFiles};
get_file(Module, [_H|T]) ->
    get_file(Module, T);
get_file(_Module, []) ->
    false.

get_beam_file(Module,?TAG,Compiled) ->
    {value,{Module,File}} = lists:keysearch(Module,1,Compiled),
    case filename:extension(File) of
	".erl" -> {error,no_beam};
	".beam" -> {ok,File}
    end;
get_beam_file(_Module,BeamFile,_Compiled) ->
    {ok,BeamFile}.

get_modules(Compiled) ->
    lists:map(fun({Module, _File}) -> Module end, Compiled).

update_compiled([Module|Modules], [{Module,_File}|Compiled]) ->
    update_compiled(Modules, Compiled);
update_compiled(Modules, [H|Compiled]) ->
    [H|update_compiled(Modules, Compiled)];
update_compiled(_Modules, []) ->
    [].

%% Get all compiled modules which are still loaded, and possibly an
%% updated version of the Compiled list.
get_compiled_still_loaded(Nodes,Compiled0) ->
    %% Find all Cover compiled modules which are still loaded
    CompiledModules = get_modules(Compiled0),
    LoadedModules = lists:filter(fun(Module) ->
					 case code:which(Module) of
					     ?TAG -> true;
					     _ -> false
					 end
				 end,
				 CompiledModules),

    %% If some Cover compiled modules have been unloaded, update the database.
    UnloadedModules = CompiledModules--LoadedModules,
    Compiled = 
	case UnloadedModules of
	    [] ->
		Compiled0;
	    _ ->
		lists:foreach(fun(Module) -> do_clear(Module) end,
			      UnloadedModules),
		remote_unload(Nodes,UnloadedModules),
		update_compiled(UnloadedModules, Compiled0)
	end,
    {LoadedModules,Compiled}.


%%%--Compilation---------------------------------------------------------

%% do_compile(File, Options) -> {ok,Module} | {error,Error}
do_compile(File, UserOptions) ->
    Options = [debug_info,binary,report_errors,report_warnings] ++ UserOptions,
    case compile:file(File, Options) of
	{ok, Module, Binary} ->
	    do_compile_beam(Module,Binary);

	error ->
	    error
    end.

%% Beam is a binary or a .beam file name
do_compile_beam(Module,Beam) ->
    %% Clear database
    do_clear(Module),
    
    %% Extract the abstract format and insert calls to bump/6 at
    %% every executable line and, as a side effect, initiate
    %% the database
    {ok, {Module, [{abstract_code, AbstractCode}]}} =
	beam_lib:chunks(Beam, [abstract_code]),
    case AbstractCode of
	{Vsn, Code} ->
	    {Forms,Vars} = transform(Vsn, Code, Module, Beam),

	    %% Compile and load the result
	    %% It's necessary to check the result of loading since it may
	    %% fail, for example if Module resides in a sticky directory
	    {ok, Module, Binary} = compile:forms(Forms, []),
	    case code:load_binary(Module, ?TAG, Binary) of
		{module, Module} ->
		    
		    %% Store info about all function clauses in database
		    InitInfo = reverse(Vars#vars.init_info),
		    ets:insert(?COVER_TABLE, {Module, InitInfo}),
		    
		    %% Store binary code so it can be loaded on remote nodes
		    ets:insert(?BINARY_TABLE, {Module, Binary}),

		    {ok, Module};
		
		_Error ->
		    do_clear(Module),
		    error
	    end;
	no_abstract_code ->
	    {error,no_abstract_code}
    end.

transform(Vsn, Code, Module, Beam) when Vsn==abstract_v1; Vsn==abstract_v2 ->
    Vars0 = #vars{module=Module, vsn=Vsn},
    MainFile=find_main_filename(Code),
    {ok, MungedForms,Vars} = transform_2(Code,[],Vars0,MainFile,on),
    
    %% Add module and export information to the munged forms
    %% Information about module_info must be removed as this function
    %% is added at compilation
    {ok, {Module, [{exports,Exports1}]}} = beam_lib:chunks(Beam, [exports]),
    Exports2 = lists:filter(fun(Export) ->
				    case Export of
					{module_info,_} -> false;
					_ -> true
				    end
			    end,
			    Exports1),
    Forms = [{attribute,1,module,Module},
	     {attribute,2,export,Exports2}]++ MungedForms,
    {Forms,Vars};
transform(Vsn=raw_abstract_v1, Code, Module, _Beam) ->
    MainFile=find_main_filename(Code),
    Vars0 = #vars{module=Module, vsn=Vsn},
    {ok,MungedForms,Vars} = transform_2(Code,[],Vars0,MainFile,on),
    {MungedForms,Vars}.
    
%% Helpfunction which returns the first found file-attribute, which can
%% be interpreted as the name of the main erlang source file.
find_main_filename([{attribute,_,file,{MainFile,_}}|_]) ->
    MainFile;
find_main_filename([_|Rest]) ->
    find_main_filename(Rest).

transform_2([Form|Forms],MungedForms,Vars,MainFile,Switch) ->
    case munge(Form,Vars,MainFile,Switch) of
	ignore ->
	    transform_2(Forms,MungedForms,Vars,MainFile,Switch);
	{MungedForm,Vars2,NewSwitch} ->
	    transform_2(Forms,[MungedForm|MungedForms],Vars2,MainFile,NewSwitch)
    end;
transform_2([],MungedForms,Vars,_,_) ->
    {ok, reverse(MungedForms), Vars}.

%% This code traverses the abstract code, stored as the abstract_code
%% chunk in the BEAM file, as described in absform(3) for Erlang/OTP R8B
%% (Vsn=abstract_v2).
%% The abstract format after preprocessing differs slightly from the abstract
%% format given eg using epp:parse_form, this has been noted in comments.
%% The switch is turned off when we encounter other files then the main file.
%% This way we will be able to exclude functions defined in include files.
munge({function,0,module_info,_Arity,_Clauses},_Vars,_MainFile,_Switch) ->
    ignore; % module_info will be added again when the forms are recompiled
munge(Form={function,_,'MNEMOSYNE QUERY',_,_},Vars,_MainFile,Switch) ->
    {Form,Vars,Switch};                 % No bumps in Mnemosyne code.
munge(Form={function,_,'MNEMOSYNE RULE',_,_},Vars,_MainFile,Switch) ->
    {Form,Vars,Switch};
munge(Form={function,_,'MNEMOSYNE RECFUNDEF',_,_},Vars,_MainFile,Switch) ->
    {Form,Vars,Switch};
munge({function,Line,Function,Arity,Clauses},Vars,_MainFile,on) ->
    Vars2 = Vars#vars{function=Function,
		      arity=Arity,
		      clause=1,
		      lines=[],
		      depth=1},
    {MungedClauses, Vars3} = munge_clauses(Clauses, Vars2, []),
    {{function,Line,Function,Arity,MungedClauses},Vars3,on};
munge(Form={attribute,_,file,{MainFile,_}},Vars,MainFile,_Switch) ->
    {Form,Vars,on};                     % Switch on tranformation!
munge(Form={attribute,_,file,{_InclFile,_}},Vars,_MainFile,_Switch) ->
    {Form,Vars,off};                    % Switch off transformation!
munge({attribute,_,compile,{parse_transform,_}},_Vars,_MainFile,_Switch) ->
    %% Don't want to run parse transforms more than once.
    ignore;
munge(Form,Vars,_MainFile,Switch) ->    % Other attributes and skipped includes.
    {Form,Vars,Switch}.

munge_clauses([{clause,Line,Pattern,Guards,Body}|Clauses], Vars, MClauses) ->
    {MungedGuards, _Vars} = munge_exprs(Guards, Vars#vars{is_guard=true},[]),

    case Vars#vars.depth of
	1 -> % function clause
	    {MungedBody, Vars2} = munge_body(Body, Vars#vars{depth=2}, []),
	    ClauseInfo = {Vars2#vars.module,
			  Vars2#vars.function,
			  Vars2#vars.arity,
			  Vars2#vars.clause,
			  length(Vars2#vars.lines)},
	    InitInfo = [ClauseInfo | Vars2#vars.init_info],
	    Vars3 = Vars2#vars{init_info=InitInfo,
			       clause=(Vars2#vars.clause)+1,
			       lines=[],
			       depth=1},
	    munge_clauses(Clauses, Vars3,
			  [{clause,Line,Pattern,MungedGuards,MungedBody}|
			   MClauses]);

	2 -> % receive-,  case- or if clause
	    {MungedBody, Vars2} = munge_body(Body, Vars, []),
	    munge_clauses(Clauses, Vars2,
			  [{clause,Line,Pattern,MungedGuards,MungedBody}|
			   MClauses])
    end;
munge_clauses([], Vars, MungedClauses) -> 
    {reverse(MungedClauses), Vars}.

munge_body([Expr|Body], Vars, MungedBody) ->
    %% Here is the place to add a call to cover:bump/6!
    Line = element(2, Expr),
    Lines = Vars#vars.lines,
    case lists:member(Line,Lines) of
	true -> % already a bump at this line!
	    {MungedExpr, Vars2} = munge_expr(Expr, Vars),
	    munge_body(Body, Vars2, [MungedExpr|MungedBody]);
	false ->
	    ets:insert(?COVER_TABLE, {#bump{module   = Vars#vars.module,
					    function = Vars#vars.function,
					    arity    = Vars#vars.arity,
					    clause   = Vars#vars.clause,
					    line     = Line},
				      0}),
	    Bump={call,0,{remote,0,{atom,0,ets},{atom,0,update_counter}},
		  [{atom,0,?COVER_TABLE},
		   {tuple,0,[{atom,0,?BUMP_REC_NAME},
			     {atom,0,Vars#vars.module},
			     {atom,0,Vars#vars.function},
			     {integer,0,Vars#vars.arity},
			     {integer,0,Vars#vars.clause},
			     {integer,0,Line}]},
		   {integer,0,1}]},
%	    Bump = {call, 0, {remote, 0, {atom,0,cover}, {atom,0,bump}},
%		    [{atom, 0, Vars#vars.module},
%		     {atom, 0, Vars#vars.function},
%		     {integer, 0, Vars#vars.arity},
%		     {integer, 0, Vars#vars.clause},
%		     {integer, 0, Line}]},
	    Lines2 = [Line|Lines],

	    {MungedExpr, Vars2} = munge_expr(Expr, Vars#vars{lines=Lines2}),
	    munge_body(Body, Vars2, [MungedExpr,Bump|MungedBody])
    end;
munge_body([], Vars, MungedBody) ->
    {reverse(MungedBody), Vars}.

munge_expr({match,Line,ExprL,ExprR}, Vars) ->
    {MungedExprL, Vars2} = munge_expr(ExprL, Vars),
    {MungedExprR, Vars3} = munge_expr(ExprR, Vars2),
    {{match,Line,MungedExprL,MungedExprR}, Vars3};
munge_expr({tuple,Line,Exprs}, Vars) ->
    {MungedExprs, Vars2} = munge_exprs(Exprs, Vars, []),
    {{tuple,Line,MungedExprs}, Vars2};
munge_expr({record,Line,Expr,Exprs}, Vars) ->
    %% Only for Vsn=raw_abstract_v1
    {MungedExprName, Vars2} = munge_expr(Expr, Vars),
    {MungedExprFields, Vars3} = munge_exprs(Exprs, Vars2, []),
    {{record,Line,MungedExprName,MungedExprFields}, Vars3};
munge_expr({record_field,Line,ExprL,ExprR}, Vars) ->
    %% Only for Vsn=raw_abstract_v1
    {MungedExprL, Vars2} = munge_expr(ExprL, Vars),
    {MungedExprR, Vars3} = munge_expr(ExprR, Vars2),
    {{record_field,Line,MungedExprL,MungedExprR}, Vars3};
munge_expr({cons,Line,ExprH,ExprT}, Vars) ->
    {MungedExprH, Vars2} = munge_expr(ExprH, Vars),
    {MungedExprT, Vars3} = munge_expr(ExprT, Vars2),
    {{cons,Line,MungedExprH,MungedExprT}, Vars3};
munge_expr({op,Line,Op,ExprL,ExprR}, Vars) ->
    {MungedExprL, Vars2} = munge_expr(ExprL, Vars),
    {MungedExprR, Vars3} = munge_expr(ExprR, Vars2),
    {{op,Line,Op,MungedExprL,MungedExprR}, Vars3};
munge_expr({op,Line,Op,Expr}, Vars) ->
    {MungedExpr, Vars2} = munge_expr(Expr, Vars),
    {{op,Line,Op,MungedExpr}, Vars2};
munge_expr({'catch',Line,Expr}, Vars) ->
    {MungedExpr, Vars2} = munge_expr(Expr, Vars),
    {{'catch',Line,MungedExpr}, Vars2};
munge_expr({call,Line1,{remote,Line2,ExprM,ExprF},Exprs},
	   Vars) when Vars#vars.is_guard==false->
    {MungedExprM, Vars2} = munge_expr(ExprM, Vars),
    {MungedExprF, Vars3} = munge_expr(ExprF, Vars2),
    {MungedExprs, Vars4} = munge_exprs(Exprs, Vars3, []),
    {{call,Line1,{remote,Line2,MungedExprM,MungedExprF},MungedExprs}, Vars4};
munge_expr({call,Line1,{remote,_Line2,_ExprM,ExprF},Exprs},
	   Vars) when Vars#vars.is_guard==true ->
    %% Difference in abstract format after preprocessing: BIF calls in guards
    %% are translated to {remote,...} (which is not allowed as source form)
    %% NOT NECESSARY FOR Vsn=raw_abstract_v1
    munge_expr({call,Line1,ExprF,Exprs}, Vars);
munge_expr({call,Line,Expr,Exprs}, Vars) ->
    {MungedExpr, Vars2} = munge_expr(Expr, Vars),
    {MungedExprs, Vars3} = munge_exprs(Exprs, Vars2, []),
    {{call,Line,MungedExpr,MungedExprs}, Vars3};
munge_expr({lc,Line,Expr,LC}, Vars) ->
    {MungedExpr, Vars2} = munge_expr(Expr, Vars),
    {MungedLC, Vars3} = munge_lc(LC, Vars2, []),
    {{lc,Line,MungedExpr,MungedLC}, Vars3};
munge_expr({block,Line,Body}, Vars) ->
    {MungedBody, Vars2} = munge_body(Body, Vars, []),
    {{block,Line,MungedBody}, Vars2};
munge_expr({'if',Line,Clauses}, Vars) -> 
    {MungedClauses,Vars2} = munge_clauses(Clauses, Vars, []),
    {{'if',Line,MungedClauses}, Vars2};
munge_expr({'case',Line,Expr,Clauses}, Vars) ->
    {MungedExpr,Vars2} = munge_expr(Expr,Vars),
    {MungedClauses,Vars3} = munge_clauses(Clauses, Vars2, []),
    {{'case',Line,MungedExpr,MungedClauses}, Vars3};
munge_expr({'receive',Line,Clauses}, Vars) -> 
    {MungedClauses,Vars2} = munge_clauses(Clauses, Vars, []),
    {{'receive',Line,MungedClauses}, Vars2};
munge_expr({'receive',Line,Clauses,Expr,Body}, Vars) ->
    {MungedClauses,Vars2} = munge_clauses(Clauses, Vars, []),
    {MungedExpr, Vars3} = munge_expr(Expr, Vars2),
    {MungedBody, Vars4} = munge_body(Body, Vars3, []),
    {{'receive',Line,MungedClauses,MungedExpr,MungedBody}, Vars4};
munge_expr({'try',Line,Exprs,Clauses,CatchClauses,After}, Vars) ->
    {MungedExprs, Vars1} = munge_exprs(Exprs, Vars, []),
    {MungedClauses, Vars2} = munge_clauses(Clauses, Vars1, []),
    {MungedCatchClauses, Vars3} = munge_clauses(CatchClauses, Vars2, []),
    {MungedAfter, Vars4} = munge_body(After, Vars3, []),
    {{'try',Line,MungedExprs,MungedClauses,MungedCatchClauses,MungedAfter}, 
     Vars4};
%% Difference in abstract format after preprocessing: Funs get an extra
%% element Extra.
%% NOT NECESSARY FOR Vsn=raw_abstract_v1
munge_expr({'fun',Line,{function,Name,Arity},_Extra}, Vars) ->
    {{'fun',Line,{function,Name,Arity}}, Vars};
munge_expr({'fun',Line,{clauses,Clauses},_Extra}, Vars) ->
    {MungedClauses,Vars2}=munge_clauses(Clauses, Vars, []),
    {{'fun',Line,{clauses,MungedClauses}}, Vars2};
munge_expr({'fun',Line,{clauses,Clauses}}, Vars) ->
    %% Only for Vsn=raw_abstract_v1
    {MungedClauses,Vars2}=munge_clauses(Clauses, Vars, []),
    {{'fun',Line,{clauses,MungedClauses}}, Vars2};
munge_expr(Form, Vars) -> % var|char|integer|float|string|atom|nil|bin|eof
    {Form, Vars}.

munge_exprs([Expr|Exprs], Vars, MungedExprs) when Vars#vars.is_guard==true,
						  list(Expr) ->
    {MungedExpr, _Vars} = munge_exprs(Expr, Vars, []),
    munge_exprs(Exprs, Vars, [MungedExpr|MungedExprs]);
munge_exprs([Expr|Exprs], Vars, MungedExprs) ->
    {MungedExpr, Vars2} = munge_expr(Expr, Vars),
    munge_exprs(Exprs, Vars2, [MungedExpr|MungedExprs]);
munge_exprs([], Vars, MungedExprs) ->
    {reverse(MungedExprs), Vars}.

munge_lc([{generate,Line,Pattern,Expr}|LC], Vars, MungedLC) ->
    {MungedExpr, Vars2} = munge_expr(Expr, Vars),
    munge_lc(LC, Vars2, [{generate,Line,Pattern,MungedExpr}|MungedLC]);
munge_lc([Expr|LC], Vars, MungedLC) ->
    {MungedExpr, Vars2} = munge_expr(Expr, Vars),
    munge_lc(LC, Vars2, [MungedExpr|MungedLC]);
munge_lc([], Vars, MungedLC) ->
    {reverse(MungedLC), Vars}.


%%%--Analysis------------------------------------------------------------

%% Collect data for all modules
collect(Nodes) ->
    %% local node
    MS = ets:fun2ms(fun({M,C}) when is_atom(M) -> {M,C} end),
    AllClauses = ets:select(?COVER_TABLE,MS),
    move_modules(AllClauses),
    
    %% remote nodes
    remote_collect('_',Nodes,false).

%% Collect data for one module
collect(Module,Clauses,Nodes) ->
    %% local node
    move_modules([{Module,Clauses}]),
    
    %% remote nodes
    remote_collect(Module,Nodes,false).


%% When analysing, the data from the local ?COVER_TABLE is moved to the
%% ?COLLECTION_TABLE. Resetting data in ?COVER_TABLE
move_modules([{Module,Clauses}|AllClauses]) ->
    ets:insert(?COLLECTION_TABLE,{Module,Clauses}),
    move_clauses(Clauses),
    move_modules(AllClauses);
move_modules([]) ->
    ok.
    
move_clauses([{M,F,A,C,_L}|Clauses]) ->
    Pattern = {#bump{module=M, function=F, arity=A, clause=C}, '_'},
    Bumps = ets:match_object(?COVER_TABLE,Pattern),
    lists:foreach(fun({Key,Val}) ->
			  ets:insert(?COVER_TABLE, {Key,0}),
			  insert_in_collection_table(Key,Val)
		  end,
		  Bumps),
    move_clauses(Clauses);
move_clauses([]) ->
    ok.
			  

%% Given a .beam file, find the .erl file. Look first in same directory as
%% the .beam file, then in <beamdir>/../src
find_source(File0) ->
    case filename:rootname(File0,".beam") of
	File0 ->
	    File0;
	File ->
	    InSameDir = File++".erl",
	    case filelib:is_file(InSameDir) of
		true -> 
		    InSameDir;
		false ->
		    Dir = filename:dirname(File),
		    Mod = filename:basename(File),
		    InDotDotSrc = filename:join([Dir,"..","src",Mod++".erl"]),
		    case filelib:is_file(InDotDotSrc) of
			true ->
			    InDotDotSrc;
			false ->
			    {beam,File0}
		    end
	    end
    end.

%% do_analyse(Module, Analysis, Level, Clauses)-> {ok,Answer} | {error,Error}
%%   Clauses = [{Module,Function,Arity,Clause,Lines}]
do_analyse(Module, Analysis, line, _Clauses) ->
    Pattern = {#bump{module=Module},'_'},
    Bumps = ets:match_object(?COLLECTION_TABLE, Pattern),
    Fun = case Analysis of
	      coverage ->
		  fun({#bump{line=L}, 0}) ->
			  {{Module,L}, {0,1}};
		     ({#bump{line=L}, _N}) ->
			  {{Module,L}, {1,0}}
		  end;
	      calls ->
		  fun({#bump{line=L}, N}) ->
			  {{Module,L}, N}
		  end
	  end,
    Answer = lists:keysort(1, lists:map(Fun, Bumps)),
    {ok, Answer};
do_analyse(_Module, Analysis, clause, Clauses) ->
    Fun = case Analysis of
	      coverage ->
		  fun({M,F,A,C,Ls}) ->
			  Pattern = {#bump{module=M,function=F,arity=A,
					   clause=C},0},
			  Bumps = ets:match_object(?COLLECTION_TABLE, Pattern),
			  NotCov = length(Bumps),
			  {{M,F,A,C}, {Ls-NotCov, NotCov}}
		  end;
	      calls ->
		  fun({M,F,A,C,_Ls}) ->
			  Pattern = {#bump{module=M,function=F,arity=A,
					   clause=C},'_'},
			  Bumps = ets:match_object(?COLLECTION_TABLE, Pattern),
			  {_Bump, Calls} = hd(lists:keysort(1, Bumps)),
			  {{M,F,A,C}, Calls}
		  end
	  end,
    Answer = lists:map(Fun, Clauses),
    {ok, Answer};
do_analyse(Module, Analysis, function, Clauses) ->
    {ok, ClauseResult} = do_analyse(Module, Analysis, clause, Clauses),
    Result = merge_clauses(ClauseResult, merge_fun(Analysis)),
    {ok, Result};
do_analyse(Module, Analysis, module, Clauses) ->
    {ok, FunctionResult} = do_analyse(Module, Analysis, function, Clauses),
    Result = merge_functions(FunctionResult, merge_fun(Analysis)),
    {ok, {Module,Result}}.

merge_fun(coverage) ->
    fun({Cov1,NotCov1}, {Cov2,NotCov2}) ->
	    {Cov1+Cov2, NotCov1+NotCov2}
    end;
merge_fun(calls) ->
    fun(Calls1, Calls2) ->
	    Calls1+Calls2
    end.

merge_clauses(Clauses, MFun) -> merge_clauses(Clauses, MFun, []).
merge_clauses([{{M,F,A,_C1},R1},{{M,F,A,C2},R2}|Clauses], MFun, Result) ->
    merge_clauses([{{M,F,A,C2},MFun(R1,R2)}|Clauses], MFun, Result);
merge_clauses([{{M,F,A,_C},R}|Clauses], MFun, Result) ->
    merge_clauses(Clauses, MFun, [{{M,F,A},R}|Result]);
merge_clauses([], _Fun, Result) ->
    reverse(Result).

merge_functions([{_MFA,R}|Functions], MFun) ->
    merge_functions(Functions, MFun, R).
merge_functions([{_MFA,R}|Functions], MFun, Result) ->
    merge_functions(Functions, MFun, MFun(Result, R));
merge_functions([], _MFun, Result) ->
    Result.

%% do_analyse_to_file(Module,OutFile,ErlFile) -> {ok,OutFile} | {error,Error}
%%   Module = atom()
%%   OutFile = ErlFile = string()
do_analyse_to_file(Module, OutFile, ErlFile, HTML) ->
    case file:open(ErlFile, read) of
	{ok, InFd} ->
	    case file:open(OutFile, write) of
		{ok, OutFd} ->
		    if HTML -> 
			    io:format(OutFd,
				      "<html>\n"
				      "<head><title>~s</title></head>"
				      "<body bgcolor=white text=black>\n"
				      "<pre>\n",
				      [OutFile]);
		       true -> ok
		    end,
		    
		    %% Write some initial information to the output file
		    {{Y,Mo,D},{H,Mi,S}} = calendar:local_time(),
		    io:format(OutFd, "File generated from ~s by COVER "
			             "~p-~s-~s at ~s:~s:~s~n",
			      [ErlFile,
			       Y,
			       string:right(integer_to_list(Mo), 2, $0),
			       string:right(integer_to_list(D),  2, $0),
			       string:right(integer_to_list(H),  2, $0),
			       string:right(integer_to_list(Mi), 2, $0),
			       string:right(integer_to_list(S),  2, $0)]),
		    io:format(OutFd, "~n"
			             "**************************************"
			             "**************************************"
			             "~n~n", []),

		    print_lines(Module, InFd, OutFd, 1, HTML),
		    
		    if HTML -> io:format(OutFd,"</pre>\n</body>\n</html>\n",[]);
		       true -> ok
		    end,

		    file:close(OutFd),
		    file:close(InFd),

		    {ok, OutFile};

		{error, Reason} ->
		    {error, {file, OutFile, Reason}}
	    end;

	{error, Reason} ->
	    {error, {file, ErlFile, Reason}}
    end.

print_lines(Module, InFd, OutFd, L, HTML) ->
    case io:get_line(InFd, '') of
	eof ->
	    ignore;
 	"%"++_=Line ->				%Comment line - not executed.
 	    io:put_chars(OutFd, [tab(),Line]),
	    print_lines(Module, InFd, OutFd, L+1, HTML);
	Line ->
	    Pattern = {#bump{module=Module,line=L},'$1'},
	    case ets:match(?COLLECTION_TABLE, Pattern) of
		[] ->
		    io:put_chars(OutFd, [tab(),Line]);
		Ns ->
		    N = lists:foldl(fun([Ni], Nacc) -> Nacc+Ni end, 0, Ns),
		    if
			N=:=0, HTML=:=true ->
			    LineNoNL = Line -- "\n",
			    Str = "     0",
			    %%Str = string:right("0", 6, 32),
			    RedLine = ["<font color=red>",Str,fill1(),
				       LineNoNL,"</font>\n"],
			    io:put_chars(OutFd, RedLine);
			N<1000000 ->
			    Str = string:right(integer_to_list(N), 6, 32),
			    io:put_chars(OutFd, [Str,fill1(),Line]);
			N<10000000 ->
			    Str = integer_to_list(N),
			    io:put_chars(OutFd, [Str,fill2(),Line]);
			true ->
			    Str = integer_to_list(N),
			    io:put_chars(OutFd, [Str,fill3(),Line])
		    end
	    end,
	    print_lines(Module, InFd, OutFd, L+1, HTML)
    end.

tab() ->  "        |  ".
fill1() ->      "..|  ".
fill2() ->       ".|  ".
fill3() ->        "|  ".

%%%--Export--------------------------------------------------------------
do_export_table(Compiled, Imported, Fd) ->
    ModList = merge(Imported,Compiled),
    write_module_data(ModList,Fd).

merge([{Module,File,_ImportFiles}|Imported],ModuleList) ->
    case lists:keymember(Module,1,ModuleList) of
	true ->
	    merge(Imported,ModuleList);
	false ->
	    merge(Imported,[{Module,File}|ModuleList])
    end;
merge([],ModuleList) ->
    ModuleList.

write_module_data([{Module,File}|ModList],Fd) ->
    write({file,Module,File},Fd),
    [Clauses] = ets:lookup(?COLLECTION_TABLE,Module),
    write(Clauses,Fd),
    ModuleData = ets:match_object(?COLLECTION_TABLE,{#bump{module=Module},'_'}),
    do_write_module_data(ModuleData,Fd),
    write_module_data(ModList,Fd);
write_module_data([],_Fd) ->
    ok.

do_write_module_data([H|T],Fd) ->
    write(H,Fd),
    do_write_module_data(T,Fd);
do_write_module_data([],_Fd) ->
    ok.

write(Element,Fd) ->
    Bin = term_to_binary(Element,[compressed]),
    case size(Bin) of
	Size when Size > 255 ->
	    SizeBin = term_to_binary({'$size',Size}),
	    file:write(Fd,<<(size(SizeBin)):8,SizeBin/binary,Bin/binary>>);
	Size ->
	    file:write(Fd,<<Size:8,Bin/binary>>)
    end,
    ok.    

%%%--Import--------------------------------------------------------------
do_import_to_table(Fd,ImportFile,Imported) ->
    do_import_to_table(Fd,ImportFile,Imported,[]).
do_import_to_table(Fd,ImportFile,Imported,DontImport) ->
    case get_term(Fd) of
	{file,Module,File} ->
	    case add_imported(Module, File, ImportFile, Imported) of
		{ok,NewImported} ->
		    do_import_to_table(Fd,ImportFile,NewImported,DontImport);
		dont_import ->
		    do_import_to_table(Fd,ImportFile,Imported,
				       [Module|DontImport])
	    end;
	{Key=#bump{module=Module},Val} ->
	    case lists:member(Module,DontImport) of
		false ->
		    insert_in_collection_table(Key,Val);
		true ->
		    ok
	    end,
	    do_import_to_table(Fd,ImportFile,Imported,DontImport);
	{Module,Clauses} ->
	    case lists:member(Module,DontImport) of
		false ->
		    ets:insert(?COLLECTION_TABLE,{Module,Clauses});
		true ->
			    ok
	    end,
	    do_import_to_table(Fd,ImportFile,Imported,DontImport);
	eof ->
	    Imported
    end.
	    

get_term(Fd) ->
    case file:read(Fd,1) of
	{ok,<<Size1:8>>} ->
	    {ok,Bin1} = file:read(Fd,Size1),
	    case binary_to_term(Bin1) of
		{'$size',Size2} -> 
		    {ok,Bin2} = file:read(Fd,Size2),
		    binary_to_term(Bin2);
		Term ->
		    Term
	    end;
	eof ->
	    eof
    end.

%%%--Reset---------------------------------------------------------------

%% Reset main node and all remote nodes
do_reset_main_node(Module,Nodes) ->
    do_reset(Module),
    do_reset_collection_table(Module),
    remote_reset(Module,Nodes).

do_reset_collection_table(Module) ->
    ets:delete(?COLLECTION_TABLE,Module),
    ets:match_delete(?COLLECTION_TABLE, {#bump{module=Module},'_'}).

%% do_reset(Module) -> ok
%% The reset is done on a per-clause basis to avoid building
%% long lists in the case of very large modules
do_reset(Module) ->
    [{Module,Clauses}] = ets:lookup(?COVER_TABLE, Module),
    do_reset2(Clauses).

do_reset2([{M,F,A,C,_L}|Clauses]) ->
    Pattern = {#bump{module=M, function=F, arity=A, clause=C}, '_'},
    Bumps = ets:match_object(?COVER_TABLE, Pattern),
    lists:foreach(fun({Bump,_N}) ->
			  ets:insert(?COVER_TABLE, {Bump,0})
		  end,
		  Bumps),
    do_reset2(Clauses);
do_reset2([]) ->
    ok.    

do_clear(Module) ->
    ets:match_delete(?COVER_TABLE, {Module,'_'}),
    ets:match_delete(?COVER_TABLE, {#bump{module=Module},'_'}),
    ets:match_delete(?COLLECTION_TABLE, {#bump{module=Module},'_'}).



%%%--Div-----------------------------------------------------------------

reverse(List) ->
    reverse(List,[]).
reverse([H|T],Acc) ->
    reverse(T,[H|Acc]);
reverse([],Acc) ->
    Acc.
