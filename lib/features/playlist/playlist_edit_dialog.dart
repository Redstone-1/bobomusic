import "dart:async";
import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../core/widgets/app_form_field.dart";
import "../../core/widgets/app_checkbox_row.dart";
import "../../data/models/playlist.dart";
import "../../data/playlist_cover_store.dart";
import "display_edit_actions.dart";
import "playlists_provider.dart";

Future<void> showPlaylistEditDialog(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  // 打开前按 ID 重读，避免从保留中的目录拿到旧名称或旧封面。
  try {
    final latest = await ref.read(playlistInfoProvider(playlist.id).future);
    if (!context.mounted) return;
    if (latest == null) {
      AppToast.show(context, "歌单已不存在");
      return;
    }
    await AppDialog.show<void>(context,
        barrierDismissible: false,
        padding: EdgeInsets.zero,
        content: Flexible(child: _PlaylistEditor(playlist: latest)),
        actions: const []);
  } catch (error) {
    print("读取歌单信息失败：$error");
    if (context.mounted) AppToast.show(context, "读取歌单信息失败，请重试");
  }
}

class _PlaylistEditor extends ConsumerStatefulWidget {
  const _PlaylistEditor({required this.playlist});
  final Playlist playlist;

  @override
  ConsumerState<_PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends ConsumerState<_PlaylistEditor> {
  final _form = GlobalKey<FormState>();
  final _store = PlaylistCoverStore();
  final _staged = <String>[];
  late final _name = TextEditingController(text: widget.playlist.name);
  late final _url = TextEditingController(
      text: Uri.tryParse(widget.playlist.customCover ?? "")?.scheme == "file"
          ? ""
          : widget.playlist.customCover);
  late String? _localCover =
      Uri.tryParse(widget.playlist.customCover ?? "")?.scheme == "file"
          ? widget.playlist.customCover
          : null;
  bool _apply = false;
  bool _busy = false;

  String? get _cover =>
      _localCover ?? (_url.text.trim().isEmpty ? null : _url.text.trim());

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    for (final cover in _staged) {
      unawaited(_store.removeIfUnused(cover));
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFile(
          type: FileType.image, dialogTitle: "选择歌单封面");
      if (picked?.path == null) return;
      final cover = await _store.importFile(File(picked!.path!));
      if (!mounted) {
        await _store.removeIfUnused(cover);
        return;
      }
      _staged.add(cover);
      setState(() {
        _localCover = cover;
        _url.clear();
      });
    } catch (error) {
      print("选择歌单封面失败：$error");
      if (mounted) {
        AppToast.show(
            context, error is FormatException ? error.message : "无法读取图片，请重新选择");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final displayActions = ref.read(trackDisplayActionsProvider);
      final changedIds = await ref.read(playlistsProvider.notifier).updateInfo(
          widget.playlist.id,
          name: _name.text.trim(),
          customCover: _cover,
          applyCoverToTracks: _apply && _cover != null);
      var refreshed = true;
      if (changedIds.isNotEmpty) {
        refreshed = await displayActions.refresh(changedIds);
      }
      await _store.removeIfUnused(widget.playlist.customCover);
      if (!mounted) return;
      AppToast.show(
          context,
          !refreshed
              ? "歌单已保存，歌曲显示刷新失败，请稍后重试"
              : _apply
                  ? "已保存并更新歌曲封面"
                  : "已保存歌单信息");
      Navigator.of(context).pop();
    } catch (error) {
      print("保存歌单信息失败：$error");
      if (mounted) AppToast.show(context, "保存失败，请检查歌单名称是否重复后重试");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    return PopScope(
        canPop: !_busy,
        child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
                child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 封面全宽出血铺满弹窗上部（约 1/3），顶部两角随弹窗圆角裁切
                  ClipRRect(
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(t.radiusLg)),
                      child: SizedBox(
                          height: 160,
                          child: Stack(fit: StackFit.expand, children: [
                            CoverPlaceholder(
                                cover:
                                    _cover ?? widget.playlist.fallbackCover,
                                text: _name.text.trim().isEmpty
                                    ? widget.playlist.name
                                    : _name.text.trim(),
                                width: double.infinity,
                                height: 160,
                                radius: 0),
                            // 边缘渐隐：贴近封面处透明露出图片，向下过渡到面板底色
                            Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                      t.bg2.withValues(alpha: 0),
                                      t.bg2,
                                    ])))),
                          ]))),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppDialog.titleText(context, "编辑歌单信息"),
                            const SizedBox(height: 14),
                            AppFormField(
                                key: const Key("playlist_edit_name"),
                                controller: _name,
                                enabled: !_busy,
                                label: "歌单名称",
                                onChanged: (_) => setState(() {}),
                                validator: (value) {
                                  final name = value?.trim() ?? "";
                                  if (name.isEmpty) return "歌单名不能为空";
                                  if (name.length > 20) return "歌单名最长 20 个字符";
                                  if (name != widget.playlist.name &&
                                      RegExp(r"^\d").hasMatch(name)) {
                                    return "歌单名不能以数字开头";
                                  }
                                  return null;
                                }),
                            const SizedBox(height: 12),
                            AppFormField(
                                key: const Key("playlist_edit_cover"),
                                controller: _url,
                                enabled: !_busy,
                                label: "封面图片链接",
                                suffix: IconButton(
                                    tooltip: "从设备选择",
                                    onPressed: _busy ? null : _pickImage,
                                    icon:
                                        const Icon(Icons.image_outlined)),
                                onChanged: (_) => setState(() {
                                      _localCover = null;
                                    }),
                                validator: (value) {
                                  if (_apply && _cover == null) {
                                    return "请先选择图片或填写图片链接";
                                  }
                                  if (value == null || value.trim().isEmpty) {
                                    return null;
                                  }
                                  final uri = Uri.tryParse(value.trim());
                                  return uri != null &&
                                          (uri.scheme == "https" ||
                                              uri.scheme == "http") &&
                                          uri.host.isNotEmpty
                                      ? null
                                      : "请输入有效的 http 或 https 图片链接";
                                }),
                            AppCheckboxRow(
                                key: const Key("playlist_apply_cover"),
                                label: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text("将歌单封面应用到此歌单的全部歌曲",
                                        maxLines: 1,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                _busy ? t.fgMute : t.fg))),
                                value: _apply,
                                onChanged: _busy
                                    ? null
                                    : (value) =>
                                        setState(() => _apply = value)),
                            const SizedBox(height: 18),
                            Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => Navigator.of(context).pop(),
                                      child: Text("取消",
                                          style: TextStyle(
                                              color: _busy
                                                  ? t.fgMute
                                                  : t.fgDim))),
                                  Flexible(
                                      child: TextButton(
                                          key:
                                              const Key("playlist_edit_save"),
                                          onPressed: _busy ? null : _save,
                                          child: Text(
                                              _busy
                                                  ? "处理中…"
                                                  : _apply && _cover != null
                                                      ? "保存并更新 ${widget.playlist.count} 首歌曲"
                                                      : "保存",
                                              style: TextStyle(
                                                  color: _busy
                                                      ? t.fgMute
                                                      : t.primary,
                                                  fontWeight:
                                                      FontWeight.w700)))),
                                ]),
                          ])),
                ],
              ),
            ))));
  }
}
