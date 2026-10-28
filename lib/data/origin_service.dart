import "package:bobomusic/origin_sdk/bili/bili_api.dart";
import "package:bobomusic/origin_sdk/kuwo/kuwo_api.dart";
import "package:bobomusic/origin_sdk/netease/netease_api.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/qianqian/qianqian_api.dart";
import "package:bobomusic/origin_sdk/qq/qq_api.dart";

/// 音源 API 全局实例（测试注入 Fake，与 appPrefs/appDb 同一环境单例模式）
/// B 站：鉴权材料随实例缓存；酷我：免签名第二源（D11）；网易：免加密第三源（批次 2）；
/// QQ/千千：免费口径第四/五源（批次 3）
OriginService biliApi = BiliApi();
OriginService kuwoApi = KuwoApi();
OriginService neteaseApi = NeteaseApi();
OriginService qqApi = QqApi();
OriginService qianqianApi = QianqianApi();
