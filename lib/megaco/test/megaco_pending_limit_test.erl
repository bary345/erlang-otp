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
%% Purpose: Verify the application specifics of the Megaco application
%%          Testing the xxxOriginatingPendingLimit property of the 
%%          root package
%%----------------------------------------------------------------------
-module(megaco_pending_limit_test).

-export([t/0, t/1]).
-export([init_per_testcase/2, fin_per_testcase/2]).
-export([all/1,

	 sent/1,
	 sent_timer_late_reply/1,
	 sent_timer_exceeded/1,
	 sent_timer_exceeded_long/1,
	 sent_resend_late_reply/1,
	 sent_resend_exceeded/1,
	 sent_resend_exceeded_long/1,

	 recv/1,
	 recv_limit_exceeded1/1,
	 recv_limit_exceeded2/1,

	 tickets/1,
	 otp_4956/1,
	 otp_5310/1
	
	]).

-include("megaco_test_lib.hrl").
-include_lib("megaco/include/megaco.hrl").
-include_lib("megaco/include/megaco_message_v1.hrl").

-define(TEST_VERBOSITY, debug).
-define(MGC_VERBOSITY,  debug).
-define(MG_VERBOSITY,   debug).

-define(VERSION, 1).

-define(A4444, ["11111111", "00000000", "00000000"]).
-define(A4445, ["11111111", "00000000", "11111111"]).
-define(A5555, ["11111111", "11111111", "00000000"]).
-define(A5556, ["11111111", "11111111", "11111111"]).

-define(MGC_START(Pid, Mid, ET, Verb), 
	megaco_test_mgc:start(Pid, Mid, ET, Verb)).
-define(MGC_STOP(Pid), megaco_test_mgc:stop(Pid)).
-define(MGC_GET_STATS(Pid, No), megaco_test_mgc:get_stats(Pid, No)).
-define(MGC_RESET_STATS(Pid),   megaco_test_mgc:reset_stats(Pid)).
-define(MGC_REQ_IGNORE(Pid),    megaco_test_mgc:request_ignore(Pid)).
-define(MGC_REQ_PIGNORE(Pid),   megaco_test_mgc:request_pending_ignore(Pid)).
-define(MGC_REQ_DISC(Pid,To),   megaco_test_mgc:request_discard(Pid,To)).
-define(MGC_REQ_PEND(Pid,To),   megaco_test_mgc:request_pending(Pid,To)).
-define(MGC_REQ_HAND(Pid, To),  megaco_test_mgc:request_handle(Pid, To)).
-define(MGC_REQ_HANDS(Pid),     megaco_test_mgc:request_handle_sloppy(Pid)).
-define(MGC_UPDATE_UI(Pid,Tag,Val), 
	megaco_test_mgc:update_user_info(Pid,Tag,Val)).
-define(MGC_UPDATE_CI(Pid,Tag,Val), 
	megaco_test_mgc:update_conn_info(Pid,Tag,Val)).
-define(MGC_USER_INFO(Pid,Tag), megaco_test_mgc:user_info(Pid,Tag)).
-define(MGC_CONN_INFO(Pid,Tag), megaco_test_mgc:conn_info(Pid,Tag)).
-define(MGC_ACK_INFO(Pid,To),   megaco_test_mgc:ack_info(Pid,To)).
-define(MGC_ABORT_INFO(Pid,To), megaco_test_mgc:abort_info(Pid,To)).
-define(MGC_DISCO(Pid,Reason),  megaco_test_mgc:disconnect(Pid,Reason)).

-define(MG_START(Pid, Mid, Enc, Transp, Conf, Verb), 
	megaco_test_mg:start(Pid, Mid, Enc, Transp, Conf, Verb)).
-define(MG_STOP(Pid), megaco_test_mg:stop(Pid)).
-define(MG_GET_STATS(Pid, No), megaco_test_mg:get_stats(Pid, No)).
-define(MG_RESET_STATS(Pid), megaco_test_mg:reset_stats(Pid)).
-define(MG_SERV_CHANGE(Pid), megaco_test_mg:service_change(Pid)).
-define(MG_NOTIF_RAR(Pid), megaco_test_mg:notify_request_and_reply(Pid)).
-define(MG_NOTIF_REQ(Pid), megaco_test_mg:notify_request(Pid)).
-define(MG_NOTIF_AR(Pid),  megaco_test_mg:await_notify_reply(Pid)).
-define(MG_CANCEL(Pid,R),  megaco_test_mg:cancel_request(Pid,R)).
-define(MG_APPLY_LOAD(Pid,CntStart), megaco_test_mg:apply_load(Pid,CntStart)).
-define(MG_UPDATE_UI(Pid,Tag,Val), 
	megaco_test_mg:update_user_info(Pid,Tag,Val)).
-define(MG_UPDATE_CI(Pid,Tag,Val), 
	megaco_test_mg:update_conn_info(Pid,Tag,Val)).
-define(MG_USER_INFO(Pid,Tag), megaco_test_mg:user_info(Pid,Tag)).
-define(MG_CONN_INFO(Pid,Tag), megaco_test_mg:conn_info(Pid,Tag)).
-define(MG_GRP_REQ(Pid,N),     megaco_test_mg:group_requests(Pid,N)).
-define(MG_ECC(Pid, M, T, F),  megaco_test_mg:enable_test_code(Pid,M,T,F)).

t()     -> megaco_test_lib:t(?MODULE).
t(Case) -> megaco_test_lib:t({?MODULE, Case}).


%% Test server callbacks
init_per_testcase(Case, Config) ->
    process_flag(trap_exit, true),
    megaco_test_lib:init_per_testcase(Case, Config).

fin_per_testcase(Case, Config) ->
    process_flag(trap_exit, false),
    megaco_test_lib:fin_per_testcase(Case, Config).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

all(suite) ->
    [
     sent,
     recv,
     
     %% Tickets last 
     tickets
    ].

sent(suite) ->
    [
     sent_timer_late_reply,
     sent_timer_exceeded,
     sent_timer_exceeded_long,
     sent_resend_late_reply,
     sent_resend_exceeded,
     sent_resend_exceeded_long
     
    ].

recv(suite) ->
    [
     recv_limit_exceeded1,
     recv_limit_exceeded2
    ].

tickets(suite) ->
    [
     otp_4956,
     otp_5310
    ].


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                                                                   %%%
%%%                    Sent pending test cases                        %%%
%%%                                                                   %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sent_timer_late_reply(suite) ->
    [];
sent_timer_late_reply(doc) ->
    "...";
sent_timer_late_reply(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        sent_timer_late_reply),
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
    MgConfig = [],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    d("MG user info: ~p", [?MG_USER_INFO(Mg, all)]),

    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    d("MG conn info: ~p", [?MG_CONN_INFO(Mg, all)]),

    d("[MGC] update connection info pending timer"),
    PendingTimer = #megaco_incr_timer{wait_for = timer:seconds(5),
				      factor   = 1},
    ?MGC_UPDATE_CI(Mgc, pending_timer, PendingTimer),

    d("[MGC] update connection info sent pending limit"),
    PendingLimit = 5,
    ?MGC_UPDATE_CI(Mgc, sent_pending_limit, PendingLimit),

    d("[MGC] late reply to requests "
      "(simulate that the request takes a long time)"),
    ?MGC_REQ_DISC(Mgc, 11000),

    d("[MG] send the notify"),
    {ok, Reply} = ?MG_NOTIF_RAR(Mg),
    d("[MG] Reply: ~p", [Reply]),
    {_Version, {ok, [_ActionReply]}} = Reply,

    %% Tell MG to stop
    i("[MG] stop"),
    ?MG_STOP(Mg),

    %% Tell Mgc to stop
    i("[MGC] stop"),
    ?MGC_STOP(Mgc),

    i("done", []),
    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sent_timer_exceeded(suite) ->
    [];
sent_timer_exceeded(doc) ->
    "...";
sent_timer_exceeded(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        sent_timer_exceeded),
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
    MgConfig = [],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    d("MG user info: ~p", [?MG_USER_INFO(Mg, all)]),

    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    d("MG conn info: ~p", [?MG_CONN_INFO(Mg, all)]),

    d("[MGC] update connection info pending timer"),
    PendingTimer = #megaco_incr_timer{wait_for = timer:seconds(5),
				      factor   = 1},
    ?MGC_UPDATE_CI(Mgc, pending_timer, PendingTimer),

    d("[MGC] update connection info sent pending limit"),
    PendingLimit = 5,
    ?MGC_UPDATE_CI(Mgc, sent_pending_limit, PendingLimit),

    d("[MGC] no reply to requests "
      "(simulate that the request takes a __long__ time)"),
    ?MGC_REQ_IGNORE(Mgc),

    d("[MG] send the notify"),
    ED = ?MG_NOTIF_RAR(Mg),
    d("[MG] ED: ~p", [ED]),
    ErrorCode = ?megaco_number_of_transactionpending_exceeded,
    #'ErrorDescriptor'{errorCode = ErrorCode} = ED,

    %% Tell MG to stop
    i("[MG] stop"),
    ?MG_STOP(Mg),

    %% Tell Mgc to stop
    i("[MGC] stop"),
    ?MGC_STOP(Mgc),

    i("done", []),
    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sent_timer_exceeded_long(suite) ->
    [];
sent_timer_exceeded_long(doc) ->
    "...";
sent_timer_exceeded_long(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        sent_timer_exceeded_long),
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
    MgConfig = [],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    d("MG user info: ~p", [?MG_USER_INFO(Mg, all)]),

    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    d("MG conn info: ~p", [?MG_CONN_INFO(Mg, all)]),

    d("[MGC] update connection info pending timer"),
    PendingTimer = #megaco_incr_timer{wait_for = timer:seconds(5),
				      factor   = 1},
    ?MGC_UPDATE_CI(Mgc, pending_timer, PendingTimer),

    d("[MGC] update connection info sent pending limit"),
    PendingLimit = 5,
    ?MGC_UPDATE_CI(Mgc, sent_pending_limit, PendingLimit),

    d("[MGC] long request with no reply ~n"
      "   (simulate that we know that this will "
      "take a while, but takes even longer...)"),
    ?MGC_REQ_PIGNORE(Mgc),

    d("[MG] send the notify"),
    ED = ?MG_NOTIF_RAR(Mg),
    d("[MG] ED: ~p", [ED]),
    ErrorCode = ?megaco_number_of_transactionpending_exceeded,
    #'ErrorDescriptor'{errorCode = ErrorCode} = ED,

    %% Tell MG to stop
    i("[MG] stop"),
    ?MG_STOP(Mg),

    %% Tell Mgc to stop
    i("[MGC] stop"),
    ?MGC_STOP(Mgc),

    i("done", []),
    ok.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% This test case can only be run with the stack compiled with
%% the MEGACO_TEST_CODE flag. Therefor there is no point in 
%% including this test case in the usual test suite
-ifdef(MEGACO_TEST_CODE).
sent_resend_late_reply(suite) ->
    [];
sent_resend_late_reply(doc) ->
    "...";
sent_resend_late_reply(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        sent_resend_late_reply),
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
    MgConfig = [],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    d("MG user info: ~p", [?MG_USER_INFO(Mg, all)]),

    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    d("MG conn info: ~p", [?MG_CONN_INFO(Mg, all)]),

    d("[MGC] update connection info pending timer"),
    PendingTimer = infinity,
    %%     PendingTimer = #megaco_incr_timer{wait_for = timer:seconds(5),
    %% 				      factor    = 1},
    ?MGC_UPDATE_CI(Mgc, pending_timer, PendingTimer),

    d("[MGC] update connection info sent pending limit"),
    PendingLimit = 5,
    ?MGC_UPDATE_CI(Mgc, sent_pending_limit, PendingLimit),

    d("[MG] update connection info request timer"),
    RequestTimer = #megaco_incr_timer{wait_for = timer:seconds(5),
				      factor   = 1},
    ?MG_UPDATE_CI(Mg, request_timer, RequestTimer),

    d("[MGC] no reply to requests "
      "(simulate that the request takes a __long__ time)"),
    ?MGC_REQ_IGNORE(Mgc),

    d("[MG] set the 'init_request_timer' tag"),
    EccRes = (catch ?MG_ECC(Mg, megaco_messenger, 
			    init_request_timer, fun init_request_timer/1)),
    d("[MG] EccRes: ~p", [EccRes]),

    d("[MGC] late reply to requests "
      "(simulate that the request takes a long time)"),
    ?MGC_REQ_DISC(Mgc, 11000),

    d("[MG] send the notify"),
    {ok, Reply} = (catch ?MG_NOTIF_RAR(Mg)),
    d("[MG] Reply: ~p", [Reply]),
    {_Version, {ok, [_ActionReply]}} = Reply,

    %% Tell MG to stop
    i("[MG] stop"),
    ?MG_STOP(Mg),

    %% Tell Mgc to stop
    i("[MGC] stop"),
    ?MGC_STOP(Mgc),

    i("done", []),
    ok.

-else.

sent_resend_late_reply(suite) ->
    [];
sent_resend_late_reply(doc) ->
    "...";
sent_resend_late_reply(Config) when list(Config) ->
    ?SKIP("included only if compiled with USE_MEGACO_TEST_CODE=true").

-endif.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% This test case can only be run with the stack compiled with
%% the MEGACO_TEST_CODE flag. Therefor there is no point in 
%% including this test case in the usual test suite
-ifdef(MEGACO_TEST_CODE).
sent_resend_exceeded(suite) ->
    [];
sent_resend_exceeded(doc) ->
    "...";
sent_resend_exceeded(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        sent_resend_exceeded),
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
    MgConfig = [],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    d("MG user info: ~p", [?MG_USER_INFO(Mg, all)]),

    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    d("MG conn info: ~p", [?MG_CONN_INFO(Mg, all)]),

    d("[MGC] update connection info pending timer"),
    PendingTimer = infinity,
    ?MGC_UPDATE_CI(Mgc, pending_timer, PendingTimer),

    d("[MGC] update connection info sent pending limit"),
    PendingLimit = 5,
    ?MGC_UPDATE_CI(Mgc, sent_pending_limit, PendingLimit),

    d("[MG] update connection info request timer"),
    RequestTimer = #megaco_incr_timer{wait_for = timer:seconds(5),
				      factor   = 1},
    ?MG_UPDATE_CI(Mg, request_timer, RequestTimer),

    d("[MGC] no reply to requests "
      "(simulate that the request takes a __long__ time)"),
    ?MGC_REQ_IGNORE(Mgc),

    d("[MG] set the 'init_request_timer' tag"),
    EccRes = (catch ?MG_ECC(Mg, megaco_messenger, 
			    init_request_timer, fun init_request_timer/1)),
    d("[MG] EccRes: ~p", [EccRes]),

    d("[MG] send the notify"),
    ED = (catch ?MG_NOTIF_RAR(Mg)),
    d("[MG] ED: ~p", [ED]),
    ErrorCode = ?megaco_number_of_transactionpending_exceeded,
    #'ErrorDescriptor'{errorCode = ErrorCode} = ED,

    %% Tell MG to stop
    i("[MG] stop"),
    ?MG_STOP(Mg),

    %% Tell Mgc to stop
    i("[MGC] stop"),
    ?MGC_STOP(Mgc),

    i("done", []),
    ok.


-else.

sent_resend_exceeded(suite) ->
    [];
sent_resend_exceeded(doc) ->
    "...";
sent_resend_exceeded(Config) when list(Config) ->
    ?SKIP("included only if compiled with USE_MEGACO_TEST_CODE=true").

-endif.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% This test case can only be run with the stack compiled with
%% the MEGACO_TEST_CODE flag. Therefor there is no point in 
%% including this test case in the usual test suite
-ifdef(MEGACO_TEST_CODE).
sent_resend_exceeded_long(suite) ->
    [];
sent_resend_exceeded_long(doc) ->
    "...";
sent_resend_exceeded_long(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        sent_resend_exceeded_long),
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
    MgConfig = [],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    d("MG user info: ~p", [?MG_USER_INFO(Mg, all)]),

    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    d("MG conn info: ~p", [?MG_CONN_INFO(Mg, all)]),

    d("[MGC] update connection info pending timer"),
    PendingTimer = infinity,
    ?MGC_UPDATE_CI(Mgc, pending_timer, PendingTimer),

    d("[MGC] update connection info sent pending limit"),
    PendingLimit = 5,
    ?MGC_UPDATE_CI(Mgc, sent_pending_limit, PendingLimit),

    d("[MG] update connection info request timer"),
    RequestTimer = #megaco_incr_timer{wait_for = timer:seconds(5),
				      factor   = 1},
    ?MG_UPDATE_CI(Mg, request_timer, RequestTimer),

    d("[MGC] long request with no reply ~n"
      "   (simulate that we know that this will "
      "take a while, but takes even longer...)"),
    ?MGC_REQ_PIGNORE(Mgc),

    d("[MG] set the 'init_request_timer' tag"),
    EccRes = (catch ?MG_ECC(Mg, megaco_messenger, 
			    init_request_timer, fun init_request_timer/1)),
    d("[MG] EccRes: ~p", [EccRes]),

    d("[MG] send the notify"),
    ED = (catch ?MG_NOTIF_RAR(Mg)),
    d("[MG] ED: ~p", [ED]),
    ErrorCode = ?megaco_number_of_transactionpending_exceeded,
    #'ErrorDescriptor'{errorCode = ErrorCode} = ED,

    %% Tell MG to stop
    i("[MG] stop"),
    ?MG_STOP(Mg),

    %% Tell Mgc to stop
    i("[MGC] stop"),
    ?MGC_STOP(Mgc),

    i("done", []),
    ok.


-else.

sent_resend_exceeded_long(suite) ->
    [];
sent_resend_exceeded_long(doc) ->
    "...";
sent_resend_exceeded_long(Config) when list(Config) ->
    ?SKIP("included only if compiled with USE_MEGACO_TEST_CODE=true").

-endif.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                                                                   %%%
%%%                 Received peinding test cases                      %%%
%%%                                                                   %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

recv_limit_exceeded1(suite) ->
    [];
recv_limit_exceeded1(doc) ->
    "Received pending limit exceeded (exactly)";
recv_limit_exceeded1(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        rle1),
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
    MgcEvSeq = rle1_mgc_event_sequence(text, tcp),

    i("wait some time before starting the MGC simulation"),
    sleep(1000),

    d("[MGC] start the simulation"),
    megaco_test_generator:tcp(Mgc, MgcEvSeq),

    i("wait some time before starting the MG simulator"),
    sleep(1000),

    d("[MG] start the simulator (generator)"),
    {ok, Mg} = megaco_test_generator:start_link("MG", MgNode),

    d("[MG] create the event sequence"),
    MgEvSeq = rle1_mg_event_sequence(text, tcp),

    i("wait some time before starting the MG simulation"),
    sleep(1000),

    d("[MG] start the simulation"),
    megaco_test_generator:megaco(Mg, MgEvSeq),

    d("[MGC] await the generator reply"),
    case megaco_test_generator:tcp_await_reply(Mgc) of
        {ok, MgcReply} ->
            d("[MGC] OK => MgcReply: ~n~p", [MgcReply]),
            ok;
        {error, MgcReply} ->
            d("[MGC] ERROR => MgcReply: ~n~p", [MgcReply]),
            ?ERROR(mgc_failed)
    end,

    d("[MG] await the generator reply"),
    case megaco_test_generator:megaco_await_reply(Mg) of
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


%%
%% MGC generator stuff
%% 
rle1_mgc_event_sequence(text, tcp) ->
    Mid = {deviceName,"ctrl"},
    EM  = megaco_pretty_text_encoder,
    EC  = [],
    rle1_mgc_event_sequence2(Mid, EM, EC).

rle1_mgc_event_sequence2(Mid, EM, EC) ->
    DecodeFun = rle1_mgc_decode_msg_fun(EM, EC),
    EncodeFun = rle1_mgc_encode_msg_fun(EM, EC),
    ServiceChangeReqVerify = 
	rle1_mgc_verify_service_change_req_fun(Mid),
    ServiceChangeReply = 
	rle1_mgc_service_change_reply_msg(Mid, 1, 0),
    NotifyReqVerify = rle1_mgc_verify_notify_request_fun(),
    Pending = rle1_mgc_pending_msg(Mid,2),
    EvSeq = 
	[{debug,  true},
	 {decode, DecodeFun},
	 {encode, EncodeFun},
	 {listen, 2944},
	 {expect_accept, any},
	 {expect_receive, "service-change-req", 
	  {ServiceChangeReqVerify, 10000}}, 
	 {send, "service-change-reply", ServiceChangeReply}, 
	 {expect_receive, "notify-request", {NotifyReqVerify, 5000}},
	 {sleep, 100},
	 {send, "pending 1", Pending}, 
	 {sleep, 100},
	 {send, "pending 2", Pending}, 
	 {sleep, 100},
	 {send, "pending 3", Pending}, 
	 {sleep, 100},
	 {send, "pending 4", Pending}, 
	 {sleep, 100},
	 {send, "pending 5", Pending}, 
	 {sleep, 1000},
	 disconnect
	 ],
    EvSeq.

rle1_mgc_encode_msg_fun(Mod, Conf) ->
    fun(M) ->
            Mod:encode_message(Conf, M)
    end.

rle1_mgc_decode_msg_fun(Mod, Conf) ->
    fun(M) ->
            Mod:decode_message(Conf, M)
    end.

rle1_mgc_service_change_reply_msg(Mid, TransId, Cid) ->
    SCRP  = #'ServiceChangeResParm'{serviceChangeMgcId = Mid},
    SCRPs = {serviceChangeResParms,SCRP},
    Root  = #megaco_term_id{id = ["root"]},
    SCR   = #'ServiceChangeReply'{terminationID       = [Root],
                                  serviceChangeResult = SCRPs},
    CR    = {serviceChangeReply, SCR},
    rle1_mgc_msg(Mid, TransId, CR, Cid).
     
rle1_mgc_msg(Mid, TransId, CR, Cid) ->
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
     
rle1_mgc_pending_msg(Mid, TransId) ->
    TP   = #'TransactionPending'{transactionId = TransId},
    Body = {transactions, [{transactionPending, TP}]},
    Mess = #'Message'{version     = 1,
                      mId         = Mid,
                      messageBody = Body},
    #'MegacoMessage'{mess = Mess}.

rle1_mgc_verify_service_change_req_fun(_) ->
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

rle1_mgc_verify_notify_request_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) ->
	    io:format("rle1_mgc_verify_notify_request_fun -> entry~n", []),
            #'Message'{messageBody = Body} = Mess,
            {transactions, [Trans]} = Body,
            {transactionRequest, TR} = Trans,
            #'TransactionRequest'{actions = [AR]} = TR,
	    io:format("rle1_mgc_verify_notify_request_fun -> AR: "
		      "~n~p~n", [AR]),
            #'ActionRequest'{commandRequests = [CR]} = AR,
            #'CommandRequest'{command = Cmd} = CR,
            {notifyReq, NR} = Cmd,
            #'NotifyRequest'{observedEventsDescriptor = OED} = NR,
            #'ObservedEventsDescriptor'{observedEventLst = [OE]} = OED,
            #'ObservedEvent'{eventName = "al/of"} = OE,
            {ok, M};
       (M) ->
            {error, {invalid_message, M}}
    end.
    
% rle1_err_desc(T) ->
%     EC = ?megaco_internal_gateway_error,
%     ET = lists:flatten(io_lib:format("~w",[T])),
%     #'ErrorDescriptor'{errorCode = EC, errorText = ET}.


%%
%% MG generator stuff
%% 
rle1_mg_event_sequence(text, tcp) ->
    Mid = {deviceName,"mg"},
    RI = [
          {port,             2944},
          {encoding_module,  megaco_pretty_text_encoder},
          {encoding_config,  []},
          {transport_module, megaco_tcp}
         ],
    rle1_mg_event_sequence2(Mid, RI).

rle1_mg_event_sequence2(Mid, RI) ->
    ServiceChangeReq = [rle1_mg_service_change_request_ar(Mid, 1)],
    ConnectVerify = fun rle1_mg_verify_handle_connect/1,
    ServiceChangeReplyVerify = 
	fun rle1_mg_verify_service_change_reply/1,
    Tid = #megaco_term_id{id = ["00000000","00000000","01101101"]},
    NotifyReq = [rle1_mg_notify_request_ar(1, Tid, 1)],
    TransReplyVerify = fun rle1_mg_verify_trans_reply/1,
    EvSeq = [
             {debug, true},
             megaco_start,
             {megaco_start_user, Mid, RI, []},
	     {megaco_update_user_info, recv_pending_limit, 4},
             start_transport,
             {megaco_trace, disable}, %%100},
             {megaco_system_info, users},
             {megaco_system_info, connections},
             connect,
             {megaco_callback, handle_connect, ConnectVerify},
             megaco_connect,
             {megaco_cast, ServiceChangeReq, []},
             {megaco_callback, handle_connect, ConnectVerify},
             {megaco_callback, handle_trans_reply, ServiceChangeReplyVerify},
             {sleep, 1000},
             {megaco_cast, NotifyReq, []},
             {megaco_callback, handle_trans_reply, TransReplyVerify},
             {sleep, 1000},
             megaco_stop_user,
             megaco_stop,
             {sleep, 1000}
            ],
    EvSeq.


rle1_mg_verify_handle_connect({handle_connect, CH, ?VERSION}) -> 
    io:format("rle1_mg_verify_handle_connect -> ok"
	      "~n   CH: ~p~n", [CH]),
    {ok, CH, ok};
rle1_mg_verify_handle_connect(Else) ->
    io:format("rle1_mg_verify_handle_connect -> unknown"
	      "~n   Else: ~p~n", [Else]),
    {error, Else, ok}.

rle1_mg_verify_service_change_reply({handle_trans_reply, _CH, 
					       ?VERSION, 
					       {ok, [AR]}, _}) ->
    io:format("rle1_mg_verify_service_change_reply -> ok"
	      "~n   AR: ~p~n", [AR]),
    case AR of
	#'ActionReply'{commandReply = [SCR]} ->
	    case SCR of
		{serviceChangeReply,
		 #'ServiceChangeReply'{terminationID = [Tid],
				       serviceChangeResult = Res}} ->
		    case Tid of
			#megaco_term_id{contains_wildcards = false, 
					id = ["root"]} ->
			    case Res of
				{serviceChangeResParms,
				 #'ServiceChangeResParm'{
				   serviceChangeMgcId = _RemoteMid}} ->
				    {ok, AR, ok};
				{Tag, Val} ->
				    Err = {invalid_service_change_result, 
					   Tag, Val},
				    {error, Err, ok}
			    end;
			_ ->
			    Err = {invalid_termination_id, Tid},
			    {error, Err, ok}
		    end;
		{Tag, Val} ->
		    Err = {invalid_command_reply, Tag, Val},
		    {error, Err, ok}
	    end;
	_ ->
	    Err = {invalid_action_reply, AR},
	    {error, Err, ok}
    end;
rle1_mg_verify_service_change_reply(Else) ->
    io:format("rle1_mg_verify_service_change_reply -> unknown"
	      "~n   Else: ~p~n", [Else]),
    {error, Else, ok}.

rle1_mg_verify_trans_reply({handle_trans_reply, _CH, ?VERSION, 
			    {error, exceeded_recv_pending_limit} = E, _}) ->
    io:format("rle1_mg_verify_trans_reply -> expected error~n", []),
    {ok, E    , error};
rle1_mg_verify_trans_reply(Else) ->
    io:format("rle1_mg_verify_trans_reply -> unknown"
	      "~n   Else: ~p~n", [Else]),
    {error, Else, error}.

rle1_mg_service_change_request_ar(_Mid, Cid) ->
    Prof  = cre_serviceChangeProf("resgw", 1),
    SCP   = cre_serviceChangeParm(restart, ["901 mg col boot"], Prof),
    Root  = #megaco_term_id{id = ["root"]},
    SCR   = cre_serviceChangeReq([Root], SCP),
    CMD   = cre_command(SCR),
    CR    = cre_cmdReq(CMD),
    cre_actionReq(Cid, [CR]).

rle1_mg_notify_request_ar(Rid, Tid, Cid) ->
    TT      = cre_timeNotation("19990729", "22000000"),
    Ev      = cre_obsEvent("al/of", TT),
    EvsDesc = cre_obsEvsDesc(Rid, [Ev]),
    NR      = cre_notifyReq([Tid], EvsDesc),
    CMD     = cre_command(NR),
    CR      = cre_cmdReq(CMD),
    cre_actionReq(Cid, [CR]).


%% ---

recv_limit_exceeded2(suite) ->
    [];
recv_limit_exceeded2(doc) ->
    "Received pending limit exceeded";
recv_limit_exceeded2(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        rle2),
    i("starting"),

    _MgcNode = make_node_name(mgc),
    _MgNode  = make_node_name(mg),

    ?SKIP(not_yet_implemented).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                                                                   %%%
%%%                       Ticket test cases                           %%%
%%%                                                                   %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

otp_4956(suite) ->
    [];
otp_4956(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        otp_4956),
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
    MgcEvSeq = otp_4956_mgc_event_sequence(text, tcp),

    i("wait some time before starting the MGC simulation"),
    sleep(1000),

    d("[MGC] start the simulation"),
    megaco_test_generator:megaco(Mgc, MgcEvSeq),

    i("wait some time before starting the MG simulator"),
    sleep(1000),

    d("[MG] start the simulator (generator)"),
    {ok, Mg} = megaco_test_generator:start_link("MG", MgNode),

    d("[MG] create the event sequence"),
    MgEvSeq = otp_4956_mg_event_sequence(text, tcp),

    i("wait some time before starting the MG simulation"),
    sleep(1000),

    d("[MG] start the simulation"),
    megaco_test_generator:tcp(Mg, MgEvSeq),

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


%%
%% MGC generator stuff
%% 
otp_4956_mgc_event_sequence(text, tcp) ->
    Mid = {deviceName,"ctrl"},
    RI = [
          {port,             2944},
          {encoding_module,  megaco_pretty_text_encoder},
          {encoding_config,  []},
          {transport_module, megaco_tcp}
         ],
    ConnectVerify = fun otp_4956_mgc_verify_handle_connect/1,
    ServiceChangeReqVerify = otp_4956_mgc_verify_service_change_req_fun(Mid),
    NotifyReqVerify = otp_4956_mgc_verify_notify_request_fun(),
    ReqAbortVerify = fun otp_4956_mgc_verify_handle_trans_request_abort/1, 
    DiscoVerify = fun otp_4956_mgc_verify_handle_disconnect/1,
    EvSeq = [
             {debug, true},
	     {megaco_trace, disable},
             %% {megaco_trace, 100},
             megaco_start,
             {megaco_start_user, Mid, RI, []},
	     {megaco_update_user_info, sent_pending_limit, 4},
             start_transport,
             listen,
             {megaco_callback, handle_connect, ConnectVerify},
	     {megaco_conn_info, all},
             {megaco_callback, handle_trans_request, ServiceChangeReqVerify},
             {megaco_callback, handle_trans_request, NotifyReqVerify},
             {megaco_callback, handle_trans_request_abort, ReqAbortVerify},
             {megaco_callback, nocall, 1000},
             {megaco_callback, handle_disconnect, DiscoVerify},
             megaco_stop_user,
             megaco_stop
            ],
    EvSeq.

otp_4956_mgc_verify_handle_connect({handle_connect, CH, ?VERSION}) -> 
    {ok, CH, ok};
otp_4956_mgc_verify_handle_connect(Else) ->
    {error, Else, ok}.

otp_4956_mgc_verify_service_change_req_fun(Mid) ->
    fun({handle_trans_request, _, ?VERSION, [AR]}) ->
%             io:format("otp_4956_mgc_verify_service_change_req -> ok"
%                       "~n   AR: ~p~n", [AR]),
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
                                                         serviceChangeReason = [[$9,$0,$1|_]]} ->
                                                    Reply = 
                                                        {discard_ack, 
                                                         [otp_4956_mgc_service_change_reply_ar(Mid, 1)]},
                                                    {ok, AR, Reply};
                                                _ ->
                                                    Err = {invalid_SCP, Parms},
                                                    ED = otp_4956_err_desc(Parms),
                                                    ErrReply = {discard_ack, 
                                                                ED},
                                                    {error, Err, ErrReply}
                                            end;
                                        _ ->
                                            Err = {invalid_termination_id, Tid},
                                            ED = otp_4956_err_desc(Tid),
                                            ErrReply = {discard_ack, ED},
                                            {error, Err, ErrReply}
                                    end;
                                _ ->
                                    Err = {invalid_command, Cmd},
                                    ED = otp_4956_err_desc(Cmd),
                                    ErrReply = {discard_ack, ED},
                                    {error, Err, ErrReply}
                            end;
                        _ ->
                            Err = {invalid_command_request, CR},
                            ED = otp_4956_err_desc(CR),
                            ErrReply = {discard_ack, ED},
                            {error, Err, ErrReply}
                    end;
                _ ->
                    Err = {invalid_action_request, AR},
                    ED = otp_4956_err_desc(AR),
                    ErrReply = {discard_ack, ED},
                    {error, Err, ErrReply}
            end;
       (Else) ->
%             io:format("otp_4956_mgc_verify_service_change_req -> unknown"
%                       "~n   Else: ~p~n", [Else]),
            ED = otp_4956_err_desc(Else),
            ErrReply = {discard_ack, ED},
            {error, Else, ErrReply}
    end.

otp_4956_mgc_verify_notify_request_fun() ->
    fun({handle_trans_request, _, ?VERSION, [AR]}) ->
%             io:format("otp_4956_mgc_verify_notify_request:fun -> ok"
%                       "~n   AR: ~p~n", [AR]),
            case AR of
                #'ActionRequest'{contextId = Cid, 
                                 commandRequests = [CR]} ->
                    #'CommandRequest'{command = Cmd} = CR,
                    {notifyReq, NR} = Cmd,
                    #'NotifyRequest'{terminationID = [Tid],
                                     observedEventsDescriptor = OED,
                                     errorDescriptor = asn1_NOVALUE} = NR,
                    #'ObservedEventsDescriptor'{observedEventLst = [OE]} = OED,
                    #'ObservedEvent'{eventName = "al/of"} = OE,
                    Reply = {discard_ack, [otp_4956_mgc_notify_reply_ar(Cid, Tid)]},
                    {ok, 6000, AR, Reply};
                _ ->
                    ED = otp_4956_err_desc(AR),
                    ErrReply = {discard_ack, ED},
                    {error, AR, ErrReply}
            end;
       (Else) ->
%             io:format("otp_4956_mgc_verify_notify_request:fun -> unknown"
%                       "~n   Else: ~p~n", [Else]),
            ED = otp_4956_err_desc(Else),
            ErrReply = {discard_ack, ED},
            {error, Else, ErrReply}
    end.

otp_4956_mgc_verify_handle_trans_request_abort({handle_trans_request_abort, 
						CH, ?VERSION, 2, Pid}) -> 
    {ok, {CH, Pid}, ok};
otp_4956_mgc_verify_handle_trans_request_abort(Else) ->
    {error, Else, ok}.

otp_4956_mgc_verify_handle_disconnect({handle_disconnect, CH, ?VERSION, _}) -> 
%     io:format("otp_4956_mgc_verify_handle_disconnect -> ok"
%               "~n   CH: ~p"
%               "~n   R:  ~p"
%               "~n", [CH, R]),
    {ok, CH, ok};
otp_4956_mgc_verify_handle_disconnect(Else) ->
%     io:format("otp_4956_mgc_verify_handle_disconnect -> unknown"
%               "~n   Else: ~p~n", [Else]),
    {error, Else, ok}.

otp_4956_mgc_service_change_reply_ar(Mid, Cid) ->
    SCRP  = cre_serviceChangeResParm(Mid),
    SCRes = cre_serviceChangeResult(SCRP),
    Root  = #megaco_term_id{id = ["root"]},
    SCR   = cre_serviceChangeReply([Root], SCRes),
    CR    = cre_cmdReply(SCR),
    AR    = cre_actionReply(Cid, [CR]),
    AR.

%% otp_4956_mgc_service_change_reply_msg(Mid, TransId, Cid) ->
%%     AR    = otp_4956_mgc_service_change_reply_ar(Mid, Cid),
%%     TRes  = cre_transResult([AR]),
%%     TR    = cre_transReply(TransId, TRes),
%%     Trans = cre_transaction(TR),
%%     Mess  = cre_message(?VERSION, Mid, cre_transactions([Trans])),
%%     cre_megacoMessage(Mess).

otp_4956_mgc_notify_reply_ar(Cid, TermId) ->
    NR    = cre_notifyReply([TermId]),
    CR    = cre_cmdReply(NR),
    cre_actionReply(Cid, [CR]).

%% otp_4956_mgc_notify_reply(Mid, TransId, Cid, TermId) ->
%%     AR    = otp_4956_mgc_notify_reply_ar(Cid, TermId),
%%     TRes  = cre_transResult([AR]),
%%     TR    = cre_transReply(TransId, TRes),
%%     Trans = cre_transaction(TR),
%%     Mess  = cre_message(?VERSION, Mid, cre_transactions([Trans])),
%%     cre_megacoMessage(Mess).


%%
%% MG generator stuff
%% 
otp_4956_mg_event_sequence(text, tcp) ->
    DecodeFun = otp_4956_mg_decode_msg_fun(megaco_pretty_text_encoder, []),
    EncodeFun = otp_4956_mg_encode_msg_fun(megaco_pretty_text_encoder, []),
    Mid = {deviceName,"mg"},
    ServiceChangeReq = otp_4956_mg_service_change_request_msg(Mid, 1, 0),
    ServiceChangeReplyVerifyFun = 
	otp_4956_mg_verify_service_change_rep_msg_fun(),
    TermId = #megaco_term_id{id = ["00000000","00000000","01101101"]},
    NotifyReq = otp_4956_mg_notify_request_msg(Mid, 2, 1, TermId, 1),
    PendingVerify = otp_4956_mg_verify_pending_msg_fun(),
    PendingLimitVerify = otp_4956_mg_verify_pending_limit_msg_fun(),
    EvSeq = [{debug,  true},
	     {decode, DecodeFun},
	     {encode, EncodeFun},
	     {connect, 2944},
	     {send, "service-change-request", ServiceChangeReq}, 
	     {expect_receive, "service-change-reply", {ServiceChangeReplyVerifyFun, 10000}}, 
	     {send, "notify request (first send)", NotifyReq}, 
	     {sleep, 100},
	     {send, "notify request (resend 1)", NotifyReq}, 
	     {expect_receive, "pending 1", {PendingVerify, 1000}},
	     {sleep, 1000},
	     {send, "notify request (resend 2)", NotifyReq}, 
	     {expect_receive, "pending 2", {PendingVerify, 1000}},
	     {sleep, 1000},
	     {send, "notify request (resend 3)", NotifyReq}, 
	     {expect_receive, "pending 3", {PendingVerify, 1000}},
	     {sleep, 1000},
	     {send, "notify request (resend 4)", NotifyReq}, 
	     {expect_receive, "pending 4", {PendingVerify, 1000}},
	     {sleep, 1000},
	     {send, "notify request (resend 5)", NotifyReq}, 
	     {expect_receive, "pending limit exceeded", 
	      {PendingLimitVerify, 1000}},
	     {sleep, 2000},
	     {send, "notify request (resend 6)", NotifyReq}, 
	     {expect_nothing, 2000},
	     disconnect
	    ],
    EvSeq.

otp_4956_mg_encode_msg_fun(Mod, Conf) ->
    fun(M) -> 
            Mod:encode_message(Conf, M) 
    end.
% otp_4956_mg_encode_msg_fun(Mod, Conf, Ver) ->
%     fun(M) -> 
%             Mod:encode_message(Conf, Ver, M) 
%     end.

otp_4956_mg_decode_msg_fun(Mod, Conf) ->
    fun(M) -> 
            Mod:decode_message(Conf, M) 
    end.
% otp_4956_mg_decode_msg_fun(Mod, Conf, Ver) ->
%     fun(M) -> 
%             Mod:decode_message(Conf, Ver, M) 
%     end.

otp_4956_mg_verify_service_change_rep_msg_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
            io:format("otp_4956_mg_verify_service_change_rep:fun -> "
		      "ok so far~n",[]),
            #'Message'{version     = _V,
                       mId         = _MgMid,
                       messageBody = Body} = Mess,
            {transactions, [Trans]} = Body,
            {transactionReply, TR} = Trans,
            #'TransactionReply'{transactionId = _Tid,
				immAckRequired = asn1_NOVALUE,
				transactionResult = Res} = TR,
	    {actionReplies, [AR]} = Res,
            #'ActionReply'{contextId = _Cid,
			   errorDescriptor = asn1_NOVALUE,
			   contextReply = _CtxReq,
			   commandReply = [CR]} = AR,
	    {serviceChangeReply, SCR} = CR,
            #'ServiceChangeReply'{terminationID = _TermID,
				  serviceChangeResult = SCRes} = SCR,
	    {serviceChangeResParms, SCRP} = SCRes,
            #'ServiceChangeResParm'{serviceChangeMgcId = _MgcMid} = SCRP,
            {ok, M};
       (M) ->
            {error, {invalid_message, M}}
    end.

otp_4956_mg_verify_pending_msg_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
	    io:format("otp_4956_mg_verify_pending_msg_fun -> entry with"
		      "~n~p~n", [M]),
            #'Message'{messageBody = Body} = Mess,
            {transactions, [Trans]} = Body,
            {transactionPending, TP} = Trans,
            #'TransactionPending'{transactionId = _Id} = TP,
	    io:format("otp_4956_mg_verify_pending_msg_fun -> done~n", []),
            {ok, M};
       (M) ->
            {error, {invalid_message, M}}
    end.

otp_4956_mg_verify_pending_limit_msg_fun() ->
    fun(#'MegacoMessage'{mess = Mess} = M) -> 
	    io:format("otp_4956_mg_verify_pending_limit_msg_fun -> entry with"
		      "~n~p~n", [M]),
            #'Message'{messageBody = Body} = Mess,
	    io:format("otp_4956_mg_verify_pending_limit_msg_fun -> Body"
		      "~n~p~n", [Body]),
	    case Body of
		{messageError, ED} ->
		    EC = ?megaco_number_of_transactionpending_exceeded,
		    #'ErrorDescriptor'{errorCode = EC} = ED,
		    {ok, M};
		_ ->
		    {error, {invalid_messageBody, Body}}
	    end;
       (M) ->
            {error, {invalid_message, M}}
    end.

otp_4956_mg_service_change_request_ar(_Mid, Cid) ->
    Prof  = cre_serviceChangeProf("resgw", 1),
    SCP   = cre_serviceChangeParm(restart, ["901 mg col boot"], Prof),
    Root  = #megaco_term_id{id = ["root"]},
    SCR   = cre_serviceChangeReq([Root], SCP),
    CMD   = cre_command(SCR),
    CR    = cre_cmdReq(CMD),
    cre_actionReq(Cid, [CR]).

otp_4956_mg_service_change_request_msg(Mid, TransId, Cid) ->
    AR    = otp_4956_mg_service_change_request_ar(Mid, Cid),
    TR    = cre_transReq(TransId, [AR]),
    Trans = cre_transaction(TR),
    Mess  = cre_message(?VERSION, Mid, cre_transactions([Trans])),
    cre_megacoMessage(Mess).

otp_4956_mg_notify_request_ar(Rid, Tid, Cid) ->
    TT      = cre_timeNotation("19990729", "22000000"),
    Ev      = cre_obsEvent("al/of", TT),
    EvsDesc = cre_obsEvsDesc(Rid, [Ev]),
    NR      = cre_notifyReq([Tid], EvsDesc),
    CMD     = cre_command(NR),
    CR      = cre_cmdReq(CMD),
    cre_actionReq(Cid, [CR]).

otp_4956_mg_notify_request_msg(Mid, TransId, Rid, TermId, Cid) ->
    AR      = otp_4956_mg_notify_request_ar(Rid, TermId, Cid),
    TR      = cre_transReq(TransId, [AR]),
    Trans   = cre_transaction(TR),
    Mess    = cre_message(?VERSION, Mid, cre_transactions([Trans])),
    cre_megacoMessage(Mess).


otp_4956_err_desc(T) ->
    EC = ?megaco_internal_gateway_error,
    ET = lists:flatten(io_lib:format("~w",[T])),
    #'ErrorDescriptor'{errorCode = EC, errorText = ET}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

otp_5310(suite) ->
    [];
otp_5310(doc) ->
    "...";
otp_5310(Config) when list(Config) ->
    put(verbosity, ?TEST_VERBOSITY),
    put(sname,     "TEST"),
    put(tc,        otp_5310),
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
    MgConfig = [],
    {ok, Mg} = ?MG_START(MgNode, MgMid, text, tcp, MgConfig, ?MG_VERBOSITY),

    d("MG user info: ~p", [?MG_USER_INFO(Mg, all)]),

    i("[MG] connect to the MGC (service change)"),    
    ServChRes = ?MG_SERV_CHANGE(Mg),
    d("service change result: ~p", [ServChRes]),

    d("MG conn info: ~p", [?MG_CONN_INFO(Mg, all)]),

    d("[MGC] update connection info pending timer"),
    PendingTimer = #megaco_incr_timer{wait_for = timer:seconds(1),
				      factor   = 1},
    ?MGC_UPDATE_CI(Mgc, pending_timer, PendingTimer),

    d("[MGC] update connection info originating pending limit"),
    PendingLimit = 3,
    ?MGC_UPDATE_CI(Mgc, orig_pending_limit, PendingLimit),

    ConnReps1 = ?MGC_CONN_INFO(Mgc, replies),
    d("[MGC] ConnReps1: ~p", [ConnReps1]),
    case filter_aborted1(ConnReps1, []) of
	[{_, []}] ->
	    ok;
	ConnFlt1 ->
	    ?ERROR({unexpected_reply_state, conn_info, ConnReps1, ConnFlt1})
    end,
    UserReps1 = ?MGC_USER_INFO(Mgc, replies),
    d("[MGC] UserReps1: ~p", [UserReps1]),
    case filter_aborted1(UserReps1, []) of
	[{_, []}] ->
	    ok;
	UserFlt1 ->
	    ?ERROR({unexpected_reply_state, user_info, UserReps1, UserFlt1})
    end,

    %% Instruct the MGC to never reply to requests
    d("[MGC] don't reply to requests"),
    ?MGC_REQ_IGNORE(Mgc),

    %% We want to know when the abort comes...
    d("[MGC] request abort inform"),
    ?MGC_ABORT_INFO(Mgc, self()),

    %% Make MG send a request
    d("[MG] send the notify"),
    Reply = ?MG_NOTIF_RAR(Mg),
    d("[MG] Reply: ~p", [Reply]),
    case Reply of
	#'ErrorDescriptor'{errorCode = 
			   ?megaco_number_of_transactionpending_exceeded} ->
	    ok;
	_ ->
	    ?ERROR({invalid_mg_reply, Reply})
    end,

    %% Wait for the MGC to get aborted
    d("[MGC] await the abort callback"),
    {ok, TransId} = await_aborted(Mgc),
    d("[MGC] aborted transaction: ~p", [TransId]),

    %% Make sure we have one in aborted state
    d("[MGC] how many is aborted (should be == 1)?"),
    ConnReps2 = ?MGC_CONN_INFO(Mgc, replies),
    case filter_aborted1(ConnReps2, []) of
	[{_, [TransId]}] ->
	    ok;
	_ ->
	    ?ERROR({unexpected_reply_state, conn_info, ConnReps2})
    end,
    d("[MGC] ConnReps2: ~p", [ConnReps2]),
    UserReps2 = ?MGC_USER_INFO(Mgc, replies),
    d("[MGC] UserReps2: ~p", [UserReps2]),
    case filter_aborted1(UserReps2, []) of
	[{_, [TransId]}] ->
	    ok;
	_ ->
	    ?ERROR({unexpected_reply_state, user_info, UserReps2})
    end,

    %% do disconnect and the do cancel in the handle function
    d("[MGC] disconnect"),
    DiscoRes = ?MGC_DISCO(Mgc, cancel),
    d("[MGC] DiscoRes: ~p", [DiscoRes]),

    %% check number of reply records (should be no in aborted).
    d("[MGC] check number of replies in aborted state (should be == 1)"),
    ConnReps3 = ?MGC_CONN_INFO(Mgc, replies),
    d("[MGC] ConnReps3: ~p", [ConnReps3]),
    UserReps3 = ?MGC_USER_INFO(Mgc, replies),
    d("[MGC] UserReps3: ~p", [UserReps3]),

    %% Tell MG to stop
    i("[MG] stop"),
    ?MG_STOP(Mg),

    %% Tell Mgc to stop
    i("[MGC] stop"),
    ?MGC_STOP(Mgc),

    i("done", []),
    ok.

await_aborted(Mgc) ->
    d("await_aborted"),
    receive
	{abort_received, Mgc, TransId} ->
	    {ok, TransId}
    after 10000 ->
	    d("await_aborted - timeout"),
	    {error, timeout}
    end.

filter_aborted1([], Acc) ->
    lists:reverse(Acc);
filter_aborted1([{CH, Ab}|T], Acc) ->
    filter_aborted1(T, [{CH, filter_aborted2(Ab, [])}|Acc]).

filter_aborted2([], Aborted) ->
    lists:reverse(Aborted);
filter_aborted2([{TransId, aborted, _}|T], Aborted) ->
    filter_aborted2(T, [TransId|Aborted]);
filter_aborted2([_|T], Aborted) ->
    filter_aborted2(T, Aborted).
    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%
%% Common message creation functions
%%

cre_serviceChangeParm(M,R,P) ->
    #'ServiceChangeParm'{serviceChangeMethod  = M, 
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
%% cre_obsEvent(Name, Not, Par) ->
%%     #'ObservedEvent'{eventName    = Name, 
%%                      timeNotation = Not, 
%%                      eventParList = Par}.

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

cre_serviceChangeResParm(Mid) ->
    cre_serviceChangeResParm(Mid, ?VERSION).

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

%% cre_transResult(ED) when record(ED, 'ErrorDescriptor') ->
%%     {transactionError, ED};
%% cre_transResult([AR|_] = ARs) when record(AR, 'ActionReply') ->
%%     {actionReplies, ARs}.

%% cre_transReply(TransId, Res) ->
%%     #'TransactionReply'{transactionId     = TransId,
%%                         transactionResult = Res}.

%% --

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


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Transform a short timer to a long one.
%% The purpose of this is to trick the stack
%% to keep re-sending the request, even after 
%% having received the first pending (which
%% indicates that the other side _IS_ 
%% working on the request).
-ifdef(MEGACO_TEST_CODE).

init_request_timer({short, Ref}) ->
    {long, Ref};  
init_request_timer(O) ->
    O.

-endif.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% tim() ->
%%     {A,B,C} = erlang:now(),
%%     A*1000000000+B*1000+(C div 1000).


make_node_name(Name) ->
    case string:tokens(atom_to_list(node()), [$@]) of
	[_,Host] ->
	    list_to_atom(lists:concat([atom_to_list(Name) ++ "@" ++ Host]));
	_ ->
	    exit("Test node must be started with '-sname'")
     end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sleep(X) -> receive after X -> ok end.

%% error_msg(F,A) -> error_logger:error_msg(F ++ "~n",A).


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


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% random_init() ->
%%     {A,B,C} = now(),
%%     random:seed(A,B,C).

%% random() ->
%%     10 * random:uniform(50).

%% apply_load_timer() ->
%%     erlang:send_after(random(), self(), apply_load_timeout).


format_timestamp({_N1, _N2, N3} = Now) ->
    {Date, Time}   = calendar:now_to_datetime(Now),
    {YYYY,MM,DD}   = Date,
    {Hour,Min,Sec} = Time,
    FormatDate = 
        io_lib:format("~.4w:~.2.0w:~.2.0w ~.2.0w:~.2.0w:~.2.0w 4~w",
                      [YYYY,MM,DD,Hour,Min,Sec,round(N3/1000)]),  
    lists:flatten(FormatDate).

