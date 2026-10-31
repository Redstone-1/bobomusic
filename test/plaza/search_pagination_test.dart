import "dart:async";

import "package:bobomusic/data/origin_service.dart" as services;
import "package:bobomusic/origin_sdk/bili/types.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/qq/qq_api.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/app_test_helper.dart";

class PagedQq extends FakeQqApi {
  final Future<SearchResponse> Function(SearchParams) handler;
  final requests = <SearchParams>[];
  PagedQq(this.handler);

  @override
  Future<SearchResponse> search(SearchParams params) {
    requests.add(params);
    return handler(params);
  }
}

SearchItem song(String name) => SearchItem(
      id: "qq:$name",
      cover: "",
      name: name,
      duration: 200,
      author: "测试",
      origin: OriginType.qq,
      isSeasonDisplay: false,
      type: SearchType.music,
    );

Future<void> openSearch(WidgetTester tester, PagedQq api) async {
  final app = await buildTestApp();
  services.qqApi = api;
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.tap(find.text("广场"));
  await tester.pump();
  await tester.tap(find.text("搜索歌曲 / 歌手 / 合集"));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text("QQ"));
  await tester.pump();
}

void main() {
  testWidgets("过滤空页可继续查找，下一次从最后消费页翻页", (tester) async {
    final api = PagedQq((params) async => params.page == 1
        ? const QqSearchResponse(
            current: 3, total: 300, pageSize: 30, data: [], hasMore: true)
        : QqSearchResponse(
            current: 4,
            total: 300,
            pageSize: 30,
            data: [song("后续免费歌曲")],
            hasMore: false));
    await openSearch(tester, api);
    await tester.enterText(find.byType(TextField), "歌");
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("继续查找"), findsOneWidget);
    await tester.tap(find.text("继续查找"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.requests.map((p) => p.page), [1, 4]);
    expect(find.text("后续免费歌曲"), findsOneWidget);
    expect(find.text("到底了"), findsOneWidget);
  });

  testWidgets("免费结果不足一屏也能手动加载更多，按原始页码继续", (tester) async {
    final api = PagedQq((params) async => QqSearchResponse(
          current: params.page == 1 ? 3 : 4,
          total: 300,
          pageSize: 30,
          data: [song(params.page == 1 ? "首批免费" : "下一批免费")],
          hasMore: params.page == 1,
        ));
    await openSearch(tester, api);
    await tester.enterText(find.byType(TextField), "歌");
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("加载更多"), findsOneWidget);
    await tester.tap(find.text("加载更多"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.requests.map((p) => p.page), [1, 4]);
    expect(find.text("下一批免费"), findsOneWidget);
  });

  testWidgets("服务拒绝显示具体原因，不伪装成搜索无结果", (tester) async {
    final api = PagedQq((_) async => throw const QqApiError(
          "QQ 音乐请求被限制，请稍后重试",
          kind: QqFailure.rejected,
          code: 2001,
        ));
    await openSearch(tester, api);
    await tester.enterText(find.byType(TextField), "歌");
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("搜索失败"), findsOneWidget);
    expect(find.text("QQ 音乐请求被限制，请稍后重试"), findsOneWidget);
  });

  testWidgets("输入过程不自动搜索，回车才发请求", (tester) async {
    final api = PagedQq((params) async => QqSearchResponse(
          current: 1,
          total: 1,
          pageSize: 30,
          data: [song("回车结果")],
          hasMore: false,
        ));
    await openSearch(tester, api);
    await tester.enterText(find.byType(TextField), "歌");
    await tester.pump(const Duration(milliseconds: 400));
    // 输入停顿不产生任何请求（2026-10-31 移除防抖自动搜）
    expect(api.requests, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.requests.map((p) => p.keyword), ["歌"]);
    expect(find.text("回车结果"), findsOneWidget);
  });

  testWidgets("在途旧响应不得覆盖新提交的搜索", (tester) async {
    final pending = Completer<SearchResponse>();
    final api = PagedQq((params) => params.keyword == "旧"
        ? pending.future
        : Future.value(QqSearchResponse(
            current: 1,
            total: 1,
            pageSize: 30,
            data: [song("新结果")],
            hasMore: false)));
    await openSearch(tester, api);
    await tester.enterText(find.byType(TextField), "旧");
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    // 输入变化本身不发请求也不作废在途响应；新提交的搜索才隔离旧词
    await tester.enterText(find.byType(TextField), "新");
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    pending.complete(BiliSearchResponse(
        current: 1, total: 1, pageSize: 30, data: [song("不应出现的旧结果")]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("不应出现的旧结果"), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("新结果"), findsOneWidget);
  });
}
