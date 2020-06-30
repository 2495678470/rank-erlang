
%% 避免头文件多重包含
-ifndef(__RANK__).
-define(__RANK__, 0).



-define(ETS_RANK_KEY,   ets_rank_key).  % 唯一ID和排行榜key值的映射关系 {PlayerId, Key}
-define(ETS_RANK_,   ets_rank_).        % 排行榜分桶排序表
-define(BUCKET_SIZE,        10).        % 桶大小
-define(BUCKET_NUM,         10).        % 桶数量

% 排行榜KEY
-record(key, {
	mainval, 	% 排行主要依据参数
	unixstamp, 	% 排行次要依据参数1 上榜时间戳
	id			% 排行次要依据参数2 全服唯一ID
}).
% 唯一ID和Key值的映射结构
-record(ets_rank_key, {id, key}).
% 排行榜信息结构
-record(ets_rank, {
	key,
	val, 				% 排行榜附加信息
	is_dirty = false	% 是否脏数据，脏数据定时存库
}).

-define(SORT_RULE(Pos), case Pos of
							#key.mainval -> -1;
							#key.unixstamp -> 1;
							#key.id -> -1
						end).







-endif.  %% __AOI__
