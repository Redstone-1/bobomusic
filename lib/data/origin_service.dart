import "package:bobomusic/origin_sdk/bili/bili_api.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";

/// B 站 API 全局实例（鉴权材料随实例缓存）
/// 可替换：测试注入 Fake（与 appPrefs/appDb 同一"环境单例"模式）
OriginService biliApi = BiliApi();
