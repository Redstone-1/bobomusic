import "package:bobomusic/data/repositories/track_repository.dart";
import "package:bobomusic/features/player/player_card_page.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "../../helpers/app_test_helper.dart";

/// 播放卡手势（2026-11-01 定）：汽水式翻页——上滑下一曲 / 下滑上一曲。
/// 跟手阶段邻曲预览从对侧滑入；松手过阈值（视口高度 18%）滑出并切歌。
/// 歌词区纵向滚动由列表自身消费，切歌手势只在非滚动区生效——
/// 用例从顶栏出发拖动（避开歌词列表）。
/// 我喜欢列表按 liked_at 倒序，连续入库可能同毫秒、顺序不稳定，
/// 故只断言「上滑离开原曲、下滑回到原曲」，不假设具体下一曲。
/// 切歌发生在「滑出动画完成」的帧末回调，之后新内容还需滑入：
/// 断言前必须分两段 pump 推进动画时钟
void main() {
  testWidgets("播放卡：上滑切下一曲，下滑切回上一曲", (tester) async {
    final app = await buildTestApp(seedTracks: const [
      {"id": "bili:1_a", "name": "晴天", "author": "周杰伦"},
      {"id": "bili:2_b", "name": "夜曲", "author": "周杰伦"},
      {"id": "bili:3_c", "name": "彩虹", "author": "周杰伦"},
    ]);
    for (final id in ["bili:1_a", "bili:2_b", "bili:3_c"]) {
      await TrackRepository().setLiked(id, true);
    }

    await tester.pumpWidget(app);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 我喜欢 → 点第一首开播（上下文 = 三首列表）→ 打开播放卡
    await tester.tap(find.text("我喜欢的音乐"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text("晴天"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key("mini_player")));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.descendant(of: find.byType(PlayerCardPage), matching: find.text("晴天")),
      findsOneWidget,
    );

    // 上滑（从顶栏出发，160px > 视口 18% 阈值）→ 滑出切下一曲
    await tester.drag(find.text("正在播放"), const Offset(0, -160));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 滑出完成、切歌
    await tester.pump(const Duration(milliseconds: 400)); // 新内容滑入
    // ignore: avoid_print
    print("SWIPE-POS topbar=${tester.getTopLeft(find.text("正在播放"))}");
    expect(
      find.descendant(of: find.byType(PlayerCardPage), matching: find.text("晴天")),
      findsNothing,
    );

    // 下滑 → 上一曲（回到原曲）
    await tester.drag(find.text("正在播放"), const Offset(0, 160));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.descendant(of: find.byType(PlayerCardPage), matching: find.text("晴天")),
      findsOneWidget,
    );
  });
}
