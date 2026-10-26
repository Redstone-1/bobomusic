import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/mappers.dart";
import "../../data/models/track.dart";
import "../../data/origin_service.dart";
import "../../origin_sdk/kuwo/kuwo_api.dart";
import "../../origin_sdk/origin_types.dart";

/// 酷我官方热榜：标题来自榜单页；item 可能为空，点播时再解析 rid
final kuwoHotHitsProvider = FutureProvider<List<KuwoHotHit>>((ref) async {
  final api = kuwoApi;
  if (api is KuwoApi) return api.hotHits();
  // 测试/其它 OriginService 兜底：优先用其 hotSongs，再退回搜索
  final items = await api.hotSongs();
  if (items.isNotEmpty) {
    return [
      for (final item in items)
        KuwoHotHit(name: item.name, artist: item.author, item: item),
    ];
  }
  final resp = await api.search(
    const SearchParams(keyword: "热门歌曲", page: 1, pageSize: 10),
  );
  return [
    for (final item in resp.data)
      KuwoHotHit(name: item.name, artist: item.author, item: item),
  ];
});

/// 点播热榜条目：SSR 已带 item 直接用；否则按标题+歌手搜索并做匹配筛选
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
