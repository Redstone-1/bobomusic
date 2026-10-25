import "package:shared_preferences/shared_preferences.dart";

/// 全局 SharedPreferences 实例（main() 预取后处处同步可读）
/// 测试中先 SharedPreferences.setMockInitialValues() 再 initAppPrefs()
late SharedPreferences appPrefs;

Future<void> initAppPrefs() async {
  appPrefs = await SharedPreferences.getInstance();
}
