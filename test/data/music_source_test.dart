import "package:bobomusic/core/prefs/app_prefs.dart";
import "package:bobomusic/data/music_source.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// S5 默认音源设置：默认 B 站、切换酷我持久化、重启读回
void main() {
  test("默认 B 站；切换酷我写回并新容器读回", () async {
    SharedPreferences.setMockInitialValues(const {});
    await initAppPrefs();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(musicSourceProvider), MusicSource.bili);
    container.read(musicSourceProvider.notifier).select(MusicSource.kuwo);
    expect(appPrefs.getString("music_source"), "kuwo");

    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    expect(restarted.read(musicSourceProvider), MusicSource.kuwo);
  });

  test("预置 music_source=kuwo 时启动即酷我", () async {
    SharedPreferences.setMockInitialValues({"music_source": "kuwo"});
    await initAppPrefs();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(musicSourceProvider), MusicSource.kuwo);
  });
}
