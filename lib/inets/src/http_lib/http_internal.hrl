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

-include("inets_internal.hrl").

-define(HTTP_MAX_BODY_SIZE, nolimit).
-define(HTTP_MAX_HEADER_SIZE, 10240).

%%% Response headers
-record(http_response_h,{
%%% --- Standard "General" headers
 	  'cache-control',
 	  connection,
 	  date,
 	  pragma,
 	  trailer,
 	  'transfer-encoding',
 	  upgrade,
 	  via,
 	  warning,
%%% --- Standard "Response" headers
 	  'accept-ranges',
 	  age,
 	  etag,
 	  location,
 	  'proxy-authenticate',
 	  'retry-after',
 	  server,
 	  vary,
 	  'www-authenticate',
%%% --- Standard "Entity" headers
 	  allow,
 	  'content-encoding',
 	  'content-language',
 	  'content-length' = "0",
 	  'content-location',
	  'content-md5',
 	  'content-range',
 	  'content-type',
 	  expires,
 	  'last-modified',
	  other=[]        % list() - Key/Value list with other headers
	 }).


%%% Request headers
-record(http_request_h,{
%%% --- Standard "General" headers
 	  'cache-control',
 	  connection = "keep-alive",
 	  date,
 	  pragma,
 	  trailer,
 	  'transfer-encoding',
 	  upgrade,
 	  via,
 	  warning,
%%% --- Standard "Request" headers
 	  accept,
 	  'accept-charset',
 	  'accept-encoding',
 	  'accept-language',
 	  authorization,
 	  expect, 
 	  from,
 	  host,
 	  'if-match',
 	  'if-modified-since',
 	  'if-none-match',
 	  'if-range',
 	  'if-unmodified-since',
 	  'max-forwards',
	  'proxy-authenticate', 
 	  range,
 	  referer,
 	  te, 
 	  'user-agent',
%%% --- Standard "Entity" headers
	  allow,
 	  'content-encoding',
 	  'content-language',
 	  'content-length' = "0",
	  'content-location',
 	  'content-md5',
 	  'content-range',
 	  'content-type',
	  expires,
 	  'last-modified',
	  other=[]        % list() - Key/Value list with other headers
	 }).
