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
-module(snmpa_symbolic_store).

%%----------------------------------------------------------------------
%% This module implements a multipurpose symbolic store.
%% 1) For internal and use from application: aliasname_to_value/1.
%%    If this was stored in the mib, deadlock would occur.
%% 2 table_info/1. Getting information about a table. Used by default 
%%    implementation of tables.
%% 3) variable_info/1. Used by default implementation of variables.
%% 4) notification storage. Used by snmpa_trap.
%% There is one symbolic store per node and it uses the ets table
%% snmp_agent_table, owned by the snmpa_supervisor.
%%
%%----------------------------------------------------------------------
-include("snmp_types.hrl").
-include("snmp_debug.hrl").
-include("snmp_verbosity.hrl").


%% API
-export([start_link/2, 
	 stop/0,
	 info/0, 
	 aliasname_to_oid/1, oid_to_aliasname/1, 
	 add_aliasnames/2, delete_aliasnames/1,
	 which_aliasnames/0, 
	 enum_to_int/2, int_to_enum/2, 
	 table_info/1, add_table_infos/2, delete_table_infos/1,
	 variable_info/1, add_variable_infos/2, delete_variable_infos/1,
	 get_notification/1, set_notification/2, delete_notifications/1,
	 add_types/2, delete_types/1]).

%% API (for quick access to the db, note that this is only reads).
-export([get_db/0,
	 aliasname_to_oid/2, oid_to_aliasname/2, 
	 enum_to_int/3, int_to_enum/3]).


%% Internal exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
	code_change/3]).

-export([verbosity/1]).

-define(SERVER, ?MODULE).

-ifdef(snmp_debug).
-define(GS_START_LINK(Prio, Opts),
        gen_server:start_link({local, ?SERVER}, ?MODULE, [Prio, Opts], 
			      [{debug,[trace]}])).
-else.
-define(GS_START_LINK(Prio, Opts),
        gen_server:start_link({local, ?SERVER}, ?MODULE, [Prio, Opts], [])).
-endif.
  
-record(state, {db}).
-record(symbol,{key,mib_name,info}).


%%-----------------------------------------------------------------
%% Func: start_link/1
%% Args: Prio is priority of mib-server
%%       Opts is a list of options
%% Purpose: starts the mib server synchronized
%% Returns: {ok, Pid} | {error, Reason}
%%-----------------------------------------------------------------
start_link(Prio, Opts) ->
    ?d("start_link -> entry with"
	"~n   Prio: ~p"
	"~n   Opts: ~p", [Prio,Opts]),
    ?GS_START_LINK(Prio,Opts).

stop() ->
    call(stop).

info() ->
    call(info).


%%----------------------------------------------------------------------
%% Returns: Db
%%----------------------------------------------------------------------
get_db() ->
    call(get_db).

%%----------------------------------------------------------------------
%% Returns: {value, Oid} | false
%%----------------------------------------------------------------------
aliasname_to_oid(Aliasname) ->
    call({aliasname_to_oid, Aliasname}).

oid_to_aliasname(OID) ->
    call({oid_to_aliasname, OID}).

int_to_enum(TypeOrObjName, Int) ->
    call({int_to_enum,TypeOrObjName,Int}).

enum_to_int(TypeOrObjName, Enum) ->
    call({enum_to_int,TypeOrObjName,Enum}).

add_types(MibName, Types) ->
    cast({add_types, MibName, Types}).

delete_types(MibName) ->
    cast({delete_types, MibName}).

add_aliasnames(MibName, MEs) ->
    cast({add_aliasnames, MibName, MEs}).

delete_aliasnames(MibName) ->
    cast({delete_aliasname, MibName}).

which_aliasnames() ->
    call(which_aliasnames).


%%----------------------------------------------------------------------
%% Returns: false|{value, Info}
%%----------------------------------------------------------------------
table_info(TableName) ->
    call({table_info, TableName}).

%%----------------------------------------------------------------------
%% Returns: false|{value, Info}
%%----------------------------------------------------------------------
variable_info(VariableName) ->
    call({variable_info, VariableName}).

add_table_infos(MibName, TableInfos) ->
    cast({add_table_infos, MibName, TableInfos}).

delete_table_infos(MibName) ->
    cast({delete_table_infos, MibName}).

add_variable_infos(MibName, VariableInfos) ->
    cast({add_variable_infos, MibName, VariableInfos}).

delete_variable_infos(MibName) ->
    cast({delete_variable_infos, MibName}).


%%-----------------------------------------------------------------
%% Store traps
%%-----------------------------------------------------------------
%% A notification is stored as {Key, Value}, where
%% Key is the symbolic trap name, and Value is 
%% a #trap record.
%%-----------------------------------------------------------------
%% Returns: {value, Val} | undefined
%%-----------------------------------------------------------------
get_notification(Key) ->
    call({get_notification, Key}).
set_notification(Trap, MibName) ->
    call({set_notification, MibName, Trap}).
delete_notifications(MibName) ->
    call({delete_notifications, MibName}).

verbosity(Verbosity) -> 
    cast({verbosity,Verbosity}).


%%----------------------------------------------------------------------
%% DB access (read) functions: Returns: {value, Oid} | false
%%----------------------------------------------------------------------
aliasname_to_oid(Db, Aliasname) ->
    case snmpa_general_db:read(Db, {alias, Aliasname}) of
	{value,#symbol{info = {Oid, _Enums}}} -> {value, Oid};
	false -> false
    end.

oid_to_aliasname(Db,Oid) ->
    case snmpa_general_db:read(Db, {oid, Oid}) of
	{value,#symbol{info = Aliasname}} -> {value, Aliasname};
	_ -> false
    end.

which_aliasnames(Db) ->
    Pattern = #symbol{key = {alias, '_'}, _ = '_'},
%%     Symbols = snmpa_general_db:match_object(Db, Pattern),
%%     [Alias || #symbol{key = {alias, Alias}} <- Symbols, atom(Alias)].
    Symbols = snmpa_general_db:match_object(Db, Pattern),
    [Alias || #symbol{key = {alias, Alias}} <- Symbols].

int_to_enum(Db,TypeOrObjName,Int) ->
    case snmpa_general_db:read(Db, {alias, TypeOrObjName}) of
	{value,#symbol{info = {_Oid, Enums}}} ->
	    case lists:keysearch(Int, 2, Enums) of
		{value, {Enum, _Int}} -> {value, Enum};
		false -> false
	    end;
	false -> % Not an Aliasname ->
	    case snmpa_general_db:read(Db, {type, TypeOrObjName}) of
		{value,#symbol{info = Enums}} ->
		    case lists:keysearch(Int, 2, Enums) of
			{value, {Enum, _Int}} -> {value, Enum};
			false -> false
		    end;
		false ->
		    false
	    end
    end.

enum_to_int(Db, TypeOrObjName, Enum) ->
    case snmpa_general_db:read(Db, {alias, TypeOrObjName}) of
	{value,#symbol{info = {_Oid, Enums}}} ->
	    case lists:keysearch(Enum, 1, Enums) of
		{value, {_Enum, Int}} -> {value, Int};
		false -> false
	    end;
	false -> % Not an Aliasname
	    case snmpa_general_db:read(Db, {type, TypeOrObjName}) of
		{value,#symbol{info = Enums}} ->
		    case lists:keysearch(Enum, 1, Enums) of
			{value, {_Enum, Int}} -> {value, Int};
			false -> false
		    end;
		false ->
		    false
	    end
    end.


%%----------------------------------------------------------------------
%% DB access (read) functions: Returns: false|{value, Info}
%%----------------------------------------------------------------------
table_info(Db,TableName) ->
    case snmpa_general_db:read(Db, {table_info, TableName}) of
	{value,#symbol{info = Info}} -> {value, Info};
	false -> false
    end.


%%----------------------------------------------------------------------
%% DB access (read) functions: Returns: false|{value, Info}
%%----------------------------------------------------------------------
variable_info(Db,VariableName) ->
    case snmpa_general_db:read(Db, {variable_info, VariableName}) of
	{value,#symbol{info = Info}} -> {value, Info};
	false -> false
    end.


%%----------------------------------------------------------------------
%% Implementation
%%----------------------------------------------------------------------

init([Prio,Opts]) ->
    ?d("init -> entry with"
	"~n   Prio: ~p"
	"~n   Opts: ~p", [Prio,Opts]),
    case (catch do_init(Prio, Opts)) of
	{ok, State} ->
	    {ok, State};
	Error ->
	    config_err("failed starting symbolic-store: ~n~p", [Error]),
	    {stop, {error, Error}}
    end.

do_init(Prio, Opts) ->
    process_flag(priority, Prio),
    put(sname,ss),
    put(verbosity,get_verbosity(Opts)),
    ?vlog("starting",[]),
    Storage = get_mib_storage(Opts),
    %% type = bag solves the problem with import and multiple
    %% object/type definitions.
    Db = snmpa_general_db:open(Storage, snmpa_symbolic_store,
			       symbol, record_info(fields,symbol), bag),
    S  = #state{db = Db},
    ?vdebug("started",[]),
    {ok, S}.


handle_call(get_db, _From, #state{db = DB} = S) ->
    ?vlog("get db",[]),
    {reply, DB, S};

handle_call({table_info, TableName}, _From, #state{db = DB} = S) ->
    ?vlog("table info: ~p",[TableName]),
    Res = table_info(DB, TableName),
    ?vdebug("table info result: ~p",[Res]),
    {reply, Res, S};

handle_call({variable_info, VariableName}, _From, #state{db = DB} = S) ->
    ?vlog("variable info: ~p",[VariableName]),
    Res = variable_info(DB, VariableName),
    ?vdebug("variable info result: ~p",[Res]),
    {reply, Res, S};

handle_call({aliasname_to_oid, Aliasname}, _From, #state{db = DB} = S) ->
    ?vlog("aliasname to oid: ~p",[Aliasname]),
    Res = aliasname_to_oid(DB,Aliasname),
    ?vdebug("aliasname to oid result: ~p",[Res]),
    {reply, Res, S};

handle_call({oid_to_aliasname, Oid}, _From, #state{db = DB} = S) ->
    ?vlog("oid to aliasname: ~p",[Oid]),
    Res = oid_to_aliasname(DB, Oid),
    ?vdebug("oid to aliasname result: ~p",[Res]),
    {reply, Res, S};

handle_call(which_aliasnames, _From, #state{db = DB} = S) ->
    ?vlog("which aliasnames",[]),
    Res = which_aliasnames(DB),
    ?vdebug("which aliasnames: ~p",[Res]),
    {reply, Res, S};

handle_call({enum_to_int, TypeOrObjName, Enum}, _From, #state{db = DB} = S) ->
    ?vlog("enum to int: ~p, ~p",[TypeOrObjName,Enum]),
    Res = enum_to_int(DB, TypeOrObjName, Enum),
    ?vdebug("enum to int result: ~p",[Res]),
    {reply, Res, S};

handle_call({int_to_enum, TypeOrObjName, Int}, _From, #state{db = DB} = S) ->
    ?vlog("int to enum: ~p, ~p",[TypeOrObjName,Int]),
    Res = int_to_enum(DB, TypeOrObjName, Int),
    ?vdebug("int to enum result: ~p",[Res]),
    {reply, Res, S};

handle_call({set_notification, MibName, Trap}, _From, #state{db = DB} = S) ->
    ?vlog("set notification:"
	  "~n   ~p~n   ~p",[MibName,Trap]),
    set_notif(DB, MibName, Trap),
    {reply, true, S};

handle_call({delete_notifications, MibName}, _From, #state{db = DB} = S) ->
    ?vlog("delete notification: ~p",[MibName]),
    delete_notif(DB, MibName),
    {reply, true, S};

handle_call({get_notification, Key}, _From, #state{db = DB} = S) ->
    ?vlog("get notification: ~p",[Key]),
    Res = get_notif(DB, Key),
    ?vdebug("get notification result: ~p",[Res]),
    {reply, Res, S};

handle_call(info, _From, #state{db = DB} = S) ->
    ?vlog("info",[]),
    {memory, ProcSize} = erlang:process_info(self(),memory),
    DbSize = snmpa_general_db:info(DB, memory),
    {reply, [{process_memory, ProcSize}, {db_memory, DbSize}], S};

handle_call(stop, _From, S) -> 
    ?vlog("stop",[]),
    {stop, normal, ok, S};

handle_call(Req, _From, S) -> 
    info_msg("received unknown request: ~n~p", [Req]),
    Reply = {error, {unknown, Req}}, 
    {reply, Reply, S}.


handle_cast({add_types, MibName, Types}, #state{db = DB} = S) ->
    ?vlog("add types for ~p:",[MibName]),
    F = fun(#asn1_type{assocList = Alist, aliasname = Name}) ->
		case snmp_misc:assq(enums, Alist) of
		    {value, Es} ->
			?vlog("add type~n   ~p -> ~p",[Name,Es]),
			Rec = #symbol{key      = {type, Name}, 
				      mib_name = MibName, 
				      info     = Es},
			snmpa_general_db:write(DB, Rec);
		    false -> done
		end
	end,
    lists:foreach(F, Types),
    {noreply, S};

handle_cast({delete_types, MibName}, #state{db = DB} = S) ->
    ?vlog("delete types: ~p",[MibName]),
    Pattern = #symbol{key = {type, '_'}, mib_name = MibName, info = '_'},
    snmpa_general_db:match_delete(DB, Pattern),
    {noreply, S};

handle_cast({add_aliasnames, MibName, MEs}, #state{db = DB} = S) ->
    ?vlog("add aliasnames for ~p:",[MibName]),
    F = fun(#me{aliasname = AN, oid = Oid, asn1_type = AT}) ->
		Enums =
		    case AT of
			#asn1_type{assocList = Alist} -> 
			    case lists:keysearch(enums, 1, Alist) of
				{value, {enums, Es}} -> Es;
				_ -> []
			    end;
			_ -> []
		    end,
		?vlog("add alias~n   ~p -> {~p,~p}",[AN, Oid, Enums]),
		Rec1 = #symbol{key      = {alias, AN}, 
			       mib_name = MibName, 
			       info     = {Oid,Enums}},
		snmpa_general_db:write(DB, Rec1),
		?vlog("add oid~n   ~p -> ~p",[Oid, AN]),
		Rec2 = #symbol{key      = {oid, Oid}, 
			       mib_name = MibName, 
			       info     = AN},
		snmpa_general_db:write(DB, Rec2)
	end,
    lists:foreach(F, MEs),
    {noreply, S};

handle_cast({delete_aliasname, MibName}, #state{db = DB} = S) ->
    ?vlog("delete aliasname: ~p",[MibName]),
    Pattern1 = #symbol{key = {alias, '_'}, mib_name = MibName, info = '_'},
    snmpa_general_db:match_delete(DB, Pattern1),
    Pattern2 = #symbol{key = {oid, '_'}, mib_name = MibName, info = '_'},
    snmpa_general_db:match_delete(DB, Pattern2),
    {noreply, S};

handle_cast({add_table_infos, MibName, TableInfos}, #state{db = DB} = S) ->
    ?vlog("add table infos for ~p:",[MibName]),
    F = fun({Name, TableInfo}) ->
		?vlog("add table info~n   ~p -> ~p",
		      [Name, TableInfo]),
		Rec = #symbol{key      = {table_info, Name}, 
			      mib_name = MibName, 
			      info     = TableInfo},
		snmpa_general_db:write(DB, Rec)
	end,
    lists:foreach(F, TableInfos),
    {noreply, S};

handle_cast({delete_table_infos, MibName}, #state{db = DB} = S) ->
    ?vlog("delete table infos: ~p",[MibName]),
    Pattern = #symbol{key = {table_info, '_'}, mib_name = MibName, info = '_'},
    snmpa_general_db:match_delete(DB, Pattern),
    {noreply, S};

handle_cast({add_variable_infos, MibName, VariableInfos}, 
	    #state{db = DB} = S) ->
    ?vlog("add variable infos for ~p:",[MibName]),
    F = fun({Name, VariableInfo}) ->
		?vlog("add variable info~n   ~p -> ~p",
		      [Name,VariableInfo]),
		Rec = #symbol{key      = {variable_info, Name},
			      mib_name = MibName,
			      info     = VariableInfo},
		snmpa_general_db:write(DB, Rec)
	end,
    lists:foreach(F, VariableInfos),
    {noreply, S};

handle_cast({delete_variable_infos, MibName}, #state{db = DB} = S) ->
    ?vlog("delete variable infos: ~p",[MibName]),
    Pattern = #symbol{key      = {variable_info,'_'}, 
		      mib_name = MibName, 
		      info     = '_'},
    snmpa_general_db:match_delete(DB, Pattern),
    {noreply, S};

handle_cast({verbosity,Verbosity}, State) ->
    ?vlog("verbosity: ~p -> ~p",[get(verbosity),Verbosity]),
    put(verbosity,snmp_verbosity:validate(Verbosity)),
    {noreply, State};
    
handle_cast(Msg, S) ->
    info_msg("received unknown message: ~n~p", [Msg]),
    {noreply, S}.
    

handle_info(Info, S) ->
    info_msg("received unknown info: ~n~p", [Info]),    
    {noreply, S}.


terminate(Reason, S) ->
    ?vlog("terminate: ~p",[Reason]),
    snmpa_general_db:close(S#state.db).


%%----------------------------------------------------------
%% Code change
%%----------------------------------------------------------

% downgrade
code_change({down, _Vsn}, #state{db = DB} = S, downgrade_to_404) ->
    ?d("code_change(down) -> entry", []),
    Pat   = #symbol{key = {oid, '_'}, _ = '_'},
    Syms = snmpa_general_db:match_object(DB, Pat),
    F = fun(#symbol{key = {oid, Oid} = Key} = Sym0) -> 
		?d("code_change(down) -> downgrading oid ~w", [Oid]),
		snmpa_general_db:delete(DB, Key),
		Sym1 = Sym0#symbol{key = {alias, Oid}},
		snmpa_general_db:write(DB, Sym1)
	end,
    lists:foreach(F, Syms),
    ?d("code_change(down) -> done", []),
    {ok, S};

% upgrade
code_change(_Vsn, #state{db = DB} = S, upgrade_from_404) ->
    ?d("code_change(up) -> entry", []),
    Pat   = #symbol{key = {alias, '_'}, _ = '_'},
    Syms0 = snmpa_general_db:match_object(DB, Pat),
    Syms  = [Sym || #symbol{key = {alias, Oid}} = Sym <- Syms0, list(Oid)],
    F = fun(#symbol{key = {alias, Oid} = Key} = Sym0) -> 
		?d("code_change(up) -> upgrading oid ~w", [Oid]),
		snmpa_general_db:delete(DB, Key),
		Sym1 = Sym0#symbol{key = {oid, Oid}},
		snmpa_general_db:write(DB, Sym1)
	end,
    lists:foreach(F, Syms),
    ?d("code_change(up) -> done", []),
    {ok, S};

code_change(_Vsn, S, _Extra) ->
    ?d("code_change -> entry [do nothing]", []),
    {ok, S}.




    
%%-----------------------------------------------------------------
%% Trap operations (write, read, delete)
%%-----------------------------------------------------------------
%% A notification is stored as {Key, Value}, where
%% Key is the symbolic trap name, and Value is 
%% a #trap or a #notification record.
%%-----------------------------------------------------------------
%% Returns: {value, Value} | undefined
%%-----------------------------------------------------------------
get_notif(Db, Key) ->
    case snmpa_general_db:read(Db, {trap, Key}) of
	{value,#symbol{info = Value}} -> {value, Value};
	false -> undefined
    end.

set_notif(Db, MibName, Trap) when record(Trap, trap) ->
    #trap{trapname = Key} = Trap,
    Rec = #symbol{key = {trap, Key}, mib_name = MibName, info = Trap},
    snmpa_general_db:write(Db, Rec);
set_notif(Db, MibName, Trap) ->
    #notification{trapname = Key} = Trap,
    Rec = #symbol{key = {trap, Key}, mib_name = MibName, info = Trap},
    snmpa_general_db:write(Db, Rec).

delete_notif(Db, MibName) ->
    Pattern = #symbol{key = {trap, '_'}, mib_name = MibName, info = '_'},
    snmpa_general_db:match_delete(Db, Pattern).


%% -------------------------------------

get_verbosity(L) -> 
    snmp_misc:get_option(verbosity,L,?default_verbosity).

get_mib_storage(L) -> 
    snmp_misc:get_option(mib_storage,L,ets).


%% -------------------------------------

call(Req) ->
    call(Req, infinity).

call(Req, Timeout) ->
    gen_server:call(?SERVER, Req, Timeout).

cast(Msg) ->
    gen_server:cast(?SERVER, Msg).


%% ----------------------------------------------------------------

info_msg(F, A) ->
    error_logger:info_msg("~w: " ++ F ++ "~n", [?MODULE|A]).

config_err(F, A) ->
    snmpa_error:config_err(F, A).
 
