import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/mappers.dart";
import "../../data/models/track.dart";
import "../../data/origin_service.dart";
import "../../origin_sdk/kuwo/kuwo_api.dart";
import "../../origin_sdk/origin_types.dart";

/// 广场榜单卡定义（key, 展示名）：热歌榜 = 唯一 SSR 真榜；其余为主题卡
/// （酷我多榜单接口已封死，实测结论见 kuwo_api.hotChart 注释）
const plazaChartDefs = <(String, String)>[
  ("hot", "热歌榜"),
  ("theme:经典老歌", "经典老歌"),
  ("theme:网络热歌", "网络热歌"),
  ("theme:伤感情歌", "伤感情歌"),
];

/// 单张榜单卡数据（keepAlive：进详情页/回广场不重拉；单卡失败只降级该卡）
final kuwoChartProvider = FutureProvider.family<KuwoChart, String>((ref, key) async {
  final api = kuwoApi;
  if (key == "hot") {
    if (api is KuwoApi) return api.hotChart();
    // 测试/其它 OriginService 兜底：hotSongs → search
    final items = await api.hotSongs();
    if (items.isNotEmpty) {
      return KuwoChart(
        key: key,
        name: "热歌榜",
        hits: [
          for (final item in items)
            KuwoHotHit(name: item.name, artist: item.author, item: item),
        ],
      );
    }
    final resp = await api.search(
      const SearchParams(keyword: "热门歌曲", page: 1, pageSize: 10),
    );
    return KuwoChart(
      key: key,
      name: "热歌榜",
      hits: [
        for (final item in resp.data)
          KuwoHotHit(name: item.name, artist: item.author, item: item),
      ],
    );
  }
  final keyword = key.substring("theme:".length);
  if (api is KuwoApi) return api.themeChart(keyword);
  final resp = await api.search(
    SearchParams(keyword: keyword, page: 1, pageSize: 30),
  );
  return KuwoChart(
    key: key,
    name: keyword,
    hits: [
      for (final item in resp.data)
        KuwoHotHit(name: item.name, artist: item.author, item: item),
    ],
  );
});

/// 点播榜单条目：SSR 已带 item 直接用；否则按标题+歌手搜索并做匹配筛选
Future<Track?> resolveKuwoHotHit(KuwoHotHit hit) async {
  if (hit.item != null) return hit.item!.toTrack();
  try {
    var candidates = await kuwoApi.search(
      SearchParams(
        keyword: "${hit.name} ${hit.artist}".trim(),
        page: 1,
        pageSize: 10,
      ),
    );
    var best = pickKuwoRankItem(
      candidates.data,
      KuwoRankTitle(name: hit.name, artist: hit.artist),
    );
    if (best == null) {
      // 歌手拼写差异时，再用纯歌名搜一次；仍匹配不到则取同名结果第一首，
      // 避免热榜条目点不动（部分榜单标题没有完全一致的原唱版本）
      candidates = await kuwoApi.search(
        SearchParams(keyword: hit.name, page: 1, pageSize: 10),
      );
      best = pickKuwoRankItem(
        candidates.data,
        KuwoRankTitle(name: hit.name, artist: hit.artist),
      );
    }
    best ??= candidates.data.isNotEmpty ? candidates.data.first : null;
    return best?.toTrack();
  } catch (_) {
    return null;
  }
}
