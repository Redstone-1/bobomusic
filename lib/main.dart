import "dart:io";

import "package:audio_service/audio_service.dart";
import "package:bobomusic/constants/notification.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/download/model.dart";
import "package:bobomusic/permission/permission.dart";
import "package:bobomusic/utils/get_cache_color.dart";
import "package:bobomusic/utils/window_manage.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/home/home.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/player/service.dart";
import "package:flutter/services.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:just_audio_media_kit/just_audio_media_kit.dart";
import "package:provider/provider.dart";

// toast 初始化
final botToastBuilder = BotToastInit();
// 主题
Color primaryColor = Colors.black;
// 数据库
final DBOrder db = DBOrder(version: 2);

ThemeData theme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.white,
    primary: primaryColor,
    brightness: Brightness.light,
  ),
  primaryColor: primaryColor,
  appBarTheme: const AppBarTheme(
    backgroundColor: Color.fromARGB(255, 245, 245, 245)
  ),
  popupMenuTheme: const PopupMenuThemeData(
    color: Color.fromARGB(255, 245, 245, 245)
  ),
  scaffoldBackgroundColor: const Color.fromARGB(255, 245, 245, 245),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: Colors.grey[200],
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(10),
        topRight: Radius.circular(10),
      ),
    ),
  ),
);

final _playerHandler = AudioPlayerHandler();

void main() async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await initWindowManage();
  }

  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(
    iOS: false,
    android: false,
    windows: true,
    linux: true,
    macOS: false,
  );
  final playerService = await AudioService.init(
    builder: () => _playerHandler,
    config: AudioServiceConfig(
      androidNotificationChannelId: NotificationAudio.channelId,
      androidNotificationChannelName: NotificationAudio.channelName,
      androidNotificationOngoing: true,
    ),
  );

  await db.deleteAll(TableName.musicWaitPlay);

  primaryColor = await getCacheColor();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => PlayerModel()),
        ChangeNotifierProvider(create: (context) => DownloadModel()),
      ],
      child: MyApp(
        initialTheme: theme.copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.white,
            primary: primaryColor,
            brightness: Brightness.light,
          ),
          primaryColor: primaryColor,
        ),
        playerHandler: _playerHandler,
        playerService: playerService,
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  final ThemeData initialTheme;
  final AudioPlayerHandler playerHandler;
  final AudioHandler playerService;

  const MyApp({
    super.key,
    required this.initialTheme,
    required this.playerHandler,
    required this.playerService,
  });

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  late ThemeData _currentTheme;

  @override
  void initState() {
    super.initState();
    // 初始化播放器
    Provider.of<PlayerModel>(context, listen: false).init(
      playerHandler: widget.playerHandler,
      playerService: widget.playerService,
    );
    _currentTheme = widget.initialTheme;
    // 监听主题色变更事件
    eventBus.on<ThemeColorChanged>().listen((event) {
      setState(() {
        primaryColor = event.newColor;
        _currentTheme = _currentTheme.copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.white,
            primary: primaryColor,
            brightness: Brightness.light,
          ),
          primaryColor: primaryColor,
        );
      });
    });

    Permissions.requestNotificationPermission();
  }

  @override
  Widget build(BuildContext context) {
    // 隐藏 Android 底部导航条
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    return MaterialApp(
      theme: _currentTheme,
      home: const HomeView(),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [BotToastNavigatorObserver()],
      builder: (context, child) {
        child = EasyLoading.init()(context, child);
        child = botToastBuilder(context, child);
        // 消息提示框的默认配置
        BotToast.defaultOption.text.duration = const Duration(seconds: 3);
        BotToast.defaultOption.text.textStyle = TextStyle(
          fontSize: 12,
          color: Theme.of(context).cardColor,
        );
        EasyLoading.instance.indicatorType = EasyLoadingIndicatorType.cubeGrid;
        return child;
      },
    );
  }
}
