import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "app/app.dart";

// v2 重写版入口：S1 阶段为 UI 骨架（mock 数据）；
// 播放内核 / 数据库 / AudioService / 通知栏在 S3、S4 逐步接入
void main() {
  runApp(const ProviderScope(child: App()));
}
