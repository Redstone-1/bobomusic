import "package:bobomusic/origin_sdk/bili/sign.dart";
import "package:flutter_test/flutter_test.dart";

/// WBI 签名特征测试（S2.3）：锁定 mixinKey 与签名输出
/// 黄金值取自当前生产可用实现（旧版 2.7.0 同算法，线上已验证）；
/// B 站更换混淆表/算法时此处先红，即接口漂移信号
void main() {
  // bilibili-API-collect 文档示例所用密钥对
  const imgKey = "7cd084941338484aae1ad9425b84077c";
  const subKey = "4932ca06026ee65899800f7c2f0bd6a6";

  test("getMixinKey：混淆表重排 + 截断 32 位（黄金值锁定）", () {
    final mixin = getMixinKey(imgKey + subKey);
    expect(mixin, "581df124a83c00624e49936a70464028");
    expect(mixin.length, 32);
  });

  test("encWbi：注入固定 wts 后签名可复现（黄金值锁定）", () {
    final signed = encWbi(
      {"foo": "one", "bar": "two", "baz": 3},
      imgKey,
      subKey,
      wts: 1702204800,
    );
    expect(signed["wts"], "1702204800");
    expect(signed["w_rid"], "becad88091c9362d5741a7f2e4ea70f5");
  });

  test("encWbi：特殊字符过滤（!'()* 移除）与空格编码（黄金值锁定）", () {
    final signed = encWbi(
      {"a": "h!a(h*a'）", "b": "x y"},
      imgKey,
      subKey,
      wts: 1702204800,
    );
    expect(signed["w_rid"], "3c9e8075fd0b4cd4701176021ab7e9f7");
  });
}
