%%%-------------------------------------------------------------------
%%% File    : dot.erl
%%% Author  : Per Gustafsson <pergu@it.uu.se>
%%% Description : 
%%%
%%% Created : 25 Nov 2004 by Per Gustafsson <pergu@it.uu.se>
%%%-------------------------------------------------------------------
-module(hipe_dot).

-export([translate_digraph/3, translate_digraph/5, 
	 translate_list/3, translate_list/4,translate_list/5]).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% This module creates .dot representations of graphs from their
%% Erlang representations. There are two different forms of Erlang
%% representations that the module accepts, digraphs and lists of two
%% tuples (where each tuple represent a directed edge).
%%
%% The functions also require a FileName and a name of the graph.  The
%% filename is the name of the resulting .dot file the GraphName is
%% pretty much useless
%%
%% The resulting .dot reprsentation will be stored in the flie FileName
%%
%% Interfaces:
%%
%% translate_list(Graph::[{Node,Node}], FileName::string(),
%%                GraphName::string()) -> ok
%%
%%translate_list(Graph::[{Node,Node}], FileName::string(),
%%                GraphName::string(), Options::[option] ) -> ok
%%
%% translate_list(Graph::[{Node::term(),Node::term()}], FileName::string(),
%%                GraphName::string(), Fun::fun(term()->string()),
%%                Options::[option]) -> ok
%%
%% The optional Fun argument dictates how the node/names should be output
%%
%% The option list can be used to pass options to .dot to decide how
%% different nodes and edges should be displayed.
%%
%% translate_digraph has the same interface as translate_list except
%% it takes a digraph rather than a list
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 


translate_digraph(G, FileName, GName) ->
  translate_digraph(G, FileName, GName, 
		    fun(X) -> io_lib:format("~p", [X]) end, []).

translate_digraph(G, FileName, GName, Fun, Opts) ->
  Edges = [digraph:edge(G,X) || X <- digraph:edges(G)],
  EdgeList = [{X,Y}|| {_,X,Y,_} <- Edges],
  translate_list(EdgeList, FileName, GName, Fun, Opts).

translate_list(List, FileName, GName) ->
  translate_list(List, FileName, GName, fun(X) -> lists:flatten(io_lib:format("~p", [X])) end, []).

translate_list(List, FileName, GName, Opts) ->
  translate_list(List, FileName, GName, fun(X) -> lists:flatten(io_lib:format("~p", [X])) end, Opts).

translate_list(List, FileName, GName, Fun, Opts) ->
  {NodeList1, NodeList2} = lists:unzip(List),
  NodeList = NodeList1 ++ NodeList2,
  NodeSet = ordsets:from_list(NodeList),
  Start = ["digraph ",GName ," {"],
  VertexList = 
    [node_format(Opts, Fun, V) ||V <- NodeSet],
  End = ["graph [",GName,"=",GName,"]}"],
  EdgeList = [edge_format(Opts,Fun,X,Y)||{X,Y}<-List],
  String = [Start, VertexList, EdgeList, End],
  %%io:format("~p~n", [lists:flatten([String])]),
  file:write_file(FileName, list_to_binary(String)).
  
node_format(Opt, Fun, V) ->
  OptText = nodeoptions(Opt, Fun ,V),
  Tmp = io_lib:format("~p",[Fun(V)]),
  String = lists:flatten(Tmp),
  %% io:format("~p", [String]),
  {Width, Heigth} = calc_dim(String),
  W = ((Width div 7) + 1) * 0.55,
  H = Heigth * 0.4,
  SL = io_lib:format("~f",[W]), 
  SH = io_lib:format("~f",[H]),
  [String, " [width=",SL," heigth=", SH, " ", OptText,"];\n"].

edge_format(Opt, Fun, V1, V2) ->
  OptText = 
    case  lists:flatten(edgeoptions(Opt, Fun ,V1, V2)) of
      [] ->
	[];
      [_|X] ->
	X
    end,
  String = [io_lib:format("~p",[Fun(V1)]), " -> ",
	    io_lib:format("~p",[Fun(V2)])],
  [String," [", OptText,"];\n"].
  
calc_dim(String) ->
  calc_dim(String, 1, 0 ,0).
		     
calc_dim([$\\,$n|T], H, TmpW, MaxW) ->
  if TmpW > MaxW -> calc_dim(T, H+1, 0, TmpW);
     true -> calc_dim(T, H+1, 0, MaxW)
  end;
calc_dim([_|T], H, TmpW, MaxW) ->
  calc_dim(T, H, TmpW+1, MaxW);
calc_dim([], H, TmpW, MaxW) ->
  if TmpW > MaxW -> {TmpW, H};
     true -> {MaxW, H}
  end.
      

edgeoptions([{all_edges,{OptName, OptVal}}|T], Fun, V1, V2) -> 
   case legal_edgeoption(OptName) of
     true ->
       [io_lib:format(",~p=~p ",[OptName, OptVal])|edgeoptions(T, Fun, V1, V2)]
     %% false ->
     %%  edgeoptions(T, Fun, V1,V2)
   end;
edgeoptions([{N1,N2,{OptName, OptVal}}|T], Fun, V1, V2) ->
  case %% legal_edgeoption(OptName) andalso
       Fun(N1) == Fun(V1) andalso Fun(N2) == Fun(V2) of 
    true ->
      [io_lib:format(",~p=~p ",[OptName, OptVal])|edgeoptions(T, Fun,V1,V2)];
    false ->
      edgeoptions(T, Fun, V1, V2)
  end;
edgeoptions([_|T], Fun, V1, V2) ->
  edgeoptions(T, Fun, V1, V2);
edgeoptions([], _, _, _) ->
  [].

nodeoptions([{all_nodes,{OptName, OptVal}}|T], Fun, V) -> 
  case legal_nodeoption(OptName) of
    true ->
      [io_lib:format(",~p=~p ",[OptName, OptVal])|nodeoptions(T, Fun, V)];
    false ->
      nodeoptions(T, Fun, V)
  end;
nodeoptions([{Node,{OptName, OptVal}}|T], Fun, V) -> 
  case Fun(Node) == Fun(V) andalso legal_nodeoption(OptName) of
    true ->
      [io_lib:format("~p=~p ",[OptName, OptVal])|nodeoptions(T, Fun, V)];
    false ->
      nodeoptions(T, Fun, V)
  end;
nodeoptions([_|T], Fun, V) ->
  nodeoptions(T, Fun, V);
nodeoptions([], _Fun, _V) ->
  [].

legal_nodeoption(bottomlabel) -> true;
legal_nodeoption(color) -> true;
legal_nodeoption(comment) -> true;
legal_nodeoption(distortion) -> true;
legal_nodeoption(fillcolor) -> true;
legal_nodeoption(fixedsize) -> true;  
legal_nodeoption(fontcolor) -> true;
legal_nodeoption(fontname) -> true;
legal_nodeoption(fontsize) -> true;
legal_nodeoption(group) -> true;
legal_nodeoption(height) -> true;
legal_nodeoption(label) -> true;
legal_nodeoption(layer) -> true;
legal_nodeoption(orientation) -> true;
legal_nodeoption(peripheries) -> true;
legal_nodeoption(regular) -> true;
legal_nodeoption(shape) -> true;
legal_nodeoption(shapefile) -> true;
legal_nodeoption(sides) -> true;
legal_nodeoption(skew) -> true;
legal_nodeoption(style) -> true;
legal_nodeoption(toplabel) -> true;
legal_nodeoption('URL') -> true;
legal_nodeoption(z) -> true;
legal_nodeoption(_) -> false.
  
legal_edgeoption(_) -> true.
  


