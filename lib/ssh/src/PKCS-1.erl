%% Generated by the Erlang ASN.1 BER_V2-compiler version, utilizing bit-syntax:1.4.5
%% Purpose: encoder and decoder to the types in mod PKCS-1

-module('PKCS-1').
-include("PKCS-1.hrl").
-define('RT_BER',asn1rt_ber_bin_v2).
-asn1_info([{vsn,'1.4.5'},
            {module,'PKCS-1'},
            {options,[ber_bin_v2,report_errors,{cwd,[47,108,100,105,115,107,47,100,97,105,108,121,95,98,117,105,108,100,47,111,116,112,95,112,114,101,98,117,105,108,100,95,114,49,49,98,46,50,48,48,55,45,48,54,45,49,49,95,49,57,47,111,116,112,95,115,114,99,95,82,49,49,66,45,53,47,108,105,98,47,115,115,104,47,115,114,99]},{outdir,[47,108,100,105,115,107,47,100,97,105,108,121,95,98,117,105,108,100,47,111,116,112,95,112,114,101,98,117,105,108,100,95,114,49,49,98,46,50,48,48,55,45,48,54,45,49,49,95,49,57,47,111,116,112,95,115,114,99,95,82,49,49,66,45,53,47,108,105,98,47,115,115,104,47,115,114,99]},noobj,optimize,compact_bit_string,der,{i,[46]},{i,[47,108,100,105,115,107,47,100,97,105,108,121,95,98,117,105,108,100,47,111,116,112,95,112,114,101,98,117,105,108,100,95,114,49,49,98,46,50,48,48,55,45,48,54,45,49,49,95,49,57,47,111,116,112,95,115,114,99,95,82,49,49,66,45,53,47,108,105,98,47,115,115,104,47,115,114,99]}]}]).

-export([encoding_rule/0]).
-export([
'enc_RSAPublicKey'/2,
'enc_RSAPrivateKey'/2,
'enc_Version'/2,
'enc_OtherPrimeInfos'/2,
'enc_OtherPrimeInfo'/2,
'enc_Algorithm'/2,
'enc_AlgorithmNull'/2,
'enc_RSASSA-PSS-params'/2,
'enc_TrailerField'/2,
'enc_DigestInfo'/2,
'enc_DigestInfoNull'/2
]).

-export([
'dec_RSAPublicKey'/2,
'dec_RSAPrivateKey'/2,
'dec_Version'/2,
'dec_OtherPrimeInfos'/2,
'dec_OtherPrimeInfo'/2,
'dec_Algorithm'/2,
'dec_AlgorithmNull'/2,
'dec_RSASSA-PSS-params'/2,
'dec_TrailerField'/2,
'dec_DigestInfo'/2,
'dec_DigestInfoNull'/2
]).

-export([
'pkcs-1'/0,
'rsaEncryption'/0,
'id-RSAES-OAEP'/0,
'id-pSpecified'/0,
'id-RSASSA-PSS'/0,
'md2WithRSAEncryption'/0,
'md5WithRSAEncryption'/0,
'sha1WithRSAEncryption'/0,
'sha256WithRSAEncryption'/0,
'sha384WithRSAEncryption'/0,
'sha512WithRSAEncryption'/0,
'id-sha1'/0,
'id-md2'/0,
'id-md5'/0,
'id-mgf1'/0
]).

-export([info/0]).


-export([encode/2,decode/2,encode_disp/2,decode_disp/2]).

encoding_rule() ->
   ber_bin_v2.

encode(Type,Data) ->
case catch encode_disp(Type,Data) of
  {'EXIT',{error,Reason}} ->
    {error,Reason};
  {'EXIT',Reason} ->
    {error,{asn1,Reason}};
  {Bytes,_Len} ->
    {ok,Bytes};
  Bytes ->
    {ok,Bytes}
end.

decode(Type,Data) ->
case catch decode_disp(Type,element(1,?RT_BER:decode(Data))
) of
  {'EXIT',{error,Reason}} ->
    {error,Reason};
  {'EXIT',Reason} ->
    {error,{asn1,Reason}};
  Result ->
    {ok,Result}
end.

encode_disp('RSAPublicKey',Data) -> 'enc_RSAPublicKey'(Data);
encode_disp('RSAPrivateKey',Data) -> 'enc_RSAPrivateKey'(Data);
encode_disp('Version',Data) -> 'enc_Version'(Data);
encode_disp('OtherPrimeInfos',Data) -> 'enc_OtherPrimeInfos'(Data);
encode_disp('OtherPrimeInfo',Data) -> 'enc_OtherPrimeInfo'(Data);
encode_disp('Algorithm',Data) -> 'enc_Algorithm'(Data);
encode_disp('AlgorithmNull',Data) -> 'enc_AlgorithmNull'(Data);
encode_disp('RSASSA-PSS-params',Data) -> 'enc_RSASSA-PSS-params'(Data);
encode_disp('TrailerField',Data) -> 'enc_TrailerField'(Data);
encode_disp('DigestInfo',Data) -> 'enc_DigestInfo'(Data);
encode_disp('DigestInfoNull',Data) -> 'enc_DigestInfoNull'(Data);
encode_disp(Type,_Data) -> exit({error,{asn1,{undefined_type,Type}}}).


decode_disp('RSAPublicKey',Data) -> 'dec_RSAPublicKey'(Data);
decode_disp('RSAPrivateKey',Data) -> 'dec_RSAPrivateKey'(Data);
decode_disp('Version',Data) -> 'dec_Version'(Data);
decode_disp('OtherPrimeInfos',Data) -> 'dec_OtherPrimeInfos'(Data);
decode_disp('OtherPrimeInfo',Data) -> 'dec_OtherPrimeInfo'(Data);
decode_disp('Algorithm',Data) -> 'dec_Algorithm'(Data);
decode_disp('AlgorithmNull',Data) -> 'dec_AlgorithmNull'(Data);
decode_disp('RSASSA-PSS-params',Data) -> 'dec_RSASSA-PSS-params'(Data);
decode_disp('TrailerField',Data) -> 'dec_TrailerField'(Data);
decode_disp('DigestInfo',Data) -> 'dec_DigestInfo'(Data);
decode_disp('DigestInfoNull',Data) -> 'dec_DigestInfoNull'(Data);
decode_disp(Type,_Data) -> exit({error,{asn1,{undefined_type,Type}}}).





info() ->
   case ?MODULE:module_info() of
      MI when is_list(MI) ->
         case lists:keysearch(attributes,1,MI) of
            {value,{_,Attributes}} when is_list(Attributes) ->
               case lists:keysearch(asn1_info,1,Attributes) of
                  {value,{_,Info}} when is_list(Info) ->
                     Info;
                  _ ->
                     []
               end;
            _ ->
               []
         end
   end.


%%================================
%%  RSAPublicKey
%%================================
'enc_RSAPublicKey'(Val) ->
    'enc_RSAPublicKey'(Val, [<<48>>]).

'enc_RSAPublicKey'(Val, TagIn) ->
{_,Cindex1, Cindex2} = Val,

%%-------------------------------------------------
%% attribute modulus(1) with type INTEGER
%%-------------------------------------------------
   {EncBytes1,EncLen1} = ?RT_BER:encode_integer([], Cindex1, [<<2>>]),

%%-------------------------------------------------
%% attribute publicExponent(2) with type INTEGER
%%-------------------------------------------------
   {EncBytes2,EncLen2} = ?RT_BER:encode_integer([], Cindex2, [<<2>>]),

   BytesSoFar = [EncBytes1, EncBytes2],
LenSoFar = EncLen1 + EncLen2,
?RT_BER:encode_tags(TagIn, BytesSoFar, LenSoFar).


'dec_RSAPublicKey'(Tlv) ->
   'dec_RSAPublicKey'(Tlv, [16]).

'dec_RSAPublicKey'(Tlv, TagIn) ->
   %%-------------------------------------------------
   %% decode tag and length 
   %%-------------------------------------------------
Tlv1 = ?RT_BER:match_tags(Tlv,TagIn), 

%%-------------------------------------------------
%% attribute modulus(1) with type INTEGER
%%-------------------------------------------------
[V1|Tlv2] = Tlv1, 
Term1 = ?RT_BER:decode_integer(V1,[],[2]),

%%-------------------------------------------------
%% attribute publicExponent(2) with type INTEGER
%%-------------------------------------------------
[V2|Tlv3] = Tlv2, 
Term2 = ?RT_BER:decode_integer(V2,[],[2]),

case Tlv3 of
[] -> true;_ -> exit({error,{asn1, {unexpected,Tlv3}}}) % extra fields not allowed
end,
   {'RSAPublicKey', Term1, Term2}.



%%================================
%%  RSAPrivateKey
%%================================
'enc_RSAPrivateKey'(Val) ->
    'enc_RSAPrivateKey'(Val, [<<48>>]).

'enc_RSAPrivateKey'(Val, TagIn) ->
{_,Cindex1, Cindex2, Cindex3, Cindex4, Cindex5, Cindex6, Cindex7, Cindex8, Cindex9, Cindex10} = Val,

%%-------------------------------------------------
%% attribute version(1) with type INTEGER
%%-------------------------------------------------
   {EncBytes1,EncLen1} = ?RT_BER:encode_integer([], Cindex1, [{'two-prime',0},{multi,1}], [<<2>>]),

%%-------------------------------------------------
%% attribute modulus(2) with type INTEGER
%%-------------------------------------------------
   {EncBytes2,EncLen2} = ?RT_BER:encode_integer([], Cindex2, [<<2>>]),

%%-------------------------------------------------
%% attribute publicExponent(3) with type INTEGER
%%-------------------------------------------------
   {EncBytes3,EncLen3} = ?RT_BER:encode_integer([], Cindex3, [<<2>>]),

%%-------------------------------------------------
%% attribute privateExponent(4) with type INTEGER
%%-------------------------------------------------
   {EncBytes4,EncLen4} = ?RT_BER:encode_integer([], Cindex4, [<<2>>]),

%%-------------------------------------------------
%% attribute prime1(5) with type INTEGER
%%-------------------------------------------------
   {EncBytes5,EncLen5} = ?RT_BER:encode_integer([], Cindex5, [<<2>>]),

%%-------------------------------------------------
%% attribute prime2(6) with type INTEGER
%%-------------------------------------------------
   {EncBytes6,EncLen6} = ?RT_BER:encode_integer([], Cindex6, [<<2>>]),

%%-------------------------------------------------
%% attribute exponent1(7) with type INTEGER
%%-------------------------------------------------
   {EncBytes7,EncLen7} = ?RT_BER:encode_integer([], Cindex7, [<<2>>]),

%%-------------------------------------------------
%% attribute exponent2(8) with type INTEGER
%%-------------------------------------------------
   {EncBytes8,EncLen8} = ?RT_BER:encode_integer([], Cindex8, [<<2>>]),

%%-------------------------------------------------
%% attribute coefficient(9) with type INTEGER
%%-------------------------------------------------
   {EncBytes9,EncLen9} = ?RT_BER:encode_integer([], Cindex9, [<<2>>]),

%%-------------------------------------------------
%% attribute otherPrimeInfos(10)   External PKCS-1:OtherPrimeInfos OPTIONAL
%%-------------------------------------------------
   {EncBytes10,EncLen10} =  case Cindex10 of
         asn1_NOVALUE -> {<<>>,0};
         _ ->
            'enc_OtherPrimeInfos'(Cindex10, [<<48>>])
       end,

   BytesSoFar = [EncBytes1, EncBytes2, EncBytes3, EncBytes4, EncBytes5, EncBytes6, EncBytes7, EncBytes8, EncBytes9, EncBytes10],
LenSoFar = EncLen1 + EncLen2 + EncLen3 + EncLen4 + EncLen5 + EncLen6 + EncLen7 + EncLen8 + EncLen9 + EncLen10,
?RT_BER:encode_tags(TagIn, BytesSoFar, LenSoFar).


'dec_RSAPrivateKey'(Tlv) ->
   'dec_RSAPrivateKey'(Tlv, [16]).

'dec_RSAPrivateKey'(Tlv, TagIn) ->
   %%-------------------------------------------------
   %% decode tag and length 
   %%-------------------------------------------------
Tlv1 = ?RT_BER:match_tags(Tlv,TagIn), 

%%-------------------------------------------------
%% attribute version(1) with type INTEGER
%%-------------------------------------------------
[V1|Tlv2] = Tlv1, 
Term1 = ?RT_BER:decode_integer(V1,[],[{'two-prime',0},{multi,1}],[2]),

%%-------------------------------------------------
%% attribute modulus(2) with type INTEGER
%%-------------------------------------------------
[V2|Tlv3] = Tlv2, 
Term2 = ?RT_BER:decode_integer(V2,[],[2]),

%%-------------------------------------------------
%% attribute publicExponent(3) with type INTEGER
%%-------------------------------------------------
[V3|Tlv4] = Tlv3, 
Term3 = ?RT_BER:decode_integer(V3,[],[2]),

%%-------------------------------------------------
%% attribute privateExponent(4) with type INTEGER
%%-------------------------------------------------
[V4|Tlv5] = Tlv4, 
Term4 = ?RT_BER:decode_integer(V4,[],[2]),

%%-------------------------------------------------
%% attribute prime1(5) with type INTEGER
%%-------------------------------------------------
[V5|Tlv6] = Tlv5, 
Term5 = ?RT_BER:decode_integer(V5,[],[2]),

%%-------------------------------------------------
%% attribute prime2(6) with type INTEGER
%%-------------------------------------------------
[V6|Tlv7] = Tlv6, 
Term6 = ?RT_BER:decode_integer(V6,[],[2]),

%%-------------------------------------------------
%% attribute exponent1(7) with type INTEGER
%%-------------------------------------------------
[V7|Tlv8] = Tlv7, 
Term7 = ?RT_BER:decode_integer(V7,[],[2]),

%%-------------------------------------------------
%% attribute exponent2(8) with type INTEGER
%%-------------------------------------------------
[V8|Tlv9] = Tlv8, 
Term8 = ?RT_BER:decode_integer(V8,[],[2]),

%%-------------------------------------------------
%% attribute coefficient(9) with type INTEGER
%%-------------------------------------------------
[V9|Tlv10] = Tlv9, 
Term9 = ?RT_BER:decode_integer(V9,[],[2]),

%%-------------------------------------------------
%% attribute otherPrimeInfos(10)   External PKCS-1:OtherPrimeInfos OPTIONAL
%%-------------------------------------------------
{Term10,Tlv11} = case Tlv10 of
[{16,V10}|TempTlv11] ->
    {'dec_OtherPrimeInfos'(V10, []), TempTlv11};
    _ ->
        { asn1_NOVALUE, Tlv10}
end,

case Tlv11 of
[] -> true;_ -> exit({error,{asn1, {unexpected,Tlv11}}}) % extra fields not allowed
end,
   {'RSAPrivateKey', Term1, Term2, Term3, Term4, Term5, Term6, Term7, Term8, Term9, Term10}.



%%================================
%%  Version
%%================================
'enc_Version'(Val) ->
    'enc_Version'(Val, [<<2>>]).


'enc_Version'({'Version',Val}, TagIn) ->
   'enc_Version'(Val, TagIn);

'enc_Version'(Val, TagIn) ->
?RT_BER:encode_integer([], Val, [{'two-prime',0},{multi,1}], TagIn).


'dec_Version'(Tlv) ->
   'dec_Version'(Tlv, [2]).

'dec_Version'(Tlv, TagIn) ->
?RT_BER:decode_integer(Tlv,[],[{'two-prime',0},{multi,1}],TagIn).



%%================================
%%  OtherPrimeInfos
%%================================
'enc_OtherPrimeInfos'(Val) ->
    'enc_OtherPrimeInfos'(Val, [<<48>>]).


'enc_OtherPrimeInfos'({'OtherPrimeInfos',Val}, TagIn) ->
   'enc_OtherPrimeInfos'(Val, TagIn);

'enc_OtherPrimeInfos'(Val, TagIn) ->
   {EncBytes,EncLen} = 'enc_OtherPrimeInfos_components'(Val,[],0),
   ?RT_BER:encode_tags(TagIn, EncBytes, EncLen).

'enc_OtherPrimeInfos_components'([], AccBytes, AccLen) -> 
   {lists:reverse(AccBytes),AccLen};

'enc_OtherPrimeInfos_components'([H|T],AccBytes, AccLen) ->
   {EncBytes,EncLen} = 'enc_OtherPrimeInfo'(H, [<<48>>]),
   'enc_OtherPrimeInfos_components'(T,[EncBytes|AccBytes], AccLen + EncLen).



'dec_OtherPrimeInfos'(Tlv) ->
   'dec_OtherPrimeInfos'(Tlv, [16]).

'dec_OtherPrimeInfos'(Tlv, TagIn) ->
   %%-------------------------------------------------
   %% decode tag and length 
   %%-------------------------------------------------
Tlv1 = ?RT_BER:match_tags(Tlv,TagIn), 
['dec_OtherPrimeInfo'(V1, [16]) || V1 <- Tlv1].




%%================================
%%  OtherPrimeInfo
%%================================
'enc_OtherPrimeInfo'(Val) ->
    'enc_OtherPrimeInfo'(Val, [<<48>>]).

'enc_OtherPrimeInfo'(Val, TagIn) ->
{_,Cindex1, Cindex2, Cindex3} = Val,

%%-------------------------------------------------
%% attribute prime(1) with type INTEGER
%%-------------------------------------------------
   {EncBytes1,EncLen1} = ?RT_BER:encode_integer([], Cindex1, [<<2>>]),

%%-------------------------------------------------
%% attribute exponent(2) with type INTEGER
%%-------------------------------------------------
   {EncBytes2,EncLen2} = ?RT_BER:encode_integer([], Cindex2, [<<2>>]),

%%-------------------------------------------------
%% attribute coefficient(3) with type INTEGER
%%-------------------------------------------------
   {EncBytes3,EncLen3} = ?RT_BER:encode_integer([], Cindex3, [<<2>>]),

   BytesSoFar = [EncBytes1, EncBytes2, EncBytes3],
LenSoFar = EncLen1 + EncLen2 + EncLen3,
?RT_BER:encode_tags(TagIn, BytesSoFar, LenSoFar).


'dec_OtherPrimeInfo'(Tlv) ->
   'dec_OtherPrimeInfo'(Tlv, [16]).

'dec_OtherPrimeInfo'(Tlv, TagIn) ->
   %%-------------------------------------------------
   %% decode tag and length 
   %%-------------------------------------------------
Tlv1 = ?RT_BER:match_tags(Tlv,TagIn), 

%%-------------------------------------------------
%% attribute prime(1) with type INTEGER
%%-------------------------------------------------
[V1|Tlv2] = Tlv1, 
Term1 = ?RT_BER:decode_integer(V1,[],[2]),

%%-------------------------------------------------
%% attribute exponent(2) with type INTEGER
%%-------------------------------------------------
[V2|Tlv3] = Tlv2, 
Term2 = ?RT_BER:decode_integer(V2,[],[2]),

%%-------------------------------------------------
%% attribute coefficient(3) with type INTEGER
%%-------------------------------------------------
[V3|Tlv4] = Tlv3, 
Term3 = ?RT_BER:decode_integer(V3,[],[2]),

case Tlv4 of
[] -> true;_ -> exit({error,{asn1, {unexpected,Tlv4}}}) % extra fields not allowed
end,
   {'OtherPrimeInfo', Term1, Term2, Term3}.



%%================================
%%  Algorithm
%%================================
'enc_Algorithm'(Val) ->
    'enc_Algorithm'(Val, [<<48>>]).

'enc_Algorithm'(Val, TagIn) ->
{_,Cindex1, Cindex2} = Val,

%%-------------------------------------------------
%% attribute algorithm(1) with type OBJECT IDENTIFIER
%%-------------------------------------------------
   {EncBytes1,EncLen1} = ?RT_BER:encode_object_identifier(Cindex1, [<<6>>]),

%%-------------------------------------------------
%% attribute parameters(2) with type ASN1_OPEN_TYPE OPTIONAL
%%-------------------------------------------------
   {EncBytes2,EncLen2} =  case Cindex2 of
         asn1_NOVALUE -> {<<>>,0};
         _ ->
            ?RT_BER:encode_open_type(Cindex2, [])
       end,

   BytesSoFar = [EncBytes1, EncBytes2],
LenSoFar = EncLen1 + EncLen2,
?RT_BER:encode_tags(TagIn, BytesSoFar, LenSoFar).


'dec_Algorithm'(Tlv) ->
   'dec_Algorithm'(Tlv, [16]).

'dec_Algorithm'(Tlv, TagIn) ->
   %%-------------------------------------------------
   %% decode tag and length 
   %%-------------------------------------------------
Tlv1 = ?RT_BER:match_tags(Tlv,TagIn), 

%%-------------------------------------------------
%% attribute algorithm(1) with type OBJECT IDENTIFIER
%%-------------------------------------------------
[V1|Tlv2] = Tlv1, 
Term1 = ?RT_BER:decode_object_identifier(V1,[6]),

%%-------------------------------------------------
%% attribute parameters(2) with type ASN1_OPEN_TYPE OPTIONAL
%%-------------------------------------------------
{Term2,Tlv3} = case Tlv2 of
[V2|TempTlv3] ->
    {?RT_BER:decode_open_type_as_binary(V2,[]), TempTlv3};
    _ ->
        { asn1_NOVALUE, Tlv2}
end,

case Tlv3 of
[] -> true;_ -> exit({error,{asn1, {unexpected,Tlv3}}}) % extra fields not allowed
end,
   {'Algorithm', Term1, Term2}.



%%================================
%%  AlgorithmNull
%%================================
'enc_AlgorithmNull'(Val) ->
    'enc_AlgorithmNull'(Val, [<<48>>]).

'enc_AlgorithmNull'(Val, TagIn) ->
{_,Cindex1, Cindex2} = Val,

%%-------------------------------------------------
%% attribute algorithm(1) with type OBJECT IDENTIFIER
%%-------------------------------------------------
   {EncBytes1,EncLen1} = ?RT_BER:encode_object_identifier(Cindex1, [<<6>>]),

%%-------------------------------------------------
%% attribute parameters(2) with type NULL
%%-------------------------------------------------
   {EncBytes2,EncLen2} = ?RT_BER:encode_null(Cindex2, [<<5>>]),

   BytesSoFar = [EncBytes1, EncBytes2],
LenSoFar = EncLen1 + EncLen2,
?RT_BER:encode_tags(TagIn, BytesSoFar, LenSoFar).


'dec_AlgorithmNull'(Tlv) ->
   'dec_AlgorithmNull'(Tlv, [16]).

'dec_AlgorithmNull'(Tlv, TagIn) ->
   %%-------------------------------------------------
   %% decode tag and length 
   %%-------------------------------------------------
Tlv1 = ?RT_BER:match_tags(Tlv,TagIn), 

%%-------------------------------------------------
%% attribute algorithm(1) with type OBJECT IDENTIFIER
%%-------------------------------------------------
[V1|Tlv2] = Tlv1, 
Term1 = ?RT_BER:decode_object_identifier(V1,[6]),

%%-------------------------------------------------
%% attribute parameters(2) with type NULL
%%-------------------------------------------------
[V2|Tlv3] = Tlv2, 
Term2 = ?RT_BER:decode_null(V2,[5]),

case Tlv3 of
[] -> true;_ -> exit({error,{asn1, {unexpected,Tlv3}}}) % extra fields not allowed
end,
   {'AlgorithmNull', Term1, Term2}.



%%================================
%%  RSASSA-PSS-params
%%================================
'enc_RSASSA-PSS-params'(Val) ->
    'enc_RSASSA-PSS-params'(Val, [<<48>>]).

'enc_RSASSA-PSS-params'(Val, TagIn) ->
{_,Cindex1, Cindex2, Cindex3, Cindex4} = Val,

%%-------------------------------------------------
%% attribute hashAlgorithm(1)   External PKCS-1:Algorithm
%%-------------------------------------------------
   {EncBytes1,EncLen1} = 'enc_Algorithm'(Cindex1, [<<48>>,<<160>>]),

%%-------------------------------------------------
%% attribute maskGenAlgorithm(2)   External PKCS-1:Algorithm
%%-------------------------------------------------
   {EncBytes2,EncLen2} = 'enc_Algorithm'(Cindex2, [<<48>>,<<161>>]),

%%-------------------------------------------------
%% attribute saltLength(3) with type INTEGER DEFAULT = 20
%%-------------------------------------------------
   {EncBytes3,EncLen3} =  case catch asn1rt_check:check_int(20, Cindex3, []) of
            true -> {[],0};
         _ ->
            ?RT_BER:encode_integer([], Cindex3, [<<2>>,<<162>>])
       end,

%%-------------------------------------------------
%% attribute trailerField(4) with type INTEGER DEFAULT = 1
%%-------------------------------------------------
   {EncBytes4,EncLen4} =  case catch asn1rt_check:check_int(1, Cindex4, [{trailerFieldBC,1}]) of
            true -> {[],0};
         _ ->
            ?RT_BER:encode_integer([], Cindex4, [{trailerFieldBC,1}], [<<2>>,<<163>>])
       end,

   BytesSoFar = [EncBytes1, EncBytes2, EncBytes3, EncBytes4],
LenSoFar = EncLen1 + EncLen2 + EncLen3 + EncLen4,
?RT_BER:encode_tags(TagIn, BytesSoFar, LenSoFar).


'dec_RSASSA-PSS-params'(Tlv) ->
   'dec_RSASSA-PSS-params'(Tlv, [16]).

'dec_RSASSA-PSS-params'(Tlv, TagIn) ->
   %%-------------------------------------------------
   %% decode tag and length 
   %%-------------------------------------------------
Tlv1 = ?RT_BER:match_tags(Tlv,TagIn), 

%%-------------------------------------------------
%% attribute hashAlgorithm(1)   External PKCS-1:Algorithm
%%-------------------------------------------------
[V1|Tlv2] = Tlv1, 
Term1 = 'dec_Algorithm'(V1, [131072,16]),

%%-------------------------------------------------
%% attribute maskGenAlgorithm(2)   External PKCS-1:Algorithm
%%-------------------------------------------------
[V2|Tlv3] = Tlv2, 
Term2 = 'dec_Algorithm'(V2, [131073,16]),

%%-------------------------------------------------
%% attribute saltLength(3) with type INTEGER DEFAULT = 20
%%-------------------------------------------------
{Term3,Tlv4} = case Tlv3 of
[{131074,V3}|TempTlv4] ->
    {?RT_BER:decode_integer(V3,[],[2]), TempTlv4};
    _ ->
        {20,Tlv3}
end,

%%-------------------------------------------------
%% attribute trailerField(4) with type INTEGER DEFAULT = 1
%%-------------------------------------------------
{Term4,Tlv5} = case Tlv4 of
[{131075,V4}|TempTlv5] ->
    {?RT_BER:decode_integer(V4,[],[{trailerFieldBC,1}],[2]), TempTlv5};
    _ ->
        {1,Tlv4}
end,

case Tlv5 of
[] -> true;_ -> exit({error,{asn1, {unexpected,Tlv5}}}) % extra fields not allowed
end,
   {'RSASSA-PSS-params', Term1, Term2, Term3, Term4}.



%%================================
%%  TrailerField
%%================================
'enc_TrailerField'(Val) ->
    'enc_TrailerField'(Val, [<<2>>]).


'enc_TrailerField'({'TrailerField',Val}, TagIn) ->
   'enc_TrailerField'(Val, TagIn);

'enc_TrailerField'(Val, TagIn) ->
?RT_BER:encode_integer([], Val, [{trailerFieldBC,1}], TagIn).


'dec_TrailerField'(Tlv) ->
   'dec_TrailerField'(Tlv, [2]).

'dec_TrailerField'(Tlv, TagIn) ->
?RT_BER:decode_integer(Tlv,[],[{trailerFieldBC,1}],TagIn).



%%================================
%%  DigestInfo
%%================================
'enc_DigestInfo'(Val) ->
    'enc_DigestInfo'(Val, [<<48>>]).

'enc_DigestInfo'(Val, TagIn) ->
{_,Cindex1, Cindex2} = Val,

%%-------------------------------------------------
%% attribute digestAlgorithm(1)   External PKCS-1:Algorithm
%%-------------------------------------------------
   {EncBytes1,EncLen1} = 'enc_Algorithm'(Cindex1, [<<48>>]),

%%-------------------------------------------------
%% attribute digest(2) with type OCTET STRING
%%-------------------------------------------------
   {EncBytes2,EncLen2} = ?RT_BER:encode_octet_string([], Cindex2, [<<4>>]),

   BytesSoFar = [EncBytes1, EncBytes2],
LenSoFar = EncLen1 + EncLen2,
?RT_BER:encode_tags(TagIn, BytesSoFar, LenSoFar).


'dec_DigestInfo'(Tlv) ->
   'dec_DigestInfo'(Tlv, [16]).

'dec_DigestInfo'(Tlv, TagIn) ->
   %%-------------------------------------------------
   %% decode tag and length 
   %%-------------------------------------------------
Tlv1 = ?RT_BER:match_tags(Tlv,TagIn), 

%%-------------------------------------------------
%% attribute digestAlgorithm(1)   External PKCS-1:Algorithm
%%-------------------------------------------------
[V1|Tlv2] = Tlv1, 
Term1 = 'dec_Algorithm'(V1, [16]),

%%-------------------------------------------------
%% attribute digest(2) with type OCTET STRING
%%-------------------------------------------------
[V2|Tlv3] = Tlv2, 
Term2 = ?RT_BER:decode_octet_string(V2,[],[4]),

case Tlv3 of
[] -> true;_ -> exit({error,{asn1, {unexpected,Tlv3}}}) % extra fields not allowed
end,
   {'DigestInfo', Term1, Term2}.



%%================================
%%  DigestInfoNull
%%================================
'enc_DigestInfoNull'(Val) ->
    'enc_DigestInfoNull'(Val, [<<48>>]).

'enc_DigestInfoNull'(Val, TagIn) ->
{_,Cindex1, Cindex2} = Val,

%%-------------------------------------------------
%% attribute digestAlgorithm(1)   External PKCS-1:AlgorithmNull
%%-------------------------------------------------
   {EncBytes1,EncLen1} = 'enc_AlgorithmNull'(Cindex1, [<<48>>]),

%%-------------------------------------------------
%% attribute digest(2) with type OCTET STRING
%%-------------------------------------------------
   {EncBytes2,EncLen2} = ?RT_BER:encode_octet_string([], Cindex2, [<<4>>]),

   BytesSoFar = [EncBytes1, EncBytes2],
LenSoFar = EncLen1 + EncLen2,
?RT_BER:encode_tags(TagIn, BytesSoFar, LenSoFar).


'dec_DigestInfoNull'(Tlv) ->
   'dec_DigestInfoNull'(Tlv, [16]).

'dec_DigestInfoNull'(Tlv, TagIn) ->
   %%-------------------------------------------------
   %% decode tag and length 
   %%-------------------------------------------------
Tlv1 = ?RT_BER:match_tags(Tlv,TagIn), 

%%-------------------------------------------------
%% attribute digestAlgorithm(1)   External PKCS-1:AlgorithmNull
%%-------------------------------------------------
[V1|Tlv2] = Tlv1, 
Term1 = 'dec_AlgorithmNull'(V1, [16]),

%%-------------------------------------------------
%% attribute digest(2) with type OCTET STRING
%%-------------------------------------------------
[V2|Tlv3] = Tlv2, 
Term2 = ?RT_BER:decode_octet_string(V2,[],[4]),

case Tlv3 of
[] -> true;_ -> exit({error,{asn1, {unexpected,Tlv3}}}) % extra fields not allowed
end,
   {'DigestInfoNull', Term1, Term2}.

'pkcs-1'() ->
{1,2,840,113549,1,1}.

'rsaEncryption'() ->
{1,2,840,113549,1,1,1}.

'id-RSAES-OAEP'() ->
{1,2,840,113549,1,1,7}.

'id-pSpecified'() ->
{1,2,840,113549,1,1,9}.

'id-RSASSA-PSS'() ->
{1,2,840,113549,1,1,10}.

'md2WithRSAEncryption'() ->
{1,2,840,113549,1,1,2}.

'md5WithRSAEncryption'() ->
{1,2,840,113549,1,1,4}.

'sha1WithRSAEncryption'() ->
{1,2,840,113549,1,1,5}.

'sha256WithRSAEncryption'() ->
{1,2,840,113549,1,1,11}.

'sha384WithRSAEncryption'() ->
{1,2,840,113549,1,1,12}.

'sha512WithRSAEncryption'() ->
{1,2,840,113549,1,1,13}.

'id-sha1'() ->
{1,3,14,3,2,26}.

'id-md2'() ->
{1,2,840,113549,2,2}.

'id-md5'() ->
{1,2,840,113549,2,5}.

'id-mgf1'() ->
{1,2,840,113549,1,1,8}.
