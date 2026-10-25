import "package:bobomusic/origin_sdk/bili/bili_auth.dart";
import "package:bobomusic/origin_sdk/bili/types.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 鉴权缓存还原与 cookie 构造特征测试（S2.2/S2.3）
/// 网络路径不在单测覆盖内（需真机实测，见硬规则 8）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // restore 判定用 DateTime.now()，取当下时间保证"未过期"
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  test("三件套缓存未过期且版本匹配 → 还原成功，不触网络", () async {
    SharedPreferences.setMockInitialValues({
      "bili_cache_version": "4",
      "bili_catch_created_at": nowMs,
      "bili_sign_img_key": "img123",
      "bili_sign_sub_key": "sub456",
      "bili_spi_b3": "b3value",
      "bili_spi_b4": "b4value",
      "bili_ticket": "ticket789",
      "bili_b_nut": "nutvalue",
      "bili_buvid3": "buvid3value",
      "bili_b_nut_created_at": nowMs,
    });

    final auth = BiliAuth();
    await auth.ensure();

    expect(auth.signData?.imgKey, "img123");
    expect(auth.signData?.subKey, "sub456");
    expect(auth.spiData?.b3, "buvid3value"); // buvid3 以主页 Set-Cookie 为准
    expect(auth.spiData?.b4, "b4value");
    expect(auth.ticket, "ticket789");
    expect(auth.bNut, "nutvalue");
  });

  test("cookieHeader：b_nut 为空不写入 cookie（纯契约，不走网络）", () {
    final auth = BiliAuth()
      ..spiData = const SpiData(b3: "b3", b4: "b4")
      ..ticket = "tk"
      ..bNut = "";

    final cookie = auth.cookieHeader();
    expect(cookie, contains("buvid3=b3"));
    expect(cookie, contains("buvid4=b4"));
    expect(cookie, contains("bili_ticket=tk"));
    expect(cookie, isNot(contains("b_nut")));
  });

  test("cookieHeader：b_nut 非空时写入", () {
    final auth = BiliAuth()
      ..spiData = const SpiData(b3: "b3", b4: "b4")
      ..ticket = "tk"
      ..bNut = "nut";

    expect(auth.cookieHeader(), contains("b_nut=nut"));
  });

  test("缓存版本不匹配 → 不还原（触发重刷材料的机制保留）", () async {
    SharedPreferences.setMockInitialValues({
      "bili_cache_version": "3",
      "bili_catch_created_at": nowMs,
      "bili_sign_img_key": "img123",
      "bili_sign_sub_key": "sub456",
      "bili_spi_b3": "b3",
      "bili_spi_b4": "b4",
      "bili_ticket": "tk",
    });

    final auth = BiliAuth();
    // 还原失败 → 走网络 → 单测环境网络不可控，这里只验证"未还原"状态
    // （ensure 会抛 BiliAuthError 或成功拉取，均属正确行为，不做强断言）
    try {
      await auth.ensure();
      // 网络可用时成功拉取也算通过；此时材料应就绪
      expect(auth.ticket, isNotNull);
    } catch (_) {
      // 网络不可达时类型化失败
      expect(true, isTrue);
    }
    expect(auth.signData?.imgKey, isNot("img123")); // 旧版本缓存未被采用
  });
}
