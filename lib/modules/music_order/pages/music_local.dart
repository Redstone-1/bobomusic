// ignore_for_file: use_build_context_synchronously

import "dart:async";

import "package:bobomusic/components/custom_dialog/custom_dialog.dart";
import "package:bobomusic/components/empty_page/empty_page.dart";
import "package:bobomusic/components/music_list_tile/music_list_tile.dart";
import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/music_order/components/audio_scanner.dart";
import "package:bobomusic/modules/music_order/components/edit_music.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/permission/permission.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:provider/provider.dart";
import "package:uuid/uuid.dart";

final DBOrder db = DBOrder(version: 2);
const Uuid uuid = Uuid();

class MusicLocal extends StatefulWidget {
  const MusicLocal({super.key});

  @override
  State<MusicLocal> createState() => MusicLocalState();
}

class MusicLocalState extends State<MusicLocal> {
  List<MusicItem> musicList = [];

  @override
  void initState() {
    super.initState();
    _loadData();

    eventBus.on<ClearMusicList>().listen((event) {
      _clearData();
    });
    eventBus.on<ScanLocalList>().listen((event) {
      scanLocalMusics();
    });
    eventBus.on<ScanLocalListWithoutLoading>().listen((event) {
      scanLocalMusics0();
    });
  }

  Future<void> _loadData() async {
    musicList.clear();
    final musics = await getUpdatedMusicList(tabName: TableName.musicLocal);

    if (mounted && musics.isNotEmpty) {
      setState(() {
        musicList = musics;
      });
    } else {
      setState(() {
        musicList = [];
      });
    }
  }

  Future<void> _clearData() async {
    musicList.clear();
    EasyLoading.show(maskType: EasyLoadingMaskType.black);

    try {
      setState(() {
        musicList = [];
      });

      await db.deleteAll(TableName.musicLocal);
    } catch (error) {
      print(error);
    }

    EasyLoading.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: musicList.isEmpty ?
        SizedBox(
          height: MediaQuery.of(context).size.height - 240,
          child: EmptyPage(
            imageTopPadding: 50,
            imageBottomPadding: 50,
            text: "你还没有本地音乐",
            btns: [
              const SizedBox(height: 32),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.only(left: 32, right: 32),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4)))
                ),
                onPressed: () async {
                  await scanLocalMusics();
                },
                child: const Text("扫描本地音乐"),
              )
            ]
          ),
        ) :
        ListView.builder(
          padding: const EdgeInsets.only(bottom: 20),
          itemCount: musicList.length,
          itemBuilder: (context, index) {
            final item = musicList[index];
            return MusicListTile(
              item,
              showOrgin: false,
              onMore: () {
                showItemSheet(context, item);
              },
            );
          }
        ),
    );
  }

  /// 扫描本地音乐
  Future<void> scanLocalMusics() async {
    final hasPermission = await Permissions.requestAudioOrStoragePermission();

    if (!hasPermission) {
      return;
    }

    EasyLoading.show(maskType: EasyLoadingMaskType.black);

    Timer(const Duration(seconds: 1), () async {
      await scanLocalMusics0();
      EasyLoading.dismiss();
    });
  }

  Future<void> scanLocalMusics0() async {
    final (audioFiles, failedMusics) = await AudioScanner.scanAudios();

    if (audioFiles.isNotEmpty) {
      final List<MusicItem> newMusicList = [];
      await db.deleteAll(TableName.musicLocal);

      for (final audioFile in audioFiles) {
        final musicItem = MusicItem(
          id: uuid.v4(),
          cover: "",
          name: audioFile.title,
          duration: (audioFile.duration / 1000).floor(),
          author: audioFile.artist == "Unknown" ? "未知歌手" : audioFile.artist,
          origin: OriginType.local,
          playId: uuid.v4(),
          orderName: TableName.musicLocal,
          localPath: audioFile.path
        );

        newMusicList.add(musicItem);
        await db.insert(TableName.musicLocal, musicItem2Row(music: musicItem));
      }

      final updatedList = await getUpdatedMusicList(tabName: TableName.musicLocal);

      if (failedMusics.isEmpty) {
        setState(() {
          musicList = updatedList;
        });

        return;
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return CustomDialog(
            title: "以下歌曲扫描失败",
            body: SizedBox(
              height: MediaQuery.of(context).size.height / 4,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: failedMusics.asMap().entries.map((entry) {
                    return Text("${entry.key + 1}. ${entry.value}", style: const TextStyle(color: Colors.grey, fontSize: 10));
                  }).toList(),
                ),
              )
            ),
            onConfirm: () async {
              setState(() {
                musicList = updatedList;
              });

              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            onCancel: () {
              setState(() {
                musicList = updatedList;
              });

              Navigator.of(context).pop();
            },
          );
        },
      );
    } else {
      BotToast.showText(text: "本地没有音乐或者系统拒绝访问 QAQ", duration: const Duration(seconds: 3));
    }
  }

  // 工具函数：将毫秒数转换为 mm:ss 格式
  String formatDuration(int milliseconds) {
    int seconds = (milliseconds / 1000).floor();
    int minutes = (seconds / 60).floor();
    seconds = seconds % 60;

    String minutesStr = minutes.toString().padLeft(2, "0");
    String secondsStr = seconds.toString().padLeft(2, "0");

    return "$minutesStr:$secondsStr";
  }

  void showItemSheet(BuildContext context, MusicItem musicItem) {
    final player = Provider.of<PlayerModel>(context, listen: false);
    openBottomSheet(context, [
      SheetItem(
        title: Text(
          musicItem.name,
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      SheetItem(
        title: const Text("添加到歌单"),
        onPressed: () {
          collectToMusicOrder(context: context, musicList: [musicItem]);
        },
      ),
      SheetItem(
        title: const Text("添加到待播放列表"),
        onPressed: () {
          player.addPlayerList([musicItem], showToast: true);
        },
      ),
      SheetItem(
        title: const Text("编辑"),
        onPressed: () {
          Navigator.of(context).push(
            ModalBottomSheetRoute(
              isScrollControlled: true,
              builder: (context) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: EditMusic(
                    musicItem: musicItem,
                    onOk: (music) async {
                      await db.update(TableName.musicLocal, musicItem2Row(music: music));

                      if (player.current != null && player.current!.playId == music.playId) {
                        player.current = music;
                      }

                      _loadData();
                    },
                  )
                );
              },
            )
          );
        },
      ),
    ]);
  }
}
