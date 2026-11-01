import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/mappers.dart";
// UI/SDK 各有一套 OriginType，本文件与 SDK 条目的 origin 比较一律用 SDK 侧
import "../../data/models/track.dart" hide OriginType;
import "../../data/origin_service.dart";
import "../../origin_sdk/kuwo/kuwo_api.dart";
import "../../origin_sdk/netease/netease_api.dart";
import "../../origin_sdk/origin_types.dart";
import "../../origin_sdk/qianqian/qianqian_api.dart";
import "../../origin_sdk/qq/qq_api.dart";

/// 广场榜单卡定义（key = "<源 value>:<源内榜单id>"，展示名带源前缀；Tab 顺序即展示顺序）
/// 网易：官方 playlist 榜（免加密接口）；千千：官方新歌榜（bdid 硬编码）；
/// B 站音乐榜已按用户决定下线（请求不稳定）；QQ 榜单未上（免费条目少）；
/// 酷我双榜已按用户决定下线（2026-11-01：VIP 试听占比过高，bang 接口付费
/// 字段全员恒定，解析层无法过滤）
const plazaChartDefs = <(String, String)>[
  ("${NeteaseApi.chartKeyPrefix}${NeteaseApi.hotChartId}", "网易云热歌榜"),
  ("${NeteaseApi.chartKeyPrefix}${NeteaseApi.surgeChartId}", "网易云飙升榜"),
  ("${NeteaseApi.chartKeyPrefix}${NeteaseApi.originalChartId}", "网易云原创榜"),
  ("${NeteaseApi.chartKeyPrefix}${NeteaseApi.electroChartId}", "网易云电音榜"),
  ("${QianqianApi.chartKeyPrefix}${QianqianApi.newSongChartBdid}", "千千新歌榜"),
];

/// 榜单 key 前缀 → 所属 SDK 源（拉取与点播解析按此分发；后续新源接入时在此登记）
OriginType originForChartKey(String key) {
  if (key.startsWith(KuwoApi.chartKeyPrefix)) return OriginType.kuwo;
  if (key.startsWith(NeteaseApi.chartKeyPrefix)) return OriginType.netease;
  if (key.startsWith(QianqianApi.chartKeyPrefix)) return OriginType.qianqian;
  if (key.startsWith(QqApi.chartKeyPrefix)) return OriginType.qq;
  return OriginType.bili;
}

OriginService _apiForChartKey(String key) {
  if (key.startsWith(KuwoApi.chartKeyPrefix)) return kuwoApi;
  if (key.startsWith(NeteaseApi.chartKeyPrefix)) return neteaseApi;
  if (key.startsWith(QianqianApi.chartKeyPrefix)) return qianqianApi;
  if (key.startsWith(QqApi.chartKeyPrefix)) return qqApi;
  return biliApi;
}

/// 单张榜单卡数据（keepAlive：进详情页/回广场不重拉；单卡失败只降级该卡）
final plazaChartProvider = FutureProvider.family<OriginChart, String>((ref, key) async {
  final api = _apiForChartKey(key);
  try {
    final hits = await api.getChartHits(key);
    final def = plazaChartDefs.firstWhere(
      (d) => d.$1 == key,
      orElse: () => (key, key),
    );
    return OriginChart(key: key, name: def.$2, hits: hits ?? const []);
  } catch (e) {
    // 单卡失败只降级该卡；真实原因打控制台（逆向接口漂移/风控都靠这行定位）
    print("[plaza] 榜单拉取失败 [$key]：$e");
    rethrow;
  }
});

/// 点播榜单条目：榜单已给出可播条目直接用；B 站条目缺 cid 时经 searchDetail 补齐
/// （多 P/合集取可播首条）；无条目的兜底行（SSR 链可能缺 rid）按标题+歌手在本源搜索解析
Future<Track?> resolveChartHit(ChartHit hit, OriginType origin) async {
  final item = hit.item;
  if (item != null) {
    if (item.origin == OriginType.bili && item.id.split("_").length < 3) {
      try {
        final detail = await biliApi.searchDetail(item.id);
        return detail.toTrack(); // musicList 首项优先（mappers），多 P 取第一 P
      } catch (e) {
        print("B 站榜单条目详情失败 [${item.id}]：$e");
        return null;
      }
    }
    return item.toTrack();
  }
  if (origin != OriginType.kuwo) return null;
  // 酷我 SSR 兜底行解析：标题+歌手搜索匹配 → 纯歌名重试 → 同名首条，避免热榜条目点不动
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
      // 歌手拼写差异时，再用纯歌名搜一次；仍匹配不到则取同名结果第一首
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

/// 酷我 VIP 试听片段登记（会话内有效，app 重启清零）：播放期探测到
/// 「引擎实际时长明显短于曲目标注」的曲目 id 集合，广场榜单据此
/// 灰显 + 打 VIP 角标；app 壳监听集合新增弹提示
class VipLimitedTrackIds extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String trackId) {
    if (state.contains(trackId)) return;
    state = {...state, trackId};
  }
}

final vipLimitedTrackIdsProvider =
    NotifierProvider<VipLimitedTrackIds, Set<String>>(VipLimitedTrackIds.new);
