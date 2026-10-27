import "package:bobomusic/features/plaza/search_page.dart";
import "package:flutter_test/flutter_test.dart";

/// 搜索历史维护（纯函数）：置顶、去重前移、上限 10、空词不记
void main() {
  test("新词置顶插入", () {
    final next = updateSearchHistory(["a", "b"], "c");
    expect(next, ["c", "a", "b"]);
  });

  test("重复词前移去重，不产生双条", () {
    final next = updateSearchHistory(["a", "b", "c"], "b");
    expect(next, ["b", "a", "c"]);
  });

  test("超过 10 条时淘汰最旧", () {
    final history = [for (var i = 1; i <= 10; i++) "词$i"];
    final next = updateSearchHistory(history, "新词");
    expect(next.length, 10);
    expect(next.first, "新词");
    expect(next, isNot(contains("词10"))); // 最旧的被挤出
    expect(next, contains("词1"));
  });

  test("空白词不记录，原样返回", () {
    const history = ["a"];
    expect(updateSearchHistory(history, "  "), same(history));
  });
}
