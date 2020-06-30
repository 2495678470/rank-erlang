# rank-erlang
This is a plugin for a large leaderboard developed with erlang. It supports 1,000 updates per second and supports real-time ranking.

这是某一款游戏服务器的全服排行榜设计框架，支持每秒1000次的更新频率，支持实时排名。

插入或更新排行榜接口： enter(Id, UnixStamp, MainVal, Others) -> ok. Id = 全服唯一ID，整型 UnixStamp = 时间戳，用以按时间先后排序 MainVal = 排行榜排序主要参数值

通过全服唯一ID获取排名： get_rank_by_id(Id) -> Rank. Id = 全服唯一ID，整型 Rank = 排名，整型

获取指定范围的排名信息： get_rank_list(MinRank, MaxRank) -> [RankInfo]. MinRank = 最小排名 MaxRank = 最大排名 RankInfo = #ets_rank{} 排行榜数据

通过唯一ID获取排行榜信息： get_rankinfo_by_id(Id) -> null | RankInfo. RankInfo = #ets_rank{} 排行榜数据
