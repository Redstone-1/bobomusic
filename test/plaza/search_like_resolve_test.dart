import "package:bobomusic/data/origin_service.dart" as services;
import "package:bobomusic/data/repositories/playlist_repository.dart";
import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/origin_sdk/bili/types.dart" as bili;
import "package:bobomusic/origin_sdk/origin_types.dart" as sdk;
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "../helpers/app_test_helper.dart";

/// 可编排的 B 站源：搜索卡片与详情由用例注入，统计详情调用次数
class StubBili extends FakeBiliApi {
  final sdk.SearchItem card;
  final sdk.SearchItem detail;
  int detailCalls = 0;

  StubBili({required this.card, required this.detail});

  @override
  Future<sdk.SearchResponse> search(sdk.SearchParams params) async =>
      bili.BiliSearchResponse(
        current: 1,
        total: 1,
        pageSize: 20,
        data: [card],
      );

  @override
  Future<sdk.SearchItem> searchDetail(String id) async {
    detailCalls++;
    return detail;
  }
}

/// 搜索卡片：无 type、无内嵌曲目（B 站"看似单曲实则未知"的形态）
sdk.SearchItem cardOf(String id, String name, {sdk.SearchType? type}) =>
    sdk.SearchItem(
      id: id,
      cover: "",
      name: name,
      duration: 0,
      author: "UP主",
      origin: sdk.OriginType.bili,
      isSeasonDisplay: false,
      type: type,
    );

/// 详情多P合集（orderName 且内嵌曲目 > 1）
bili.BiliSearchItem multiPDetail(String id) => bili.BiliSearchItem(
      id: id,
      cover: "",
      name: "详情合集名",
      duration: 0,
      author: "合集UP",
      origin: sdk.OriginType.bili,
      isSeasonDisplay: false,
      ugcSeason: null,
      type: sdk.SearchType.orderName,
      musicList: [
        sdk.MusicItem(
          id: "${id}_101",
          cover: "",
          name: "第一首",
          duration: 200,
          author: "",
          origin: sdk.OriginType.bili,
        ),
        sdk.MusicItem(
          id: "${id}_102",
          cover: "",
          name: "第二首",
          duration: 201,
          author: "",
          origin: sdk.OriginType.bili,
        ),
      ],
    );

Future<void> openBiliSearch(WidgetTester tester, StubBili stub) async {
  final app = await buildTestApp();
  services.biliApi = stub;
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.tap(find.text("广场"));
  await tester.pump();
  await tester.tap(find.text("搜索歌曲 / 歌手 / 合集"));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.enterText(find.byType(TextField), "夜");
  await tester.pump();
  // 2026-10-31 起搜索改回车触发：模拟键盘搜索键提交
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets("无cid卡片实为合集：点心形加载成员，全部歌曲加入喜欢", (tester) async {
    final stub = StubBili(
      card: cardOf("300_BVmaybe", "深夜电台"),
      detail: multiPDetail("300_BVmaybe"),
    );
    await openBiliSearch(tester, stub);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // 合集成员逐首入库并标记喜欢；不产生歌单
    expect(find.text("已将合集 2 首歌曲加入喜欢"), findsOneWidget);
    final liked = await TrackRepository().likedTracks();
    // 同毫秒入库的成员在 liked_at 倒序下不保证先后
    expect(
      liked.map((t) => t.id),
      unorderedEquals(["300_BVmaybe_101", "300_BVmaybe_102"]),
    );
    expect(await PlaylistRepository().list(), isEmpty);
    // 行内心形即时变红（按卡片 id 覆盖）
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets("无cid卡片实为真单曲：按详情曲目（带cid）入库喜欢", (tester) async {
    final stub = StubBili(
      card: cardOf("300_BVmaybe", "深夜电台"),
      detail: cardOf("300_BVmaybe_777", "隐藏的真单曲"),
    );
    await openBiliSearch(tester, stub);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    final liked = await TrackRepository().likedTracks();
    expect(liked.map((t) => t.id), ["300_BVmaybe_777"]);
    expect(liked.single.name, "隐藏的真单曲");
    // 行内心形即时变红（按卡片 id 覆盖），无合集提示
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text("已将合集 2 首歌曲加入喜欢"), findsNothing);
  });

  testWidgets("music类型卡片（真机漏判形态）也走详情：实为合集则成员全部入喜欢",
      (tester) async {
    final stub = StubBili(
      card: cardOf("400_BVsure", "确定的单曲", type: sdk.SearchType.music),
      detail: multiPDetail("400_BVsure"),
    );
    await openBiliSearch(tester, stub);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // 卡片类型不可信：必须请求详情分流后处置
    expect(stub.detailCalls, greaterThanOrEqualTo(1));
    expect(find.text("已将合集 2 首歌曲加入喜欢"), findsOneWidget);
    final liked = await TrackRepository().likedTracks();
    expect(
      liked.map((t) => t.id),
      unorderedEquals(["400_BVsure_101", "400_BVsure_102"]),
    );
  });

  testWidgets("music类型卡片实为真单曲：按详情曲目（带cid）入库喜欢", (tester) async {
    final stub = StubBili(
      card: cardOf("400_BVsure", "确定的单曲", type: sdk.SearchType.music),
      detail: cardOf("400_BVsure_555", "详情单曲"),
    );
    await openBiliSearch(tester, stub);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(stub.detailCalls, 1);
    final liked = await TrackRepository().likedTracks();
    expect(liked.map((t) => t.id), ["400_BVsure_555"]);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets("合集更多菜单：全部加入歌单把成员逐首加入目标歌单", (tester) async {
    final stub = StubBili(
      card: cardOf("300_BVmaybe", "深夜电台"),
      detail: multiPDetail("300_BVmaybe"),
    );
    await openBiliSearch(tester, stub);
    await PlaylistRepository().create("我的歌单");

    // 更多菜单先详情分流：合集 → 整包操作
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // 等弹层进场动画完成再点动作，避免命中偏移
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("全部加入歌单（2 首）"), findsOneWidget);

    // 选歌单 → 成员逐首入库（一级弹层退场 + 二级弹层进场需要多帧动画）
    await tester.tap(find.text("全部加入歌单（2 首）"));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text("我的歌单"));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text("已加入「我的歌单」2 首"), findsOneWidget);
    final items = await PlaylistRepository().items(
      (await PlaylistRepository().list()).single.id,
    );
    expect(items.map((t) => t.id), ["300_BVmaybe_101", "300_BVmaybe_102"]);
  });
}
