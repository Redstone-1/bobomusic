// ignore_for_file: use_build_context_synchronously, avoid_print, deprecated_member_use

import "dart:async";
import "dart:ui";

import "package:bobomusic/components/ripple_icon/ripple_icon.dart";
import "package:bobomusic/icons/icons_svg.dart";
import "package:bobomusic/modules/music_order/components/top_bar.dart";
import "package:bobomusic/constants/covers.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/download/model.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/modules/player/lyrics_card/lyric_scroller.dart";
import "package:bobomusic/modules/player/player_card/current_list.dart";
import "package:bobomusic/modules/player/player_card/vinyl_record.dart";
import "package:bobomusic/modules/player/utils.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/check_music_local_repeat.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:like_button/like_button.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";
import "package:uuid/uuid.dart";

const uuid = Uuid();
final DBOrder db = DBOrder(version: 2);

class PlayerCard extends StatefulWidget {
  const PlayerCard({super.key});

  @override
  State<PlayerCard> createState() => PlayerCardState();
}

class PlayerCardState extends State<PlayerCard> {
  bool isLike = false;
  String coverUrl = Covers.getRandomCover();
  String errorCoverUrl = Covers.getLocalCover();
  ImageProvider? _imageProvider;
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _imageProvider = NetworkImage(coverUrl);
    _pageController = PageController(initialPage: _currentPage);

    eventBus.on<RefresPlayerCard>().listen((event) {
      _initState();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initState();
      _loadImage();
    });
  }

  Future<void> _initState() async {
    try {
      final current = Provider.of<PlayerModel>(context, listen: false).current;
      final List<Map<String, dynamic>> dbMusics = await db.queryByParam(TableName.musicILike, current?.id ?? current!.name);

      if (dbMusics.isNotEmpty) {
        setState(() {
          isLike = true;
        });
      } else {
        setState(() {
          isLike = false;
        });
      }
    } catch (error) {
      print("$error");
    }
  }

  @override
  void dispose() {
    _imageStream?.removeListener(
      ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {},
        onError: (dynamic exception, StackTrace? stackTrace) {},
      ),
    );
    _pageController.dispose();
    super.dispose();
  }

  void _loadImage() {
    _imageStream = _imageProvider?.resolve(const ImageConfiguration());
    _imageStream?.addListener(
      ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          setState(() {
            _imageInfo = info;
          });
        },
        onError: (dynamic exception, StackTrace? stackTrace) {
          print("Image loading error: $exception");
        },
      ),
    );
  }

  Widget _buildTopBar(Color primaryColor) {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 16, top: 30, right: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(Icons.keyboard_arrow_down, color: primaryColor, size: 30),
            ),
            onTap: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecordWidget() {
    return Container(
      padding: const EdgeInsets.only(left: 20, top: 20, right: 20),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        child: VinylRecordWidget(
          albumCoverUrl: coverUrl,
          errorAlbumCoverUrl: errorCoverUrl,
          isPlaying: Provider.of<PlayerModel>(context, listen: false).isPlaying,
        ),
      ),
    );
  }

  Widget _buildMusicInfo(Color primaryColor) {
    final player = Provider.of<PlayerModel>(context, listen: false);
    String subTitle =
        player.current!.orderName.isEmpty ? "未知歌单" : (player.current!.orderName.contains("musicList_") ? "合集" : player.current!.orderName);
    if (player.current!.author.isNotEmpty) {
      subTitle = "$subTitle  ${player.current!.author}";
    }

    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;

    return Container(
      padding: const EdgeInsets.only(
        left: 30,
        top: 30,
        right: 30,
        bottom: 20,
      ),
      child: Align(
        alignment: Alignment.center,
        child: Column(
          children: [
            Text(
              player.current!.name,
              style: TextStyle(
                fontSize: isLandscape ? 54 : 18,
                overflow: TextOverflow.ellipsis,
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subTitle,
              style: TextStyle(
                fontSize: isLandscape ? 20 : 10,
                overflow: TextOverflow.ellipsis,
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _launchBilibiliVideo(String bvId, PlayerModel player) async {
    try {
      final res = await getLaunchBilibiliConfirm();

      if (res) {
        showDialog(
          context: context,
          builder: (ctx) => Container(
            alignment: Alignment.bottomCenter,
            child: CupertinoActionSheet(
              title: const Text("打开哔哩哔哩", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              message: Container(
                margin: const EdgeInsets.only(top: 6),
                child: const Text("请授权始终打开，授权后需要重新操作", style: TextStyle(fontSize: 10)),
              ),
              actions: [
                CupertinoActionSheetAction(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    setLaunchBilibiliConfirm(confirm: false);
                    final url = "bilibili://video/$bvId";
                    await launchUrl(Uri.parse(url));
                  },
                  child: const Text("确认且不再提示", style: TextStyle(fontSize: 12, color: Colors.deepPurple))
                ),
              ],
              cancelButton: CupertinoActionSheetAction(onPressed: () {
                Navigator.of(context).pop();
              }, child: Text("取消", style: TextStyle(fontSize: 12, color: Colors.grey[800]))),
            ),
          )
        );
      } else {
        final url = "bilibili://video/$bvId";
        await launchUrl(Uri.parse(url));
      }
    } catch(error) {
      final webUrl = "https://www.bilibili.com/video/$bvId/?spm_id_from=333.1007.tianma.1-2-2.click";
      await launchUrl(Uri.parse(webUrl));
    }
  }

  /// 显示当前播放列表
  Future showCurrentList(BuildContext context, List<MusicItem> musicList) {
    final NavigatorState navigator = Navigator.of(context, rootNavigator: false);
    return navigator.push(ModalBottomSheetRoute(
      isScrollControlled: true,
      builder: (context) {
        return CurrentList(musicList: musicList);
      },
    ));
  }

  Widget _buildActionButtons(Color primaryColor) {
    final player = Provider.of<PlayerModel>(context, listen: false);
    final musicItem = player.current as MusicItem;
    final isLocal = musicItem.localPath.isNotEmpty;

    return Container(
      padding: const EdgeInsets.only(left: 42, right: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          RippleIcon(
            size: 28,
            child: Transform.translate(
              offset: const Offset(0, 1),
              child: Icon(Icons.download_outlined, color: primaryColor, size: 28),
            ),
            onTap: () {
              if (isLocal) {
                BotToast.showText(text: "本地音乐，无需下载");
                return;
              }

              checkMusicLocalRepeat(context, musicItem, () {
                final downloadModel = Provider.of<DownloadModel>(context, listen: false);
                downloadModel.download([musicItem]);
              });
            },
          ),
          Padding(padding: const EdgeInsets.all(8), child: LikeButton(
            size: 28,
            animationDuration: const Duration(seconds: 1),
            circleColor: const CircleColor(start: Color(0xff00ddff), end: Color(0xff0099cc)),
            bubblesColor: const BubblesColor(
              dotPrimaryColor: Color(0xff33b5e5),
              dotSecondaryColor: Color.fromARGB(255, 198, 121, 44),
              dotThirdColor: Color.fromARGB(255, 204, 33, 33),
              dotLastColor: Color.fromARGB(255, 44, 198, 80),
            ),
            likeBuilder: (bool isLiked) {
              return isLike
                ? const Icon(Icons.favorite, size: 28, color: Colors.redAccent)
                : Icon(Icons.favorite_border_rounded, color: primaryColor, size: 28);
            },
            onTap: (bool isLiked) async {
              try {
                if (!isLike) {
                  await db.insert(
                    TableName.musicILike,
                    musicItem2Row(
                      music: player.current!.copyWith(
                        orderName: TableName.musicILike,
                        playId: uuid.v4()
                      )
                    ),
                  );

                  setState(() {
                    isLike = true;
                  });

                  BotToast.showText(text: "已喜欢");
                } else {
                  await db.delete(TableName.musicILike, player.current!.name);

                  setState(() {
                    isLike = false;
                  });

                  BotToast.showText(text: "取消喜欢");
                }

                eventBus.fire(RefreshMusicList(tabName: FrozenTab.iLike));
              } catch (error) {
                print(error);
              }

              return isLike;
            },
          )),
          RippleIcon(
            size: 28,
            child: SvgPicture.string(
              IconsSVG.bilibili,
              color: primaryColor,
              width: 28,
              height: 28,
            ),
            onTap: () {
              final biliVIDs = player.current!.id.split("_").where((e) => e.startsWith("BV")).toList();

              if (biliVIDs.isNotEmpty) {
                _launchBilibiliVideo(biliVIDs[0], player);
              } else {
                BotToast.showText(text: "找不到视频");
              }
            },
          ),
          if(player.current!.orderName.isNotEmpty)
            RippleIcon(
              size: 28,
              onTap: () async {
                EasyLoading.show(maskType: EasyLoadingMaskType.black);

                try {
                  final dbMusics = await getUpdatedMusicList(tabName: player.current!.orderName);

                  EasyLoading.dismiss();

                  showCurrentList(context, dbMusics);
                } catch (error) {
                  print(error);
                  EasyLoading.dismiss();
                }
              },
              child: Icon(Icons.menu, size: 28, color: primaryColor),
            )
        ],
      ),
    );
  }

  Widget _buildControlButtons(Color primaryColor) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final double gap = isLandscape ? 20 : 10;
    final double sizeA = isLandscape ? 50 : 30;
    final double sizeB = isLandscape ? 60 : 40;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ModeButton(size: sizeA, color: primaryColor),
        SizedBox(width: gap),
        PrevButton(size: sizeB, color: primaryColor),
        SizedBox(width: gap),
        PlayButton(size: sizeB, color: primaryColor),
        SizedBox(width: gap),
        NextButton(size: sizeB, color: primaryColor),
        SizedBox(width: gap),
        PlayerListButton(size: sizeA, color: primaryColor),
      ],
    );
  }

  // 构建轮播组件内的指示器
  Widget _buildCarouselIndicator(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          2, // 总页数
          (index) => Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == _currentPage
                  ? primaryColor
                  : primaryColor.withOpacity(0.3),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final primaryColor = Theme.of(context).primaryColor;

    return Consumer<PlayerModel>(
      builder: (context, player, child) {
        return Stack(
          children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: _imageInfo != null
                  ? Image(
                      image: _imageProvider!,
                      fit: BoxFit.cover,
                    )
                  : Image.asset(
                      errorCoverUrl,
                      fit: BoxFit.cover,
                    ),
              ),
            ),
            Container(
              width: screenSize.width,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withOpacity(0.5),
              ),
              padding: EdgeInsets.only(bottom: isLandscape ? 30 : 0),
              child: Column(
                children: [
                  // 顶部导航栏
                  _buildTopBar(primaryColor),

                  Expanded(
                    child: isLandscape
                      ? // 横屏模式：左右布局
                        Row(
                          children: [
                            // 左侧轮播图区域
                            SizedBox(
                              height: screenSize.height * 0.9,
                              width: screenSize.width * 0.6, // 占60%宽度
                              child: Column(
                                children: [
                                  // 轮播组件内的指示器
                                  _buildCarouselIndicator(primaryColor),
                                  Expanded(
                                    child: PageView(
                                      controller: _pageController,
                                      onPageChanged: (index) => setState(() => _currentPage = index),
                                      children: [
                                        Column(
                                          children: [
                                            _buildRecordWidget(),
                                          ],
                                        ),
                                        const Column(
                                          children: [
                                            Expanded(
                                              child: LyricsScroller(),
                                            )
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 右侧区域（操作按钮 + 进度条 + 控制按钮）
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildMusicInfo(primaryColor),
                                    const SizedBox(height: 30),
                                    _buildActionButtons(primaryColor),
                                    const SizedBox(height: 30),
                                    PlayerProgress(color: primaryColor),
                                    const SizedBox(height: 30),
                                    _buildControlButtons(primaryColor),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : // 竖屏模式：垂直布局
                        Column(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  // 轮播组件内的指示器
                                  _buildCarouselIndicator(primaryColor),
                                  Expanded(
                                    child: PageView(
                                      controller: _pageController,
                                      onPageChanged: (index) => setState(() => _currentPage = index),
                                      children: [
                                        Column(
                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                          children: [
                                            _buildRecordWidget(),
                                            _buildMusicInfo(primaryColor),
                                            _buildActionButtons(primaryColor),
                                          ],
                                        ),
                                        const Column(
                                          children: [
                                            Expanded(
                                              child: LyricsScroller(),
                                            )
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PlayerProgress(color: primaryColor),
                            _buildControlButtons(primaryColor),
                            const SizedBox(height: 50),
                          ],
                        ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ignore: must_be_immutable
class PlayerProgress extends StatefulWidget {
  Color? color;

  PlayerProgress({
    super.key,
    this.color,
  });

  @override
  State<PlayerProgress> createState() => _PlayerProgressState();
}

class _PlayerProgressState extends State<PlayerProgress> {
  double _value = 0;
  bool _isChanged = false;
  List<StreamSubscription<Duration>?> listens = [];

  @override
  void initState() {
    final player = Provider.of<PlayerModel>(context, listen: false);
    super.initState();

    listens.add(player.listenPosition((event) {
      if (_isChanged || !mounted) return;
      double c = event.inSeconds.toDouble();
      double total = player.duration?.inSeconds.toDouble() ?? 0.0;
      double v = c / total;
      if (v.isNaN) return;
      if (v > 1.0) {
        v = 1.0;
      }
      if (v < 0.0) {
        v = 0;
      }
      setState(() {
        _value = v;
      });
    }));
  }

  @override
  void dispose() {
    for (final listen in listens) {
      listen?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = widget.color ?? Theme.of(context).primaryColor;

    return Consumer<PlayerModel>(builder: (context, player, child) {
      int total = (player.duration?.inSeconds ?? 0);

      return Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: CustomTrackShape(context, primaryColor),
              thumbShape: CustomThumbShape(context, primaryColor),
            ),
            child: Slider(
              value: _value,
              onChanged: (v) {
                setState(() {
                  _value = v;
                });
              },
              onChangeStart: (value) {
                setState(() {
                  _isChanged = true;
                });
              },
              onChangeEnd: (value) {
                final player = Provider.of<PlayerModel>(context, listen: false);
                int v = (value * total).toInt();
                player.seek(Duration(seconds: v));
                setState(() {
                  _isChanged = false;
                });
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.only(left: 24.0, right: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  seconds2duration((_value * total).toInt()),
                  style: TextStyle(color: primaryColor, fontSize: 12),
                ),
                Text(
                  seconds2duration(total),
                  style: TextStyle(color: primaryColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class CustomThumbShape extends SliderComponentShape {
  final BuildContext context;
  Color? color;

  CustomThumbShape(this.context, this.color);

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(0, 0);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final primaryColor = color ?? Theme.of(this.context).primaryColor;
    final canvas = context.canvas;
    final paint = Paint()..color = primaryColor;
    canvas.drawCircle(center, 4, paint);
  }
}

class CustomTrackShape extends RoundedRectSliderTrackShape {
  final BuildContext context;
  Color? color;

  CustomTrackShape(this.context, this.color);

  Rect getPreferredSize({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    double trackHeight = 2;
    double trackWidth = parentBox.size.width - 48;
    return Rect.fromLTWH(offset.dx, offset.dy, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final canvas = context.canvas;
    final primaryColor = color ?? Theme.of(this.context).primaryColor;
    final Rect trackRect = getPreferredSize(
      parentBox: parentBox,
      offset: Offset(24, thumbCenter.dy - 1),
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final Paint activeTrackPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    final double thumbX = thumbCenter.dx;
    final Rect activeTrackRect = Rect.fromLTWH(
      trackRect.left,
      trackRect.top,
      thumbX - trackRect.left,
      trackRect.height,
    );
    canvas.drawRect(activeTrackRect, activeTrackPaint);

    final Paint inactiveTrackPaint = Paint()
      ..color = primaryColor.withOpacity(0.7)
      ..style = PaintingStyle.fill;
    final Rect inactiveTrackRect = Rect.fromLTWH(
      thumbX,
      trackRect.top,
      trackRect.right - thumbX,
      trackRect.height,
    );
    canvas.drawRect(inactiveTrackRect, inactiveTrackPaint);
  }
}
