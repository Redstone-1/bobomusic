import "package:bobomusic/origin_sdk/bili/bili_api.dart";
import "package:bobomusic/origin_sdk/kuwo/kuwo_api.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";

/// 音源 API 全局实例（测试注入 Fake，与 appPrefs/appDb 同一环境单例模式）
/// B 站：鉴权材料随实例缓存；酷我：免签名第二源（D11）
OriginService biliApi = BiliApi();
OriginService kuwoApi = KuwoApi();
