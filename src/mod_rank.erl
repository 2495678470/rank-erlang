%%%-------------------------------------------------------------------
%%% @author ningwenbin
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%     全服实时排行榜
%%%     需要支持每秒更新1000条数据，实时全服排名，例如：1000000名玩家，需要读取第999999排名的玩家数据
%%%     实测： 系统环境 win10 64位专业版，cpu i5-7400 4核4线程 3.00GHz，16G ddr4 2133hz运行内存
%%%            单条数据798KB，实测100000次/秒
%%%     采用桶排序，按主要排名参数值进行分桶
%%%     缺陷：当某个桶容量占总量比越来越大时，这个桶的效率会成为整个排行榜的短板，没有动态把大桶切分更细粒度的桶的机制
%%%     继续优化方向： 1、排行榜更新进程由单进程 —> 1个监控管理进程派生桶数量的slave进程，每个slave进程负责单个桶的更新操作；
%%%                    2、slave跟数据库交护的批量读写，要按照桶数量去划分操作时间段（以分为单位），充分利用数据库端口资源
%%% @end
%%% Created : 23. 3月 2020 15:18
%%%-------------------------------------------------------------------
-module(mod_rank).
-author("ningwenbin").

-behaviour(gen_server).
-include("game_rank.hrl").

%% API
-export([
    start_link/0,
    enter/4,
    get_rank_by_id/1,
    get_rankinfo_by_id/1,
    get_rank_list/1,
    get_rank_list/2,
    get_key/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {}).



%%%===================================================================
%%% API
%%%===================================================================



start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).
enter(Id, UnixStamp, MainVal, Others) ->
    RankInfo = #ets_rank{key = pack_key(MainVal, UnixStamp, Id), val = Others},
    gen_server:cast(?MODULE, {enter, RankInfo}).

%% @doc 获取前X名信息
%% get_rank_list(LimitRank) -> [RankInfo]
%%      RankInfo   =  #ets_rank{}
get_rank_list(LimitRank) ->
    get_rank_list(0, LimitRank).
%%    Fun = fun(Index, {LRank, Acc}) ->
%%        ETS = ets_name(Index),
%%        case LRank > ets:info(ETS, size) of
%%            true ->
%%                {false, {LRank - ets:info(ETS, size), Acc ++ ets:tab2list(ETS)}};
%%            false ->
%%                List =
%%                    case ets:match_object(ETS, #ets_rank{_ = '_'}, LRank) of
%%                        '$end_of_table' ->
%%                            [];
%%                        {ObjList, _} ->
%%                            ObjList
%%                    end,
%%                {true, {0, Acc ++ List}}
%%        end
%%        end,
%%    {_R, RankList} = util:limit_foldl(Fun, lists:seq(1, ?BUCKET_NUM), {LimitRank, []}),
%%    RankList.

%% @doc 获取排名段信息
%% get_rank_list(MinRank, MaxRank) -> [RankInfo]
%%      RankInfo   =  #ets_rank{}
get_rank_list(MinRank, MaxRank) ->
    Fun = fun(Index, {CurRank, Acc}) ->
        ETS = ets_name(Index),
        Rank = CurRank + ets:info(ETS, size),
        case Rank >= MinRank of
            true ->
                case Rank < MaxRank of
                    true ->
                        {false, {Rank, Acc ++ ets:tab2list(ETS)}};
                    false ->
                        List0 =
                            case ets:match_object(ETS, #ets_rank{_ = '_'}, ets:info(ETS, size) - (Rank - MaxRank)) of
                                '$end_of_table' ->
                                    [];
                                {ObjList, _} ->
                                    ObjList
                            end,
                        List =
                            case MinRank > CurRank of
                                true ->
                                    lists:nthtail(MinRank-CurRank-1, List0);
                                false ->
                                    List0
                            end,
                        {true, {MaxRank, Acc ++ List}}
                end;
            false ->
                {false, {Rank, Acc}}
        end
          end,
    {_R, RankList} = limit_foldl(Fun, lists:seq(1, ?BUCKET_NUM), {0, []}),
    RankList.

%% @doc 通过唯一ID获取排名
%% get_rank_by_id(Id) -> 0 | Rank.
%%      0       =  表示未上榜
%%      Rank    =  排名.
get_rank_by_id(Id) ->
    case get_key(Id) of
        null ->
            0;
        Key ->

            SelfIndex = allot(mainval(Key)),
            Fun = fun(Index, CurRank) ->
                ETS = ets_name(Index),
                case SelfIndex > Index of
                    true ->
                        {false, ets:info(ETS, size) + CurRank};
                    false ->
                        Pos = get_ele_pos_by_key(Key, ets:tab2list(ETS), #ets_rank.key),
                        {true, Pos + CurRank}
                end
                  end,
            limit_foldl(Fun, lists:seq(1, ?BUCKET_NUM), 0)
    end.

%% @doc 通过唯一ID获取排行榜信息
%% get_rankinfo_by_id(Id) -> null | RankInfo.
%%      null        =  表示没找到信息
%%      RankInfo    =  排行榜信息
get_rankinfo_by_id(Id) ->
    case get_key(Id) of
        null ->
            null;
        Key ->

            case ets:lookup(ets_name(Key), Key) of
                [RankInfo] ->
                    RankInfo;
                [] ->
                    []
            end
    end.


ets_name(Index) when is_integer(Index) ->
    erlang:list_to_atom(lists:concat([?ETS_RANK_, Index]));
ets_name(Key) ->
    ets_name(allot(mainval(Key))).

allot(MainVal) ->
    case MainVal div ?BUCKET_SIZE of
        N when N >= ?BUCKET_NUM ->
            ?BUCKET_NUM;
        N2 ->
            N2+1
    end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    ets:new(?ETS_RANK_KEY, [public, named_table, set, {keypos, #ets_rank_key.id}, {read_concurrency, true}]),

    lists:foreach(fun(Index) ->
        ets:new(ets_name(Index), [public, named_table, ordered_set, {keypos, #ets_rank.key}, {read_concurrency, true}])
        end, lists:seq(1, ?BUCKET_NUM)),

    {ok, #state{}}.

handle_call(Request, _From, State = #state{}) ->
    try
        Reply = do_call(Request),
        {reply, Reply, State}
    catch
        Type:Err  ->
            io:format("Type:~p , Err:~p~n get_stacktrace:~p~n",[Type, Err, erlang:get_stacktrace()]),
            {reply, {error, ?MODULE}, State}
    end.

handle_cast(Request, State = #state{}) ->
    try
        do_cast(Request)
    catch
        _:skip ->
            skip;
        Type:Err  ->
            io:format("Type:~p , Err:~p~n get_stacktrace:~p~n",[Type, Err, erlang:get_stacktrace()])
    end,
    {noreply, State}.

handle_info(Info, State = #state{}) ->
    try
        do_info(Info)
    catch
        Type:Err  ->
            io:format("Type:~p , Err:~p~n get_stacktrace:~p~n",[Type, Err, erlang:get_stacktrace()])
    end,
    {noreply, State}.

terminate(_Reason, _State = #state{}) ->
    save_db(),
    ok.

code_change(_OldVsn, State = #state{}, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
do_call(Msg) ->
    ok.


do_cast({enter, RankInfo}) ->
    update_info(RankInfo),
    ok.

do_info(Msg) ->
    ok.

get_key(Id) ->
    case ets:lookup(?ETS_RANK_KEY, Id) of
        [] ->
            null;
        [#ets_rank_key{id = Id, key = Key}] ->
            Key
    end.

update_info(RankInfo) ->
    NewKey = RankInfo#ets_rank.key,
    OldKey = get_key(id(RankInfo)),
    case OldKey /= NewKey andalso OldKey /= null of
        true ->
            ets:delete(ets_name(OldKey), OldKey);
        false ->
            skip
    end,
    FinalInfo = RankInfo#ets_rank{
        is_dirty = 1
    },
    ets:insert(ets_name(NewKey), FinalInfo),
    ets:insert(?ETS_RANK_KEY, #ets_rank_key{id = id(RankInfo), key = NewKey}).

pack_key(MainVal, UnixStamp, Id) ->
    #key{
        mainval = MainVal * ?SORT_RULE(#key.mainval),
        unixstamp = UnixStamp * ?SORT_RULE(#key.unixstamp),
        id = Id * ?SORT_RULE(#key.id)
    }.


id(RankInfo) when is_record(RankInfo, ets_rank) ->
    id(RankInfo#ets_rank.key);
id(Key) ->
    element(#key.id, Key) * ?SORT_RULE(#key.id).

mainval(RankInfo) when is_record(RankInfo, ets_rank) ->
    mainval(RankInfo#ets_rank.key);
mainval(Key) ->
    element(#key.mainval, Key) * ?SORT_RULE(#key.mainval).

unixstamp(RankInfo) when is_record(RankInfo, ets_rank) ->
    unixstamp(RankInfo#ets_rank.key);
unixstamp(Key) ->
    element(#key.unixstamp, Key) * ?SORT_RULE(#key.unixstamp).

save_db() ->
    ok.


get_ele_pos_by_key(Key, List, Index) ->
    get_ele_pos_by_key_2(Key, List, Index, 1).


get_ele_pos_by_key_2(Key, [], Index, _Pos) ->
    -1;
get_ele_pos_by_key_2(Key, [CurCmpEle | T], Index, Pos) ->
    case Key =:= element(Index, CurCmpEle) of
        true ->
            Pos;
        false ->
            get_ele_pos_by_key_2(Key, T, Index, Pos + 1)
    end.

%%
%% @doc 有限遍历列表
%%      F = function() -> {true,Acc}|{false,Acc}
%%      返回true则遍历停止，false继续
limit_foldl(F, List, Acc) ->
    limit_foldl_1(F, List, {false, Acc}).
limit_foldl_1(_F, [], {_IsEnd,Acc}) ->
    Acc;
limit_foldl_1(_F, _List, {true, Acc}) ->
    Acc;
limit_foldl_1(F, [In|List], {false, Acc}) ->
    limit_foldl_1(F, List, F(In, Acc)).