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
%%----------------------------------------------------------------------
%% Purpose: Verify the implementation of the ITU-T protocol H.248
%%----------------------------------------------------------------------
%% Run the entire test suite with:
%% 
%%    megaco_test_lib:t(megaco_test).
%%    megaco_test_lib:t({megaco_test, all}).
%%    
%% Or parts of it:
%% 
%%    megaco_test_lib:t({megaco_test, accept}).
%%----------------------------------------------------------------------
-module(megaco_mess_test).

% -export([all/1, init_per_testcase/2, fin_per_testcase/2]).
% -export([connect/1,
% 	 request_and_reply/1,
% 	 request_and_no_reply/1,
% 	 pending_ack/1,
% 	 dist/1,

% 	 tickets/1,
% 	 otp_4359/1
% 	]).
-compile(export_all).

-include_lib("megaco/include/megaco.hrl").
-include_lib("megaco/include/megaco_message_v1.hrl").
-include("megaco_test_lib.hrl").

-define(TEST_VERBOSITY, debug).
-define(MGC_VERBOSITY,  debug).
-define(MG_VERBOSITY,   debug).

-define(MGC_START(Pid, Mid, ET, Verb), 
	megaco_test_mgc:start(Pid, Mid, ET, Verb)).
-define(MGC_STOP(Pid), megaco_test_mgc:stop(Pid)).
-define(MGC_REQ_PEND(Pid,To), megaco_test_mgc:request_pending(Pid,To)).

-define(MG_START(Pid, Mid, Enc, Transp, Conf, Verb), 
	megaco_test_mg:start(Pid, Mid, Enc, Transp, Conf, Verb)).
-define(MG_STOP(Pid), megaco_test_mg:stop(Pid)).
-define(MG_SERV_CHANGE(Pid), megaco_test_mg:service_change(Pid)).
-define(MG_NOTIF_REQ(Pid), megaco_test_mg:notify_request(Pid)).
-define(MG_AWAIT_NOTIF_REP(Pid), megaco_test_mg:await_notify_reply(Pid)).
-define(MG_CONN_INFO(Pid,Tag), megaco_test_mg:conn_info(Pid,Tag)).
-define(MG_USER_INFO(Pid,Tag), megaco_test_mg:user_info(Pid,Tag)).
-define(MG_NOTIF_RAR(Pid), megaco_test_mg:notify_request_and_reply(Pid)).

-define(SEND(Expr), 
	?VERIFY(ok, megaco_mess_user_test:apply_proxy(fun() -> Expr end))).

-define(USER(Expected, Reply),
	megaco_mess_user_test:reply(?MODULE,
				    ?LINE,
				    fun(Actual) ->
				       case ?VERIFY(Expected, Actual) of
					   Expected   -> {ok, Reply};
					   UnExpected -> {error, {reply_verify,
								  ?MODULE,
								  ?LINE,
								  UnExpected}}
				       end
				    end)).
	
t()     -> megaco_test_lib:t(?MODULE).
t(Case) -> megaco_test_lib:t({?MODULE, Case}).

%% Test server callbacks
% init_per_testcase(pending_ack = Case, Config) ->
%     put(dbg,true),
%     megaco_test_lib:init_per_testcase(Case, Config);
init_per_testcase(Case, Config) ->
    megaco_test_lib:init_per_testcase(Case, Config).

% fin_per_testcase(pending_ack = Case, Config) ->
%     erase(dbg),
%     megaco_test_lib:fin_per_testcase(Case, Config);
fin_per_testcase(Case, Config) ->
    megaco_test_lib:fin_per_testcase(Case, Config).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

all(suite) ->
    [
     connect,
     request_and_reply,
     request_and_no_reply,
     pending_ack,
     dist,

     %% Tickets last
     tickets
    ].

tickets(suite) ->
    [
     otp_4359,
     otp_4836,
     otp_5805,
     otp_5881,
     otp_5887
    ].


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

connect(suite) ->
    [];
connect(doc) ->
    [];
connect(Config) when list(Config) ->
    ?ACQUIRE_NODES(1, Config),
    PrelMid = preliminary_mid,
    MgMid   = ipv4_mid(4711),

    ?VERIFY(ok, application:start(megaco)),
    ?VERIFY(ok,	megaco:start_user(MgMid, [{send_mod, bad_send_mod},
	                                  {request_timer, infinity},
	                                  {reply_timer, infinity}])),

    MgRH = user_info(MgMid, receive_handle),
    {ok, PrelCH} = ?VERIFY({ok, _}, megaco:connect(MgRH, PrelMid, sh, self())),

    connections([PrelCH]),
    ?VERIFY([PrelCH], megaco:user_info(MgMid, connections)),
    
    ?VERIFY(bad_send_mod, megaco:user_info(MgMid, send_mod)),
    ?VERIFY(bad_send_mod, megaco:conn_info(PrelCH, send_mod)),
    SC = service_change_request(),
    ?VERIFY({1, {error, {send_message_failed, {'EXIT',
                  {undef, [{bad_send_mod, send_message, [sh, _]} | _]}}}}},
	     megaco:call(PrelCH, [SC], [])),

    ?VERIFY(ok, megaco:disconnect(PrelCH, shutdown)),

    ?VERIFY(ok,	megaco:stop_user(MgMid)),
    ?VERIFY(ok, application:stop(megaco)),
    ?RECEIVE([]),
    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

request_and_reply(suite) ->
    [];
request_and_reply(Config) when list(Config) ->
    ?ACQUIRE_NODES(1, Config),
    d("request_and_reply -> start proxy",[]),
    megaco_mess_user_test:start_proxy(),

    PrelMid = preliminary_mid,
    MgMid   = ipv4_mid(4711),
    MgcMid  = ipv4_mid(),
    UserMod = megaco_mess_user_test,
    d("request_and_reply -> start megaco app",[]),
    ?VERIFY(ok, application:start(megaco)),
    UserConfig = [{user_mod, UserMod}, {send_mod, UserMod},
		  {request_timer, infinity}, {reply_timer, infinity}],
    d("request_and_reply -> start (MG) user ~p",[MgMid]),
    ?VERIFY(ok,	megaco:start_user(MgMid, UserConfig)),

    d("request_and_reply -> start (MGC) user ~p",[MgcMid]),
    ?VERIFY(ok,	megaco:start_user(MgcMid, UserConfig)),

    d("request_and_reply -> get receive info for ~p",[MgMid]),
    MgRH = user_info(MgMid, receive_handle),
    d("request_and_reply -> get receive info for ~p",[MgcMid]),
    MgcRH = user_info(MgcMid, receive_handle), 
    d("request_and_reply -> start transport",[]),
    {ok, MgPid, MgSH} =
	?VERIFY({ok, _, _}, UserMod:start_transport(MgRH, MgcRH)),
    PrelMgCH = #megaco_conn_handle{local_mid = MgMid,
				   remote_mid = preliminary_mid},
    MgCH  = #megaco_conn_handle{local_mid = MgMid,
				remote_mid = MgcMid},
    MgcCH = #megaco_conn_handle{local_mid = MgcMid,
				remote_mid = MgMid},
    d("request_and_reply -> (MG) try connect to MGC",[]),
    ?SEND(megaco:connect(MgRH, PrelMid, MgSH, MgPid)), % Mg prel
    d("request_and_reply -> (MGC) await connect from MG",[]),
    ?USER({connect, PrelMgCH, _V, []}, ok),
    ?RECEIVE([{res, _, {ok, PrelMgCH}}]),

    d("request_and_reply -> (MG) send service change request",[]),
    Req = service_change_request(),
    ?SEND(megaco:call(PrelMgCH, [Req], [])),

    d("request_and_reply -> (MGC) send service change reply",[]),
    ?USER({connect, MgcCH, _V, []}, ok), % Mgc auto
    Rep = service_change_reply(MgcMid),
    ?USER({request, MgcCH, _V, [[Req]]}, {discard_ack, [Rep]}),
    ?USER({connect, MgCH, _V, []}, ok), % Mg confirm
    ?RECEIVE([{res, _, {1, {ok, [Rep]}}}]),

    d("request_and_reply -> get (system info) connections",[]),
    connections([MgCH, MgcCH]),
    d("request_and_reply -> get (~p) connections",[MgMid]),
    ?VERIFY([MgCH], megaco:user_info(MgMid, connections)),
    d("request_and_reply -> get (~p) connections",[MgcMid]),
    ?VERIFY([MgcCH], megaco:user_info(MgcMid, connections)),

    Reason = shutdown,
    d("request_and_reply -> (MG) disconnect",[]),
    ?SEND(megaco:disconnect(MgCH, Reason)),
    ?USER({disconnect, MgCH, _V, [{user_disconnect, Reason}]}, ok),
    ?RECEIVE([{res, _, ok}]),
    ?VERIFY(ok,	megaco:stop_user(MgMid)),

    d("request_and_reply -> (MGC) disconnect",[]),
    ?SEND(megaco:disconnect(MgcCH, Reason)),
    ?USER({disconnect, MgcCH, _V, [{user_disconnect, Reason}]}, ok),
    ?RECEIVE([{res, _, ok}]),
    ?VERIFY(ok,	megaco:stop_user(MgcMid)),

    d("request_and_reply -> stop megaco app",[]),
    ?VERIFY(ok, application:stop(megaco)),
    ?RECEIVE([]),
    d("request_and_reply -> done",[]),
    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% OTP-4760
request_and_no_reply(suite) ->
    [];
request_and_no_reply(doc) ->
    [];
request_and_no_reply(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        request_and_no_reply),
    i("starting"),

    MgcNode = make_node_name(mgc),
    MgNode  = make_node_name(mg),
    d("start nodes: "
      "~n   MgcNode: ~p"
      "~n   MgNode:  ~p", 
      [MgcNode, MgNode]),
    ok = megaco_test_lib:start_nodes([MgcNode, MgNode], ?FILE, ?LINE),

    %% Start the MGC and MGs
    i("[MGC] start"),    
    ET = [{text,tcp}, {text,udp}, {binary,tcp}, {binary,udp}],
    {ok, Mgc} = 
	?MGC_START(MgcNode, {deviceName, "ctrl"}, ET, ?MGC_VERBOSITY),

    i("[MG] start"),    
    MgMid = {deviceName, "mg"},
    ReqTmr = #megaco_incr_timer{wait_for    = 3000,
				factor      = 1, 
				incr        = 0,
				max_retries = 2
			       },
    LongReqTmr = #megaco_incr_timer{wait_for    = 10000,
				    factor      = 1, 
				    incr        = 0,
				    max_retries = 3
				   },
    PendingTmr = 10000,
    ReplyTmr = 16000,
    MgConfig = [{request_timer,      ReqTmr}, 
		{long_request_timer, LongReqTmr}, 
		{pending_timer,      PendingTmr},
		{reply_timer,        ReplyTmr}],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    d("MG user info: ~p", [?MG_USER_INFO(Mg, all)]),

    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    d("tell the MGC to ignore requests"),
    ?MGC_REQ_PEND(Mgc, infinity),

    d("[MG] send the notify"),
    ?MG_NOTIF_REQ(Mg),

    d("[MG] await notify reply"),
    {ok, {_Vsn, {error, timeout}}} = ?MG_AWAIT_NOTIF_REP(Mg),

    d("[MG] received expected reply"),

    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

pending_ack(suite) ->
    [];
pending_ack(Config) when list(Config) ->

%     MgcNode = make_node_name(mgc),
%     Mg1Node = make_node_name(mg1),

%     d("pending_ack -> create nodes",[]),
%     ok = megaco_test_lib:start_nodes([MgcNode, Mg1Node], ?FILE, ?LINE),

%     d("pending_ack -> start MGC",[]),
%     MgcMid = ipv4_mid(),
%     ET = [{text,tcp}, {text,udp}, {binary,tcp}, {binary,udp}],
%     {ok, Mgc} = ?MGC_START(MgcNode, MgcMid, ET, ?MGC_VERBOSITY),

%     d("pending_ack -> start MG",[]),
%     MgMid  = ipv4_mid(4711),
%     {ok, Mg1} = ?MG_START(Mg1Node, MgMid, text, tcp, ?MG_VERBOSITY),
    
%     d("pending_ack -> (MGC) request action changed to pending",[]),
%     {ok, _} = ?MGC_REQ_PEND(Mgc,3500),

%     d("pending_ack -> (MG) perform service change",[]),
%     ok = ?MG_SERV_CHANGE(Mg1),
    
%     d("pending_ack -> wait some",[]),
%     sleep(1000),

    %% ----------------------------------------------

    ?ACQUIRE_NODES(1, Config),
    d("pending_ack -> start proxy",[]),
    megaco_mess_user_test:start_proxy(),
    
    PrelMid = preliminary_mid,
    MgMid   = ipv4_mid(4711),
    MgcMid  = ipv4_mid(),
    UserMod = megaco_mess_user_test,
    d("pending_ack -> start megaco app",[]),
    ?VERIFY(ok, application:start(megaco)),
    UserData = user_data,
    UserConfig = [{user_mod, UserMod},
		  {send_mod, UserMod},
		  {request_timer, infinity},
		  {long_request_timer, infinity},
		  {reply_timer, infinity}],
    
    d("pending_ack -> start megaco user MG (~p)",[MgMid]),
    ?VERIFY(ok,	megaco:start_user(MgMid, UserConfig)),
    
    d("pending_ack -> start megaco user MGC (~p)",[MgcMid]),
    ?VERIFY(ok,	megaco:start_user(MgcMid, UserConfig)),
    
    d("pending_ack -> retrieve (user info) receive_handle for MG",[]),
    MgRH = user_info(MgMid, receive_handle),
    
    d("pending_ack -> retrieve (user info) receive_handle for MGC",[]),
    MgcRH = user_info(MgcMid, receive_handle), 
    
    d("pending_ack -> start transport",[]),
    {ok, MgPid, MgSH} =
 	?VERIFY({ok, _, _}, UserMod:start_transport(MgRH, MgcRH)),
    PrelMgCH = #megaco_conn_handle{local_mid = MgMid,
				    remote_mid = preliminary_mid},
    MgCH  = #megaco_conn_handle{local_mid = MgMid,
				 remote_mid = MgcMid},
    MgcCH = #megaco_conn_handle{local_mid = MgcMid,
				 remote_mid = MgMid},
    
    d("pending_ack -> (MG) connect",[]),
    ?SEND(megaco:connect(MgRH, PrelMid, MgSH, MgPid)), % Mg prel
    
    d("pending_ack -> (MG) await connect",[]),
    ?USER({connect, PrelMgCH, _V, []}, ok),
    
    ?RECEIVE([{res, _, {ok, PrelMgCH}}]),
    
    d("pending_ack -> (MG) send service change request",[]),
    Req = service_change_request(),
    ?VERIFY(ok, megaco:cast(PrelMgCH, [Req], [{reply_data, UserData}])),
    
    d("pending_ack -> (MGC) await connect",[]),
    ?USER({connect, MgcCH, _V, []}, ok), % Mgc auto
    
    d("pending_ack -> (MGC) "
       "await service change request (reply with pending)",[]),
    RequestData = Req,
    ?USER({request, MgcCH, _V, [[Req]]}, {pending, RequestData}),
    Rep = service_change_reply(MgcMid),
    AckData = ack_data,
    %% BUGBUG: How do we verify that the MG rally gets a pending trans?
    d("pending_ack -> (MGC) await long request (result of pending)",[]),
    ?USER({long_request, MgcCH, _V, [RequestData]}, 
	  {{handle_ack, AckData}, [Rep]}),
    d("pending_ack -> (MG) await connect",[]),
    ?USER({connect, MgCH, _V, []}, ok), % Mg confirm

    %% **************************************************
    %% The following 2 USER calls should really happen
    %% in the order reply - ack, but due to timing, could
    %% happen in ack - reply.
    %% 
    %% START
    %% 
    d("pending_ack -> (MG) await service change reply",[]),
    ?USER({reply, MgCH, _V, [{ok, [Rep]}, UserData]}, ok),

    d("pending_ack -> (MGC) await service change ack",[]),
    ?USER({ack, MgcCH, _V, [ok, AckData]}, ok),

    %% 
    %% END
    %% 
    %% **************************************************


    connections([MgCH, MgcCH]),
    ?VERIFY([MgCH], megaco:user_info(MgMid, connections)),
    ?VERIFY([MgcCH], megaco:user_info(MgcMid, connections)),
    
    %% Reason = shutdown,
    ?SEND(application:stop(megaco)),
    ?RECEIVE([{res, _, ok}]),
    d("pending_ack -> done",[]),
    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

dist(suite) ->
    [];
dist(Config) when list(Config) ->
    [_Local, Dist] = ?ACQUIRE_NODES(2, Config),
    d("dist -> start proxy",[]),
    megaco_mess_user_test:start_proxy(),

    PrelMid = preliminary_mid,
    MgMid   = ipv4_mid(4711),
    MgcMid  = ipv4_mid(),
    UserMod = megaco_mess_user_test,
    d("dist -> start megaco app",[]),
    ?VERIFY(ok, application:start(megaco)),
    UserConfig = [{user_mod, UserMod}, {send_mod, UserMod},
		  {request_timer, infinity}, {reply_timer, infinity}],

    d("dist -> start megaco user MG (~p)",[MgMid]),
    ?VERIFY(ok,	megaco:start_user(MgMid, UserConfig)),

    d("dist -> start megaco user MGC (~p)",[MgcMid]),
    ?VERIFY(ok,	megaco:start_user(MgcMid, UserConfig)),

    d("dist -> retrieve (user info) receive_handle for MG",[]),
    MgRH = user_info(MgMid, receive_handle),

    d("dist -> retrieve (user info) receive_handle for MGC",[]),
    MgcRH = user_info(MgcMid, receive_handle), 

    d("dist -> start transport",[]),
    {ok, MgPid, MgSH} =
	?VERIFY({ok, _, _}, UserMod:start_transport(MgRH, MgcRH)),
    PrelMgCH = #megaco_conn_handle{local_mid = MgMid,
				   remote_mid = preliminary_mid},
    MgCH  = #megaco_conn_handle{local_mid = MgMid,
				remote_mid = MgcMid},
    MgcCH = #megaco_conn_handle{local_mid = MgcMid,
				remote_mid = MgMid},

    d("dist -> (MG) connect",[]),
    ?SEND(megaco:connect(MgRH, PrelMid, MgSH, MgPid)), % Mg prel

    d("dist -> (MG) await connect",[]),
    ?USER({connect, PrelMgCH, _V, []}, ok),
    ?RECEIVE([{res, _, {ok, PrelMgCH}}]),

    d("dist -> (MG) send service change request",[]),
    Req = service_change_request(),
    ?SEND(megaco:call(PrelMgCH, [Req], [])),

    d("dist -> (MGC) await auto-connect",[]),
    ?USER({connect, MgcCH, _V, []}, ok), % Mgc auto


    Rep = service_change_reply(MgcMid),
    d("dist -> (MGC) "
      "await service change request and send reply when received",[]),
    ?USER({request, MgcCH, _V, [[Req]]}, {discard_ack, [Rep]}),

    d("dist -> (MG) await connect",[]),
    ?USER({connect, MgCH, _V, []}, ok), % Mg confirm

    d("dist -> (MG) await service change reply",[]),
    ?RECEIVE([{res, _, {1, {ok, [Rep]}}}]),

    %% Dist
    d("dist -> start megaco on ~p", [Dist]),
    ?VERIFY(ok,	rpc:call(Dist, megaco, start, [])),

    d("dist -> start megaco user on ~p", [Dist]),
    ?VERIFY(ok,	rpc:call(Dist, megaco, start_user, [MgcMid, UserConfig])),

    d("dist -> (MG) connect to MGC", []),
    MgcPid = self(),
    MgcSH  = {element(2, MgSH), element(1, MgSH)},
    ?SEND(rpc:call(Dist, megaco, connect, [MgcRH, MgMid, MgcSH, MgcPid])), % Mgc dist

    d("dist -> (MGC) await auto-connect (from MG on ~p)", [Dist]),
    ?USER({connect, MgcCH, _V, []}, ok), % Mgc dist auto
    ?RECEIVE([{res, _, {ok, MgcCH}}]),

    d("dist -> (~p:MG) send service change request",[Dist]),
    ?SEND(rpc:call(Dist, megaco, call, [MgcCH, [Req], []])),

    d("dist -> (MG????????) "
      "await service change request and send reply when received",[]),
    ?USER({request, MgCH, _V, [[Req]]}, {discard_ack, [Rep]}),
    ?RECEIVE([{res, _, {1, {ok, [Rep]}}}]),

    d("dist -> retreive some info",[]),
    connections([MgCH, MgcCH]),
    ?VERIFY([MgCH], megaco:user_info(MgMid, connections)),
    ?VERIFY([MgcCH], megaco:user_info(MgcMid, connections)),

    ?VERIFY([MgcCH], rpc:call(Dist, megaco, system_info, [connections])),
    ?VERIFY([], rpc:call(Dist, megaco, user_info, [MgMid, connections])),
    ?VERIFY([MgcCH], rpc:call(Dist, megaco, user_info, [MgcMid, connections])),

    %% Shutdown

    d("dist -> close down the shop...",[]),
    Reason = shutdown,
    ?SEND(megaco:disconnect(MgCH, Reason)),
    ?USER({disconnect, MgCH, _V, [{user_disconnect, Reason}]}, ok),
    ?RECEIVE([{res, _, ok}]),
    ?VERIFY(ok,	megaco:stop_user(MgMid)),

    ?SEND(megaco:disconnect(MgcCH, Reason)),
    ?USER({disconnect, MgcCH, _V, [{user_disconnect, Reason}]}, ok),
    ?USER({disconnect, MgcCH, _V, [{user_disconnect, Reason}]}, ok),
    ?RECEIVE([{res, _, ok}]),
    ?VERIFY(ok,	megaco:stop_user(MgcMid)),

    ?VERIFY(ok, application:stop(megaco)),
    ?RECEIVE([]),
    d("dist -> done",[]),
    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

otp_4359(suite) ->
    [];
otp_4359(Config) when list(Config) ->
    ?ACQUIRE_NODES(1, Config),
    Mid = {deviceName, "dummy_mid"},

    io:format("otp_4359 -> start megaco application~n", []),
    ?VERIFY(ok, application:start(megaco)),

    io:format("otp_4359 -> start and configure megaco user~n", []),
    ?VERIFY(ok,	megaco:start_user(Mid, [{send_mod, ?MODULE},
					{request_timer, infinity},
					{reply_timer, infinity}])),

    ?VERIFY(ok, megaco:update_user_info(Mid, user_mod,  ?MODULE)),
    ?VERIFY(ok, megaco:update_user_info(Mid, user_args, [self()])),
    RH0 = user_info(Mid, receive_handle),
    RH1 = RH0#megaco_receive_handle{send_mod        = ?MODULE,
				    encoding_mod    = megaco_compact_text_encoder,
				    encoding_config = []},

    %% First an erroneous transaction (missing the transaction id number)
    %% then an valid transaction.
    M = "!/1 ml2 "
	"T={C=${A=${M{O {MO=SR,RG=OFF,RV=OFF}}}}}"
	"T=1{C=${A=${M{O {MO=SR,RG=OFF,RV=OFF}}}}}",

    %% Simulate incomming message
    %% Will result in an (auto) connect first
    io:format("otp_4359 -> simulate receive message~n", []),
    megaco:receive_message(RH1, self(), self(), list_to_binary(M)),
    io:format("otp_4359 -> await actions~n", []),
    Actions = otp_4359_await_actions([{handle_connect, ignore}, 
				      {send_message, ?megaco_bad_request}, 
				      {handle_trans_request, ignore}, 
				      {send_message, ?megaco_not_implemented}]), 
    io:format("otp_4359 -> analyze actions~n", []),
    otp_4359_analyze_result(RH1, Actions),

    Conns = megaco:system_info(connections),
    OKs   = lists:duplicate(length(Conns),ok),
    ?VERIFY(OKs, [megaco:disconnect(CH, test_complete) || CH <- Conns]),
    stop_user(Mid),
    ?VERIFY(ok, application:stop(megaco)),
    ?RECEIVE([]),
    ok.


otp_4359_await_actions(Exp) ->
    otp_4359_await_actions(Exp, []).

otp_4359_await_actions([], Rep) ->
    lists:reverse(Rep);
otp_4359_await_actions([{M,I}|R] = _All, Rep) ->
    receive
	{M, Info} ->
	    otp_4359_await_actions(R, [{M, I, Info}|Rep]);
	Else ->
	    exit({received_unexpected_message, M, Else})
	    %% io:format("received unexpected: ~p~n", [Else]),
	    %% otp_4359_await_actions(All, Rep)
    after 10000 ->
	    exit(timeout)
    end.

otp_4359_analyze_result(_RH, []) ->
    ok;
otp_4359_analyze_result(RH, 
			[{send_message, ExpErrorCode, EncodedMessage}|L]) ->
    io:format("otp_4359_analyze_result -> send_message: ", []),
    otp_4359_analyze_encoded_message(RH, ExpErrorCode, EncodedMessage),
    otp_4359_analyze_result(RH,L);
otp_4359_analyze_result(RH, [{M,ignore,_}|T]) ->
    io:format("otp_4359_analyze_result -> ignoring ~p~n", [M]),
    otp_4359_analyze_result(RH,T).

otp_4359_analyze_encoded_message(RH, ExpErrorCode, M) 
  when record(RH, megaco_receive_handle), binary(M) ->
    #megaco_receive_handle{encoding_mod    = Mod,
			   encoding_config = Conf} = RH,
    case (catch Mod:decode_message(Conf, M)) of
	{ok, #'MegacoMessage'{mess = #'Message'{messageBody = Body}}} ->
	    case Body of
		{transactions, [{transactionReply,Reply}]} ->
		    case Reply of
			#'TransactionReply'{transactionResult = Result} ->
			    case Result of
				{transactionError,ED} when record(ED, 'ErrorDescriptor') ->
				    case ED#'ErrorDescriptor'.errorCode of
					ExpErrorCode ->
					    io:format("error code ~p ok~n", [ExpErrorCode]),
					    ok;
					Code ->
					    io:format("error code ~p erroneous~n", [Code]),
					    exit({unexpected_error_code, ExpErrorCode, Code})
				    end;
				_ ->
				    io:format("unexpected trans result~n", []),
				    exit({unexpected_trans_result, Result})
			    end;
			_ ->
			    io:format("unexpected trans reply~n", []),
			    exit({unexpected_trans_reply, Reply})
		    end;
		_ ->
		    io:format("unexpected body~n", []),
		    exit({unexpected_body, Body})
	    end;

	Else ->
	    io:format("unexpected decode result~n", []),
	    exit({unexpected_decode_result, Else})
    end.
	    
    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

otp_4836(suite) ->
    [];
otp_4836(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        otp_4836),
    i("starting"),

    MgcNode = make_node_name(mgc),
    MgNode  = make_node_name(mg),
    d("start nodes: "
      "~n   MgcNode: ~p"
      "~n   MgNode:  ~p", 
      [MgcNode, MgNode]),
    ok = megaco_test_lib:start_nodes([MgcNode, MgNode], ?FILE, ?LINE),

    d("start the MGC simulator (generator)"),
    {ok, Mgc} = megaco_test_generator:start_link("MGC", MgcNode),

    d("create the MGC event sequence"),
    MgcEvSeq = otp_4836_mgc_event_sequence(text, tcp),

    d("start the MGC simulation"),
    megaco_test_generator:tcp(Mgc, MgcEvSeq),

    i("[MG] start"),    
    MgMid = {deviceName, "mg"},
    ReqTmr = #megaco_incr_timer{wait_for    = 3000,
                                factor      = 1, 
                                incr        = 0,
                                max_retries = 3},
    %% 5000,  %% Does not matter since we will not use this anyway...
    LongReqTmr = #megaco_incr_timer{wait_for    = 3000,
                                    factor      = 1, 
                                    incr        = 0,
                                    max_retries = 3},
    PendingTmr = 10000,
    ReplyTmr = 16000,
    MgConfig = [{request_timer,      ReqTmr}, 
                {long_request_timer, LongReqTmr}, 
                {pending_timer,      PendingTmr},
                {reply_timer,        ReplyTmr}],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    d("[MG] send the notify"),
    {ok, Reply} = (catch ?MG_NOTIF_RAR(Mg)),
    {1, {ok, [AR]}} = Reply,
    d("[MG] ActionReply: ~p", [AR]),

    d("[MGC] await the tcp reply"),
    {ok, TcpReply} = megaco_test_generator:tcp_await_reply(Mgc),
    d("[MGC] TcpReply: ~p", [TcpReply]),

    %% Tell MG to stop
    i("[MG] stop"),
    ?MG_STOP(Mg),

    %% Tell Mgc to stop
    i("[MGC] stop generator"),
    megaco_test_generator:stop(Mgc),

    i("done", []),
    ok.


otp_4836_mgc_event_sequence(text, tcp) ->
    DecodeFun = otp_4836_decode_msg_fun(megaco_pretty_text_encoder, []),
    EncodeFun = otp_4836_encode_msg_fun(megaco_pretty_text_encoder, []),
    ServiceChangeVerifyFun = otp_4836_verify_service_change_req_msg_fun(),
    Mid = {deviceName,"ctrl"},
    ServiceChangeReply = otp_4836_service_change_reply_msg(Mid, 1, 0),
    NotifyReqVerifyFun = otp_4836_verify_notify_request_fun(),
    TermId = #megaco_term_id{id = ["00000000","00000000","01101101"]},
    NotifyReply = otp_4836_notify_reply_msg(Mid, 2, 0, TermId),
    Pending = otp_4836_pending_msg(Mid,2),
    MgcEvSeq = [{debug,  true},
		{decode, DecodeFun},
		{encode, EncodeFun},
		{listen, 2944},
		{expect_accept, any},
		{expect_receive, "service-change-request", {ServiceChangeVerifyFun, 10000}}, 
		{send, "service-change-reply", ServiceChangeReply}, 
		{expect_receive, "notify-request", {NotifyReqVerifyFun, 10000}},
		{send, "pending 1", Pending}, 
		{sleep, 100},
		{send, "pending 2", Pending}, 
		{sleep, 500},
  		{send, "notify-reply", NotifyReply}
	       ],
    MgcEvSeq.

otp_4836_service_change_reply_msg(Mid, TransId, Cid) ->
    SCRP  = #'ServiceChangeResParm'{serviceChangeMgcId = Mid},
    SCRPs = {serviceChangeResParms,SCRP},
    Root  = #megaco_term_id{id = ["root"]},
    SCR   = #'ServiceChangeReply'{terminationID       = [Root],
				  serviceChangeResult = SCRPs},
    CR    = {serviceChangeReply, SCR},
    otp_4836_msg(Mid, TransId, CR, Cid).

otp_4836_notify_reply_msg(Mid, TransId, Cid, TermId) ->
    NR  = #'NotifyReply'{terminationID = [TermId]},
    CR  = {notifyReply, NR},
    otp_4836_msg(Mid, TransId, CR, Cid).

otp_4836_msg(Mid, TransId, CR, Cid) ->
    AR  = #'ActionReply'{contextId    = Cid,
			 commandReply = [CR]},
    ARs  = {actionReplies, [AR]},
    TR   = #'TransactionReply'{transactionId     = TransId,
			       transactionResult = ARs},
    Body = {transactions, [{transactionReply, TR}]},
    Mess = #'Message'{version     = 1,
		      mId         = Mid,
		      messageBody = Body},
    #'MegacoMessage'{mess = Mess}.


otp_4836_pending_msg(Mid, TransId) ->
    TP   = #'TransactionPending'{transactionId = TransId},
    Body = {transactions, [{transactionPending, TP}]},
    Mess = #'Message'{version     = 1,
		      mId         = Mid,
		      messageBody = Body},
    #'MegacoMessage'{mess = Mess}.


otp_4836_encode_msg_fun(Mod, Conf) ->
    fun(M) -> 
	    Mod:encode_message(Conf, M) 
    end.
otp_4836_encode_msg_fun(Mod, Conf, Ver) ->
    fun(M) -> 
	    Mod:encode_message(Conf, Ver, M) 
    end.

otp_4836_decode_msg_fun(Mod, Conf) ->
    fun(M) -> 
	    Mod:decode_message(Conf, M) 
    end.
otp_4836_decode_msg_fun(Mod, Conf, Ver) ->
    fun(M) -> 
	    Mod:decode_message(Conf, Ver, M) 
    end.

otp_4836_verify_msg_fun() ->
    fun(M) -> {ok, M} end.

otp_4836_verify_service_change_req_msg_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
	    #'Message'{version     = _V,
		       mId         = _Mid,
		       messageBody = Body} = Mess,
	    {transactions, [Trans]} = Body,
	    {transactionRequest, TR} = Trans,
	    #'TransactionRequest'{transactionId = _Tid,
				  actions = [AR]} = TR,
	    #'ActionRequest'{contextId = _Cid,
			     contextRequest = _CtxReq,
			     contextAttrAuditReq = _CtxAar,
			     commandRequests = [CR]} = AR,
	    #'CommandRequest'{command = Cmd,
			      optional = _Opt,
			      wildcardReturn = _WR} = CR,
	    {serviceChangeReq, SCR} = Cmd,
	    #'ServiceChangeRequest'{terminationID = _TermID,
				    serviceChangeParms = SCP} = SCR,
	    #'ServiceChangeParm'{serviceChangeMethod = restart,
				 serviceChangeReason = [[$9,$0,$1|_]]} = SCP,
	    {ok, M};
       (M) ->
	    {error, {invalid_message, M}}
    end.

otp_4836_verify_notify_request_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
	    #'Message'{messageBody = Body} = Mess,
	    {transactions, [Trans]} = Body,
	    {transactionRequest, TR} = Trans,
	    #'TransactionRequest'{actions = [AR]} = TR,
	    #'ActionRequest'{commandRequests = [CR1,CR2]} = AR,
	    #'CommandRequest'{command = Cmd1} = CR1,
	    {notifyReq, NR1} = Cmd1,
	    #'NotifyRequest'{observedEventsDescriptor = OED1} = NR1,
	    #'ObservedEventsDescriptor'{observedEventLst = [OE1]} = OED1,
	    #'ObservedEvent'{eventName = "al/of"} = OE1,
	    #'CommandRequest'{command = Cmd2} = CR2,
	    {notifyReq, NR2} = Cmd2,
	    #'NotifyRequest'{observedEventsDescriptor = OED2} = NR2,
	    #'ObservedEventsDescriptor'{observedEventLst = [OE2]} = OED2,
	    #'ObservedEvent'{eventName = "al/of"} = OE2,
	    {ok, M};
       (M) ->
	    {error, {invalid_message, M}}
    end.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

otp_5805(suite) ->
    [];
otp_5805(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        otp_5805),
    i("starting"),

    MgcNode = make_node_name(mgc),
    MgNode  = make_node_name(mg),
    d("start nodes: "
	 "~n   MgcNode: ~p"
	 "~n   MgNode:  ~p", 
	 [MgcNode, MgNode]),
    ok = megaco_test_lib:start_nodes([MgcNode, MgNode], ?FILE, ?LINE),

    d("[MGC] start the simulator "),
    {ok, Mgc} = megaco_test_generator:start_link("MGC", MgcNode),

    d("[MGC] create the event sequence"),
    MgcEvSeq = otp_5805_mgc_event_sequence(text, tcp),

    i("wait some time before starting the MGC simulation"),
    sleep(1000),

    d("[MGC] start the simulation"),
    megaco_test_generator:megaco(Mgc, MgcEvSeq, timer:minutes(1)),

    i("wait some time before starting the MG simulator"),
    sleep(1000),

    d("start the MG simulator (generator)"),
    {ok, Mg} = megaco_test_generator:start_link("MG", MgNode),

    d("create the MG event sequence"),
    MgEvSeq = otp_5805_mg_event_sequence(text, tcp),

    d("start the MG simulation"),
    megaco_test_generator:tcp(Mg, MgEvSeq, timer:minutes(1)),

    d("[MGC] await the generator reply"),
    case megaco_test_generator:megaco_await_reply(Mgc) of
        {ok, MgcReply} ->
            d("[MGC] OK => MgcReply: ~n~p", [MgcReply]),
            ok;
        {error, MgcReply} ->
            d("[MGC] ERROR => MgcReply: ~n~p", [MgcReply]),
            ?ERROR(mgc_failed)
    end,

    d("[MG] await the generator reply"),
    case megaco_test_generator:tcp_await_reply(Mg) of
        {ok, MgReply} ->
            d("[MG] OK => MgReply: ~n~p", [MgReply]),
            ok;
        {error, MgReply} ->
            d("[MG] ERROR => MgReply: ~n~p", [MgReply]),
            ?ERROR(mg_failed)
    end,

    %% Tell Mgc to stop
    i("[MGC] stop generator"),
    megaco_test_generator:stop(Mgc),

    %% Tell Mg to stop
    i("[MG] stop generator"),
    megaco_test_generator:stop(Mg),

    i("done", []),
    ok.


otp_5805_mg_event_sequence(text, tcp) ->
    DecodeFun = otp_5805_mg_decode_msg_fun(megaco_pretty_text_encoder, []),
    EncodeFun = otp_5805_mg_encode_msg_fun(megaco_pretty_text_encoder, []),
    Mid = {deviceName,"mg"},
    ServiceChangeReq = otp_5805_mg_service_change_request_msg(Mid, 1, 0),
    ServiceChangeReplyVerifyFun = 
	otp_5805_mg_verify_service_change_rep_msg_fun(),
    NotifyReqNNV = otp_5805_mg_notify_request_msg("1"),
    NotifyReqUV = otp_5805_mg_notify_request_msg("4"),
    EDVerify = otp_5805_mg_verify_error_descriptor_msg_fun(),
    MgEvSeq = [{debug,  true},
	       {decode, DecodeFun},
	       {encode, EncodeFun},
	       {connect, 2944},

	       {send, "service-change-request", ServiceChangeReq}, 
	       {expect_receive, "service-change-reply", {ServiceChangeReplyVerifyFun, 5000}}, 
	       {sleep, 1000},
	       {send, "notify request (not negotiated version)", NotifyReqNNV}, 
	       {expect_receive, "error-descriptor", EDVerify}, 
	       {sleep, 1000},
 	       {send, "notify request (unsupported version)", NotifyReqUV}, 
	       {expect_receive, "error-descriptor", EDVerify}, 

	       {expect_nothing, 4000},
	       disconnect
	      ],
    MgEvSeq.

otp_5805_mg_encode_msg_fun(Mod, Conf) ->
    fun(M) -> 
            Mod:encode_message(Conf, M) 
    end.

otp_5805_mg_decode_msg_fun(Mod, Conf) ->
    fun(M) -> 
            Mod:decode_message(Conf, M) 
    end.

otp_5805_mg_verify_service_change_rep_msg_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
            case Mess of
		#'Message'{version     = 1,
			   mId         = _MgMid,
			   messageBody = Body} ->
		    case Body of
			{transactions, [Trans]} ->
			    case Trans of
				{transactionReply, TR} ->
				    case TR of
					#'TransactionReply'{transactionId = _Tid,
							    immAckRequired = asn1_NOVALUE,
							    transactionResult = Res} ->
					    case Res of
						{actionReplies, [AR]} ->
						    case AR of
							#'ActionReply'{contextId = _Cid,
								       errorDescriptor = asn1_NOVALUE,
								       contextReply    = _CtxReq,
								       commandReply    = [CR]} ->
							    case CR of
								{serviceChangeReply, SCR} ->
								    case SCR of
									#'ServiceChangeReply'{
									       terminationID       = _TermID,
									       serviceChangeResult = SCRes} ->
									    case SCRes of
										{serviceChangeResParms, SCRP} ->
										    case SCRP of
											#'ServiceChangeResParm'{
												serviceChangeMgcId   = _MgcMid,
												serviceChangeVersion = 2} ->
											    {ok, M};
											_ ->
											    {error, {invalid_scrp, SCRP}}
										    end;
										_ ->
										    {error, {invalid_scres, SCRes}}
									    end;
									_ ->
									    {error, {invalid_scr, SCR}}
								    end;
								_ ->
								    {error, {invalid_cr, CR}}
							    end;
							_ ->
							    {error, {invalid_ar, AR}}
						    end;
						_ ->
						    {error, {invalid_tres, Res}}
					    end;
					_ ->
					    {error, {invalid_tr, TR}}
				    end;
				_ ->
				    {error, {invalid_trans, Trans}}
			    end;
			_ ->
			    {error, {invalid_body, Body}}
		    end;
		_ ->
		    {error, {invalid_mess, Mess}}
	    end;
       (M) ->
            {error, {invalid_message, M}}
    end.

otp_5805_mg_verify_error_descriptor_msg_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
            case Mess of
		#'Message'{version     = 2,
			   mId         = _MgMid,
			   messageBody = Body} ->
		    io:format("otp_5805_mg_verify_error_descriptor_msg_fun -> ok"
			      "~n   Body:  ~p"
			      "~n", [Body]),
		    case Body of
			{messageError, ED} ->
			    case ED of
				#'ErrorDescriptor'{
				      errorCode = ?megaco_version_not_supported} ->
				    {ok, M};
				_ ->
				    {error, {invalid_ed, ED}}
			    end;
			_ ->
			    {error, {invalid_body, Body}}
		    end;
		_ ->
		    {error, {invalid_mess, Mess}}
	    end;
       (M) ->
            {error, {invalid_message, M}}
    end.

otp_5805_mg_service_change_request_ar(_Mid, Cid) ->
    Prof  = cre_serviceChangeProf("resgw", 1),
    SCP   = cre_serviceChangeParm(restart, 2, ["901 mg col boot"], Prof),
    Root  = #megaco_term_id{id = ["root"]},
    SCR   = cre_serviceChangeReq([Root], SCP),
    CMD   = cre_command(SCR),
    CR    = cre_cmdReq(CMD),
    cre_actionReq(Cid, [CR]).

otp_5805_mg_service_change_request_msg(Mid, TransId, Cid) ->
    AR    = otp_5805_mg_service_change_request_ar(Mid, Cid),
    TR    = cre_transReq(TransId, [AR]),
    Trans = cre_transaction(TR),
    Mess  = cre_message(1, Mid, cre_transactions([Trans])),
    cre_megacoMessage(Mess).

otp_5805_mg_notify_request_ar(Rid, Tid, Cid) ->
    TT      = cre_timeNotation("19990729", "22000000"),
    Ev      = cre_obsEvent("al/of", TT),
    EvsDesc = cre_obsEvsDesc(Rid, [Ev]),
    NR      = cre_notifyReq([Tid], EvsDesc),
    CMD     = cre_command(NR),
    CR      = cre_cmdReq(CMD),
    cre_actionReq(Cid, [CR]).

otp_5805_mg_notify_request_msg(V) ->
    M = 
"MEGACO/" ++ V ++ " mg
Transaction = 2 {
	Context = 1 {
		Notify = 00000000/00000000/01101101 {
			ObservedEvents = 1 {
				19990729T22000000:al/of
			}
		}
	}
}",
    list_to_binary(M).


%%
%% MGC generator stuff
%% 
otp_5805_mgc_event_sequence(text, tcp) ->
    Mid = {deviceName,"ctrl"},
    RI = [
          {port,             2944},
          {encoding_module,  megaco_pretty_text_encoder},
          {encoding_config,  []},
          {transport_module, megaco_tcp}
         ],
    ConnectVerify = fun otp_5805_mgc_verify_handle_connect/1,
    ServiceChangeReqVerify = otp_5805_mgc_verify_service_change_req_fun(Mid),
    SyntaxErrorVerify1 = fun otp_5805_mgc_verify_handle_syntax_error/1,
    SyntaxErrorVerify2 = fun otp_5805_mgc_verify_handle_syntax_error/1,
    DiscoVerify = fun otp_5805_mgc_verify_handle_disconnect/1,
    EvSeq = [
             {debug, true},
	     {megaco_trace, disable},
	     {megaco_trace, max},
             megaco_start,
             {megaco_start_user, Mid, RI, []},
             start_transport,
             listen,
             {megaco_callback, handle_connect, ConnectVerify},
	     {megaco_conn_info, all},
             {megaco_callback, handle_trans_request_sc, ServiceChangeReqVerify},
	     {megaco_update_conn_info, protocol_version, 2}, 
             {megaco_callback, handle_syntax_error, SyntaxErrorVerify1},
             {megaco_callback, handle_syntax_error, SyntaxErrorVerify2},
             {megaco_callback, handle_disconnect, DiscoVerify},
             megaco_stop_user,
             megaco_stop
            ],
    EvSeq.

otp_5805_mgc_verify_handle_connect({handle_connect, CH, 1}) -> 
    io:format("otp_5805_mgc_verify_handle_connect -> ok"
	      "~n   CH:  ~p"
	      "~n", [CH]),
    {ok, CH, ok};
otp_5805_mgc_verify_handle_connect({handle_connect, CH, V}) -> 
    io:format("otp_5805_mgc_verify_handle_connect -> unexpected version"
	      "~n   CH:  ~p"
	      "~n   V:   ~p"
	      "~n", [CH, V]),
    {error, {unexpected_version, V}, ok};
otp_5805_mgc_verify_handle_connect(Else) ->
    {error, Else, ok}.


otp_5805_mgc_verify_service_change_req_fun(Mid) ->
    fun({handle_trans_request, _, V, [AR]}) ->
	    io:format("otp_5805_mgc_verify_service_change_req_fun -> ok so far"
		      "~n   V:   ~p"
		      "~n", [V]),
            case AR of
                #'ActionRequest'{commandRequests = [CR]} ->
                    case CR of
                        #'CommandRequest'{command = Cmd} ->
                            case Cmd of
                                {serviceChangeReq, 
                                 #'ServiceChangeRequest'{terminationID = [Tid],
                                                         serviceChangeParms = Parms}} ->
                                    case Tid of
                                        #megaco_term_id{contains_wildcards = false, 
                                                        id = ["root"]} ->
                                            case Parms of
                                                #'ServiceChangeParm'{
                                                         serviceChangeMethod = restart,
							 serviceChangeVersion = 2, 
                                                         serviceChangeReason = [[$9,$0,$1|_]]} ->
                                                    Reply = 
                                                        {discard_ack, 
                                                         [otp_5805_mgc_service_change_reply_ar(Mid, 1)]},
                                                    {ok, AR, Reply};
                                                _ ->
                                                    Err = {invalid_SCP, Parms},
                                                    ED = otp_5805_err_desc(Parms),
                                                    ErrReply = 
							{discard_ack, ED},
                                                    {error, Err, ErrReply}
                                            end;
                                        _ ->
                                            Err = {invalid_termination_id, Tid},
                                            ED = otp_5805_err_desc(Tid),
                                            ErrReply = {discard_ack, ED},
                                            {error, Err, ErrReply}
                                    end;
                                _ ->
                                    Err = {invalid_command, Cmd},
                                    ED = otp_5805_err_desc(Cmd),
                                    ErrReply = {discard_ack, ED},
                                    {error, Err, ErrReply}
                            end;
                        _ ->
                            Err = {invalid_command_request, CR},
                            ED = otp_5805_err_desc(CR),
                            ErrReply = {discard_ack, ED},
                            {error, Err, ErrReply}
                    end;
                _ ->
                    Err = {invalid_action_request, AR},
                    ED = otp_5805_err_desc(AR),
                    ErrReply = {discard_ack, ED},
                    {error, Err, ErrReply}
            end;
       (Else) ->
            ED = otp_5805_err_desc(Else),
            ErrReply = {discard_ack, ED},
            {error, Else, ErrReply}
    end.

otp_5805_mgc_verify_handle_syntax_error({handle_syntax_error, CH, _, ED}) 
  when is_record(ED, 'ErrorDescriptor') -> 
    io:format("otp_5805_mgc_verify_handle_syntax_error -> ok so far"
	      "~n   CH: ~p"
	      "~n   ED:  ~p"
	      "~n", [CH, ED]),
    case ED of
	#'ErrorDescriptor'{errorCode = ?megaco_version_not_supported} ->
	    {ok, CH, reply};
	#'ErrorDescriptor'{errorCode = Code} ->
	    {error, {invalid_errorCode, Code}, ok}
    end;
otp_5805_mgc_verify_handle_syntax_error(Else) ->
    io:format("otp_5805_mgc_verify_handle_syntax_error -> unknown"
	      "~n   Else: ~p~n", [Else]),
    {error, Else, ok}.

otp_5805_mgc_verify_handle_disconnect({handle_disconnect, CH, V, _R}) -> 
    io:format("otp_5805_mgc_verify_handle_disconnect -> ok"
	      "~n   CH: ~p"
	      "~n   V:  ~p"
	      "~n   _R:  ~p"
	      "~n", [CH, V, _R]),
    {ok, CH, ok};
otp_5805_mgc_verify_handle_disconnect(Else) ->
    io:format("otp_5805_mgc_verify_handle_disconnect -> unknown"
	      "~n   Else: ~p~n", [Else]),
    {error, Else, ok}.

otp_5805_mgc_service_change_reply_ar(Mid, Cid) ->
    SCRP  = cre_serviceChangeResParm(Mid, 2),
    SCRes = cre_serviceChangeResult(SCRP),
    Root  = #megaco_term_id{id = ["root"]},
    SCR   = cre_serviceChangeReply([Root], SCRes),
    CR    = cre_cmdReply(SCR),
    cre_actionReply(Cid, [CR]).

otp_5805_mgc_notify_reply_ar(Cid, TermId) ->
    NR    = cre_notifyReply([TermId]),
    CR    = cre_cmdReply(NR),
    cre_actionReply(Cid, [CR]).


otp_5805_err_desc(T) ->
    EC = ?megaco_internal_gateway_error,
    ET = lists:flatten(io_lib:format("~w",[T])),
    #'ErrorDescriptor'{errorCode = EC, errorText = ET}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

otp_5881(suite) ->
    [];
otp_5881(Config) when list(Config) ->
    ?SKIP("deprecated by OTP-58XX"),
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        otp_5881),
    i("starting"),

    MgcNode = make_node_name(mgc),
    MgNode  = make_node_name(mg),
    d("start nodes: "
      "~n   MgcNode: ~p"
      "~n   MgNode:  ~p", 
      [MgcNode, MgNode]),
    ok = megaco_test_lib:start_nodes([MgcNode, MgNode], ?FILE, ?LINE),

    d("start the MGC simulator (generator)"),
    {ok, Mgc} = megaco_test_generator:start_link("MGC", MgcNode),

    d("create the MGC event sequence"),
    MgcEvSeq = otp_5881_mgc_event_sequence(text, tcp),

    d("start the MGC simulation"),
    megaco_test_generator:tcp(Mgc, MgcEvSeq),

    i("[MG] start"),    
    MgMid = {deviceName, "mg"},
    ReqTmr = #megaco_incr_timer{wait_for    = 3000,
                                factor      = 1, 
                                incr        = 0,
                                max_retries = 3},
    %% 5000,  %% Does not matter since we will not use this anyway...
    LongReqTmr = #megaco_incr_timer{wait_for    = 3000,
                                    factor      = 1, 
                                    incr        = 0,
                                    max_retries = 3},
    PendingTmr = 10000,
    ReplyTmr = 16000,
    MgConfig = [{request_timer,      ReqTmr}, 
                {long_request_timer, LongReqTmr}, 
                {pending_timer,      PendingTmr},
                {reply_timer,        ReplyTmr}],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    i("[MG] verify transaction-id: undefined_serial"),    
    otp_5881_verify_trans_id(Mg, undefined_serial),
    
    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    i("[MG] verify transaction-id: 1"),    
    otp_5881_verify_trans_id(Mg, 1),
    
    d("[MG] send the notify"),
    {ok, Reply} = (catch ?MG_NOTIF_RAR(Mg)),
    {1, {ok, [AR]}} = Reply,
    d("[MG] ActionReply: ~p", [AR]),

    i("[MG] verify transaction-id: 2"),    
    otp_5881_verify_trans_id(Mg, 2),
    
    d("[MGC] await the tcp reply"),
    {ok, TcpReply} = megaco_test_generator:tcp_await_reply(Mgc),
    d("[MGC] TcpReply: ~p", [TcpReply]),

    %% Tell MG to stop
    i("[MG] stop"),
    ?MG_STOP(Mg),

    %% Tell Mgc to stop
    i("[MGC] stop generator"),
    megaco_test_generator:stop(Mgc),

    i("done", []),
    ok.

otp_5881_verify_trans_id(Mg, Expected) ->
    case ?MG_CONN_INFO(Mg, trans_id) of
	Expected -> 
	    ok;
	ErroneousValue ->
	    throw({unexpected_transaction_id_value, ErroneousValue, Expected})
    end.
    

otp_5881_mgc_event_sequence(text, tcp) ->
    DecodeFun = otp_5881_decode_msg_fun(megaco_pretty_text_encoder, []),
    EncodeFun = otp_5881_encode_msg_fun(megaco_pretty_text_encoder, []),
    ServiceChangeVerifyFun = otp_5881_verify_service_change_req_msg_fun(),
    Mid = {deviceName,"ctrl"},
    ServiceChangeReply = otp_5881_service_change_reply_msg(Mid, 1, 0),
    NotifyReqVerifyFun = otp_5881_verify_notify_request_fun(),
    TermId = #megaco_term_id{id = ["00000000","00000000","01101101"]},
    NotifyReply = otp_5881_notify_reply_msg(Mid, 2, 0, TermId),
    %% Pending = otp_5881_pending_msg(Mid,2),
    MgcEvSeq = [{debug,  true},
		{decode, DecodeFun},
		{encode, EncodeFun},
		{listen, 2944},
		{expect_accept, any},
		{expect_receive, "service-change-request", {ServiceChangeVerifyFun, 10000}}, 
		{send, "service-change-reply", ServiceChangeReply}, 
		{expect_receive, "notify-request", {NotifyReqVerifyFun, 10000}},
  		{send, "notify-reply", NotifyReply},
		{sleep, 2000}
	       ],
    MgcEvSeq.

otp_5881_service_change_reply_msg(Mid, TransId, Cid) ->
    SCRP  = #'ServiceChangeResParm'{serviceChangeMgcId = Mid},
    SCRPs = {serviceChangeResParms,SCRP},
    Root  = #megaco_term_id{id = ["root"]},
    SCR   = #'ServiceChangeReply'{terminationID       = [Root],
				  serviceChangeResult = SCRPs},
    CR    = {serviceChangeReply, SCR},
    otp_5881_msg(Mid, TransId, CR, Cid).

otp_5881_notify_reply_msg(Mid, TransId, Cid, TermId) ->
    NR  = #'NotifyReply'{terminationID = [TermId]},
    CR  = {notifyReply, NR},
    otp_5881_msg(Mid, TransId, CR, Cid).

otp_5881_msg(Mid, TransId, CR, Cid) ->
    AR  = #'ActionReply'{contextId    = Cid,
			 commandReply = [CR]},
    ARs  = {actionReplies, [AR]},
    TR   = #'TransactionReply'{transactionId     = TransId,
			       transactionResult = ARs},
    Body = {transactions, [{transactionReply, TR}]},
    Mess = #'Message'{version     = 1,
		      mId         = Mid,
		      messageBody = Body},
    #'MegacoMessage'{mess = Mess}.


otp_5881_pending_msg(Mid, TransId) ->
    TP   = #'TransactionPending'{transactionId = TransId},
    Body = {transactions, [{transactionPending, TP}]},
    Mess = #'Message'{version     = 1,
		      mId         = Mid,
		      messageBody = Body},
    #'MegacoMessage'{mess = Mess}.


otp_5881_encode_msg_fun(Mod, Conf) ->
    fun(M) -> 
	    Mod:encode_message(Conf, M) 
    end.
otp_5881_encode_msg_fun(Mod, Conf, Ver) ->
    fun(M) -> 
	    Mod:encode_message(Conf, Ver, M) 
    end.

otp_5881_decode_msg_fun(Mod, Conf) ->
    fun(M) -> 
	    Mod:decode_message(Conf, M) 
    end.
otp_5881_decode_msg_fun(Mod, Conf, Ver) ->
    fun(M) -> 
	    Mod:decode_message(Conf, Ver, M) 
    end.

otp_5881_verify_msg_fun() ->
    fun(M) -> {ok, M} end.

otp_5881_verify_service_change_req_msg_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
	    #'Message'{version     = _V,
		       mId         = _Mid,
		       messageBody = Body} = Mess,
	    {transactions, [Trans]} = Body,
	    {transactionRequest, TR} = Trans,
	    #'TransactionRequest'{transactionId = _Tid,
				  actions = [AR]} = TR,
	    #'ActionRequest'{contextId = _Cid,
			     contextRequest = _CtxReq,
			     contextAttrAuditReq = _CtxAar,
			     commandRequests = [CR]} = AR,
	    #'CommandRequest'{command = Cmd,
			      optional = _Opt,
			      wildcardReturn = _WR} = CR,
	    {serviceChangeReq, SCR} = Cmd,
	    #'ServiceChangeRequest'{terminationID = _TermID,
				    serviceChangeParms = SCP} = SCR,
	    #'ServiceChangeParm'{serviceChangeMethod = restart,
				 serviceChangeReason = [[$9,$0,$1|_]]} = SCP,
	    {ok, M};
       (M) ->
	    {error, {invalid_message, M}}
    end.

otp_5881_verify_notify_request_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
	    #'Message'{messageBody = Body} = Mess,
	    {transactions, [Trans]} = Body,
	    {transactionRequest, TR} = Trans,
	    #'TransactionRequest'{actions = [AR]} = TR,
	    #'ActionRequest'{commandRequests = [CR1,CR2]} = AR,
	    #'CommandRequest'{command = Cmd1} = CR1,
	    {notifyReq, NR1} = Cmd1,
	    #'NotifyRequest'{observedEventsDescriptor = OED1} = NR1,
	    #'ObservedEventsDescriptor'{observedEventLst = [OE1]} = OED1,
	    #'ObservedEvent'{eventName = "al/of"} = OE1,
	    #'CommandRequest'{command = Cmd2} = CR2,
	    {notifyReq, NR2} = Cmd2,
	    #'NotifyRequest'{observedEventsDescriptor = OED2} = NR2,
	    #'ObservedEventsDescriptor'{observedEventLst = [OE2]} = OED2,
	    #'ObservedEvent'{eventName = "al/of"} = OE2,
	    {ok, M};
       (M) ->
	    {error, {invalid_message, M}}
    end.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

otp_5887(suite) ->
    [];
otp_5887(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        otp_5887),
    i("starting"),

    MgcNode = make_node_name(mgc),
    MgNode  = make_node_name(mg),
    d("start nodes: "
      "~n   MgcNode: ~p"
      "~n   MgNode:  ~p", 
      [MgcNode, MgNode]),
    ok = megaco_test_lib:start_nodes([MgcNode, MgNode], ?FILE, ?LINE),

    d("start the MGC simulator (generator)"),
    {ok, Mgc} = megaco_test_generator:start_link("MGC", MgcNode),

    d("create the MGC event sequence"),
    MgcEvSeq = otp_5887_mgc_event_sequence(text, tcp),

    d("start the MGC simulation"),
    megaco_test_generator:tcp(Mgc, MgcEvSeq),

    i("[MG] start"),    
    MgMid = {deviceName, "mg"},
    ReqTmr = #megaco_incr_timer{wait_for    = 3000,
                                factor      = 1, 
                                incr        = 0,
                                max_retries = 3},
    %% 5000,  %% Does not matter since we will not use this anyway...
    LongReqTmr = #megaco_incr_timer{wait_for    = 3000,
                                    factor      = 1, 
                                    incr        = 0,
                                    max_retries = 3},
    PendingTmr = 10000,
    ReplyTmr = 16000,
    MgConfig = [{request_timer,      ReqTmr}, 
                {long_request_timer, LongReqTmr}, 
                {pending_timer,      PendingTmr},
                {reply_timer,        ReplyTmr}],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    i("[MG] conn info: ~n~p", [?MG_CONN_INFO(Mg, all)]), 

    i("[MG] verify conn transaction-id: 1"),    
    otp_5887_verify_conn_trans_id(Mg, 1),

    i("[MG] user info: ~n~p", [?MG_USER_INFO(Mg, all)]), 

    i("[MG] verify user transaction-id: undefined_serial"),    
    otp_5887_verify_user_trans_id(Mg, undefined_serial),
    
    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    i("[MG] conn info: ~n~p", [?MG_CONN_INFO(Mg, all)]), 

    i("[MG] verify conn transaction-id: 2"),    
    otp_5887_verify_conn_trans_id(Mg, 2),

    i("[MG] user info: ~n~p", [?MG_USER_INFO(Mg, all)]), 

    i("[MG] verify user transaction-id: 1"),    
    otp_5887_verify_user_trans_id(Mg, 1),
    
    d("[MG] send the notify"),
    {ok, Reply} = (catch ?MG_NOTIF_RAR(Mg)),
    {1, {ok, [AR]}} = Reply,
    d("[MG] ActionReply: ~p", [AR]),

    i("[MG] conn info: ~n~p", [?MG_CONN_INFO(Mg, all)]), 

    i("[MG] verify conn transaction-id: 3"),    
    otp_5887_verify_conn_trans_id(Mg, 3),

    i("[MG] user info: ~n~p", [?MG_USER_INFO(Mg, all)]), 

    i("[MG] verify user transaction-id: 2"),    
    otp_5887_verify_user_trans_id(Mg, 2),
    
    d("[MGC] await the tcp reply"),
    {ok, TcpReply} = megaco_test_generator:tcp_await_reply(Mgc),
    d("[MGC] TcpReply: ~p", [TcpReply]),

    %% Tell MG to stop
    i("[MG] stop"),
    ?MG_STOP(Mg),

    %% Tell Mgc to stop
    i("[MGC] stop generator"),
    megaco_test_generator:stop(Mgc),

    i("done", []),
    ok.


otp_5887_verify_conn_trans_id(Mg, Expected) ->
    F = fun() -> (catch ?MG_CONN_INFO(Mg, trans_id)) end,
    otp_5887_verify_trans_id(F, Expected).

otp_5887_verify_user_trans_id(Mg, Expected) ->
    F = fun() -> (catch ?MG_USER_INFO(Mg, trans_id)) end,
    otp_5887_verify_trans_id(F, Expected).

otp_5887_verify_trans_id(F, Expected) ->
    case F() of
	Expected -> 
	    ok;
	ErroneousValue ->
	    throw({unexpected_transaction_id_value, ErroneousValue, Expected})
    end.
    

otp_5887_mgc_event_sequence(text, tcp) ->
    DecodeFun = otp_5887_decode_msg_fun(megaco_pretty_text_encoder, []),
    EncodeFun = otp_5887_encode_msg_fun(megaco_pretty_text_encoder, []),
    ServiceChangeVerifyFun = otp_5887_verify_service_change_req_msg_fun(),
    Mid = {deviceName,"ctrl"},
    ServiceChangeReply = otp_5887_service_change_reply_msg(Mid, 1, 0),
    NotifyReqVerifyFun = otp_5887_verify_notify_request_fun(),
    TermId = #megaco_term_id{id = ["00000000","00000000","01101101"]},
    NotifyReply = otp_5887_notify_reply_msg(Mid, 2, 0, TermId),
    MgcEvSeq = [{debug,  true},
		{decode, DecodeFun},
		{encode, EncodeFun},
		{listen, 2944},
		{expect_accept, any},
		{expect_receive, "service-change-request", {ServiceChangeVerifyFun, 10000}}, 
		{send, "service-change-reply", ServiceChangeReply}, 
		{expect_receive, "notify-request", {NotifyReqVerifyFun, 10000}},
  		{send, "notify-reply", NotifyReply},
		{sleep, 2000}
	       ],
    MgcEvSeq.

otp_5887_service_change_reply_msg(Mid, TransId, Cid) ->
    SCRP  = #'ServiceChangeResParm'{serviceChangeMgcId = Mid},
    SCRPs = {serviceChangeResParms,SCRP},
    Root  = #megaco_term_id{id = ["root"]},
    SCR   = #'ServiceChangeReply'{terminationID       = [Root],
				  serviceChangeResult = SCRPs},
    CR    = {serviceChangeReply, SCR},
    otp_5887_msg(Mid, TransId, CR, Cid).

otp_5887_notify_reply_msg(Mid, TransId, Cid, TermId) ->
    NR  = #'NotifyReply'{terminationID = [TermId]},
    CR  = {notifyReply, NR},
    otp_5887_msg(Mid, TransId, CR, Cid).

otp_5887_msg(Mid, TransId, CR, Cid) ->
    AR  = #'ActionReply'{contextId    = Cid,
			 commandReply = [CR]},
    ARs  = {actionReplies, [AR]},
    TR   = #'TransactionReply'{transactionId     = TransId,
			       transactionResult = ARs},
    Body = {transactions, [{transactionReply, TR}]},
    Mess = #'Message'{version     = 1,
		      mId         = Mid,
		      messageBody = Body},
    #'MegacoMessage'{mess = Mess}.


otp_5887_pending_msg(Mid, TransId) ->
    TP   = #'TransactionPending'{transactionId = TransId},
    Body = {transactions, [{transactionPending, TP}]},
    Mess = #'Message'{version     = 1,
		      mId         = Mid,
		      messageBody = Body},
    #'MegacoMessage'{mess = Mess}.


otp_5887_encode_msg_fun(Mod, Conf) ->
    fun(M) -> 
	    Mod:encode_message(Conf, M) 
    end.
otp_5887_encode_msg_fun(Mod, Conf, Ver) ->
    fun(M) -> 
	    Mod:encode_message(Conf, Ver, M) 
    end.

otp_5887_decode_msg_fun(Mod, Conf) ->
    fun(M) -> 
	    Mod:decode_message(Conf, M) 
    end.
otp_5887_decode_msg_fun(Mod, Conf, Ver) ->
    fun(M) -> 
	    Mod:decode_message(Conf, Ver, M) 
    end.

otp_5887_verify_msg_fun() ->
    fun(M) -> {ok, M} end.

otp_5887_verify_service_change_req_msg_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
	    #'Message'{version     = _V,
		       mId         = _Mid,
		       messageBody = Body} = Mess,
	    {transactions, [Trans]} = Body,
	    {transactionRequest, TR} = Trans,
	    #'TransactionRequest'{transactionId = _Tid,
				  actions = [AR]} = TR,
	    #'ActionRequest'{contextId = _Cid,
			     contextRequest = _CtxReq,
			     contextAttrAuditReq = _CtxAar,
			     commandRequests = [CR]} = AR,
	    #'CommandRequest'{command = Cmd,
			      optional = _Opt,
			      wildcardReturn = _WR} = CR,
	    {serviceChangeReq, SCR} = Cmd,
	    #'ServiceChangeRequest'{terminationID = _TermID,
				    serviceChangeParms = SCP} = SCR,
	    #'ServiceChangeParm'{serviceChangeMethod = restart,
				 serviceChangeReason = [[$9,$0,$1|_]]} = SCP,
	    {ok, M};
       (M) ->
	    {error, {invalid_message, M}}
    end.

otp_5887_verify_notify_request_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
	    #'Message'{messageBody = Body} = Mess,
	    {transactions, [Trans]} = Body,
	    {transactionRequest, TR} = Trans,
	    #'TransactionRequest'{actions = [AR]} = TR,
	    #'ActionRequest'{commandRequests = [CR1,CR2]} = AR,
	    #'CommandRequest'{command = Cmd1} = CR1,
	    {notifyReq, NR1} = Cmd1,
	    #'NotifyRequest'{observedEventsDescriptor = OED1} = NR1,
	    #'ObservedEventsDescriptor'{observedEventLst = [OE1]} = OED1,
	    #'ObservedEvent'{eventName = "al/of"} = OE1,
	    #'CommandRequest'{command = Cmd2} = CR2,
	    {notifyReq, NR2} = Cmd2,
	    #'NotifyRequest'{observedEventsDescriptor = OED2} = NR2,
	    #'ObservedEventsDescriptor'{observedEventLst = [OE2]} = OED2,
	    #'ObservedEvent'{eventName = "al/of"} = OE2,
	    {ok, M};
       (M) ->
	    {error, {invalid_message, M}}
    end.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

cre_serviceChangeParm(M, V, R, P) ->
    #'ServiceChangeParm'{serviceChangeMethod  = M, 
			 serviceChangeVersion = V,
                         serviceChangeReason  = R, 
                         serviceChangeProfile = P}.

cre_serviceChangeReq(Tid, Parms) ->
    #'ServiceChangeRequest'{terminationID      = Tid, 
                            serviceChangeParms = Parms}.

cre_timeNotation(D,T) ->
    #'TimeNotation'{date = D, time = T}.

cre_obsEvent(Name, Not) ->
    #'ObservedEvent'{eventName    = Name, 
                     timeNotation = Not}.

cre_obsEvsDesc(Id, EvList) ->
    #'ObservedEventsDescriptor'{requestId        = Id, 
                                observedEventLst = EvList}.

cre_notifyReq(Tid, EvsDesc) ->
    #'NotifyRequest'{terminationID            = Tid, 
                     observedEventsDescriptor = EvsDesc}.

cre_command(R) when record(R, 'NotifyRequest') ->
    {notifyReq, R};
cre_command(R) when record(R, 'ServiceChangeRequest') ->
    {serviceChangeReq, R}.

cre_cmdReq(Cmd) ->
    #'CommandRequest'{command = Cmd}.

cre_actionReq(CtxId, CmdReqs) when list(CmdReqs) ->
    #'ActionRequest'{contextId       = CtxId,
                     commandRequests = CmdReqs}.

cre_transReq(TransId, ARs) when list(ARs) ->
    #'TransactionRequest'{transactionId = TransId,
			  actions       = ARs}.

%% --

cre_serviceChangeResParm(Mid, V) ->
    #'ServiceChangeResParm'{serviceChangeMgcId   = Mid, 
			    serviceChangeVersion = V}.

cre_serviceChangeResult(SCRP) when record(SCRP, 'ServiceChangeResParm') ->
    {serviceChangeResParms, SCRP};
cre_serviceChangeResult(ED) when record(ED, 'ErrorDescriptor') ->
    {errorDescriptor, ED}.

cre_serviceChangeReply(Tid, Res) ->
    #'ServiceChangeReply'{terminationID       = Tid, 
                          serviceChangeResult = Res}.

cre_cmdReply(R) when record(R, 'NotifyReply') ->
    {notifyReply, R};
cre_cmdReply(R) when record(R, 'ServiceChangeReply') ->
    {serviceChangeReply, R}.

cre_notifyReply(Tid) ->
    #'NotifyReply'{terminationID = Tid}.

cre_actionReply(CtxId, CmdRep) ->
    #'ActionReply'{contextId    = CtxId,
                   commandReply = CmdRep}.

cre_serviceChangeProf(Name, Ver) when list(Name), integer(Ver) ->
    #'ServiceChangeProfile'{profileName = Name, 
                            version     = Ver}.

cre_transaction(Trans) when record(Trans, 'TransactionRequest') ->
    {transactionRequest, Trans};
cre_transaction(Trans) when record(Trans, 'TransactionPending') ->
    {transactionPending, Trans};
cre_transaction(Trans) when record(Trans, 'TransactionReply') ->
    {transactionReply, Trans};
cre_transaction(Trans) when record(Trans, 'TransactionAck') ->
    {transactionResponseAck, Trans}.

cre_transactions(Trans) when list(Trans) ->
    {transactions, Trans}.

cre_message(Version, Mid, Body) ->
    #'Message'{version     = Version,
               mId         = Mid,
               messageBody = Body}.

cre_megacoMessage(Mess) ->
    #'MegacoMessage'{mess = Mess}.

service_change_request() ->
    Parm = #'ServiceChangeParm'{serviceChangeMethod = restart,
				serviceChangeReason = [?megaco_cold_boot]},
    SCR = #'ServiceChangeRequest'{terminationID = [?megaco_root_termination_id],
				  serviceChangeParms = Parm},
    CR = #'CommandRequest'{command = {serviceChangeReq, SCR}},
    #'ActionRequest'{contextId = ?megaco_null_context_id,
		     commandRequests = [CR]}.

service_change_reply(MgcMid) ->
    Res = {serviceChangeResParms, #'ServiceChangeResParm'{serviceChangeMgcId = MgcMid}},
    SCR = #'ServiceChangeReply'{terminationID = [?megaco_root_termination_id],
				serviceChangeResult = Res},
    #'ActionReply'{contextId = ?megaco_null_context_id,
		   commandReply = [{serviceChangeReply, SCR}]}.

local_ip_address() ->
    {ok, Hostname} = inet:gethostname(),
    {ok, {A1, A2, A3, A4}} = inet:getaddr(Hostname, inet),
    {A1, A2, A3, A4}.

ipv4_mid() ->
    ipv4_mid(asn1_NOVALUE).

ipv4_mid(Port) ->
    IpAddr = local_ip_address(),
    Ip = tuple_to_list(IpAddr),
    {ip4Address, #'IP4Address'{address = Ip, portNumber = Port}}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% -------------------------------------------------------------------------------
%%% Megaco user callback interface
%%% -------------------------------------------------------------------------------

handle_connect(ConnHandle, ProtocolVersion, Pid) ->
    Pid ! {handle_connect, {ConnHandle, ProtocolVersion}},
    ok.

handle_disconnect(_, _, {user_disconnect, test_complete}, _) ->
    ok;
handle_disconnect(ConnHandle, ProtocolVersion, Reason, Pid) ->
    Pid ! {handle_disconnect, {ConnHandle, ProtocolVersion, Reason}},
    ok.

handle_syntax_error(ConnHandle, ProtocolVersion, ErrorDescriptor, Pid) ->
    Pid ! {handle_syntax_error,{ConnHandle, ProtocolVersion, ErrorDescriptor}},
    reply.
         
handle_message_error(ConnHandle, ProtocolVersion, ErrorDescriptor, Pid) ->
    Pid ! {handle_message_error,{ConnHandle, ProtocolVersion, ErrorDescriptor}},
    reply.

handle_trans_request(ConnHandle, ProtocolVersion, ActionRequests, Pid) ->
    Pid ! {handle_trans_request,{ConnHandle, ProtocolVersion, ActionRequests}},
    ED = #'ErrorDescriptor'{errorCode = ?megaco_not_implemented,
			    errorText = "not implemented yet"},
    {discard_ack, ED}.

handle_trans_long_request(ConnHandle, ProtocolVersion, Data, Pid) ->
    Pid ! {handle_trans_long_request,{ConnHandle, ProtocolVersion, Data}},
    ED = #'ErrorDescriptor'{errorCode = ?megaco_not_implemented,
			    errorText = "not implemented yet"},
    {discard_ack, ED}.

handle_trans_reply(ConnHandle, ProtocolVersion, ActualReply, Data, Pid) ->
    Pid ! {handle_trans_reply,{ConnHandle, ProtocolVersion, ActualReply, Data}},
    ok.

handle_trans_ack(ConnHandle, ProtocolVersion, Status, Data, Pid) ->
    Pid ! {handle_trans_ack,{ConnHandle, ProtocolVersion, Status, Data}},
    ok.

handle_unexpected_trans(ReceiveHandle, ProtocolVersion, Trans, Pid) ->
    Pid ! {handle_unexpected_trans, 
	   {ReceiveHandle, ProtocolVersion, Trans, Pid}},
    ok.

handle_trans_request_abort(ReceiveHandle, ProtocolVersion, TransNo, HandlerPid, Pid) ->
    Pid ! {handle_trans_request_abort, 
	   {ReceiveHandle, ProtocolVersion, TransNo, HandlerPid}},
    ok.





%%% -------------------------------------------------------------------------------
%%% Megaco transport module interface
%%% -------------------------------------------------------------------------------

send_message(Pid, Data) ->
    Pid ! {send_message, Data},
    ok.

% block(Pid) ->
%     Pid ! {block, dummy},
%     ok.

unblock(Pid) ->
    Pid ! {unblock, dummy},
    ok.

% close(Pid) ->
%     Pid ! {close, dummy},
%     ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

make_node_name(Name) ->
    case string:tokens(atom_to_list(node()), [$@]) of
	[_,Host] ->
	    list_to_atom(lists:concat([atom_to_list(Name) ++ "@" ++ Host]));
	_ ->
	    exit("Test node must be started with '-sname'")
    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

user_info(Mid, Key) ->
    case (catch megaco:user_info(Mid, Key)) of
	{'EXIT', _} = Error ->
	    ?ERROR(Error);
	Val ->
	    ?LOG("Ok, ~p~n", [Val]),
	    Val
    end.


stop_user(Mid) ->
    case (catch megaco:stop_user(Mid)) of
	{'EXIT', _} = Error ->
	    ?ERROR(Error);
	Val ->
	    ?LOG("Ok, ~p~n", [Val]),
	    Val
    end.

connections() ->
    system_info(connections).

connections(Conns0) ->
    Conns1 = lists:sort(Conns0),
    case lists:sort(connections()) of
	Conns1 ->
	    ?LOG("Ok, ~p~n", [Conns1]),
	    Conns1;
	Conns2 ->
	    ?ERROR({Conns1, Conns2}),
	    Conns2
    end.

system_info(Key) ->
    megaco:system_info(Key).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sleep(X) -> receive after X -> ok end.

% error_msg(F,A) -> error_logger:error_msg(F ++ "~n",A).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

i(F) ->
    i(F, []).

i(F, A) ->
    print(info, get(verbosity), now(), get(tc), "INF", F, A).


d(F) ->
    d(F, []).

d(F, A) ->
    print(debug, get(verbosity), now(), get(tc), "DBG", F, A).


printable(_, debug)   -> true;
printable(info, info) -> true;
printable(_,_)        -> false.

print(Severity, Verbosity, Ts, Tc, P, F, A) ->
    print(printable(Severity,Verbosity), Ts, Tc, P, F, A).

print(true, Ts, Tc, P, F, A) ->
    io:format("*** [~s] ~s ~p ~s:~w ***"
	      "~n   " ++ F ++ "~n", 
	      [format_timestamp(Ts), P, self(), get(sname), Tc | A]);
print(_, _, _, _, _, _) ->
    ok.

format_timestamp({_N1, _N2, N3} = Now) ->
    {Date, Time}   = calendar:now_to_datetime(Now),
    {YYYY,MM,DD}   = Date,
    {Hour,Min,Sec} = Time,
    FormatDate = 
        io_lib:format("~.4w:~.2.0w:~.2.0w ~.2.0w:~.2.0w:~.2.0w 4~w",
                      [YYYY,MM,DD,Hour,Min,Sec,round(N3/1000)]),  
    lists:flatten(FormatDate).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

random_init() ->
    {A,B,C} = now(),
    random:seed(A,B,C).

random() ->
    10 * random:uniform(50).

