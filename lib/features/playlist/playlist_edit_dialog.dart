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
        title: "编辑歌单信息",
        barrierDismissible: false,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: CoverPlaceholder(
                          cover: _cover ?? widget.playlist.fallbackCover,
                          text: _name.text.trim().isEmpty
                              ? widget.playlist.name
                              : _name.text.trim(),
                          size: 100,
                          radius: t.radiusMd)),
                  const SizedBox(height: 12),
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
                      helper: _localCover == null ? "也可从设备选择图片" : "已选择本地图片",
                      onChanged: (_) => setState(() {
                            _localCover = null;
                          }),
                      validator: (value) {
                        if (_apply && _cover == null) return "请先选择图片或填写图片链接";
                        if (value == null || value.trim().isEmpty) return null;
                        final uri = Uri.tryParse(value.trim());
                        return uri != null &&
                                (uri.scheme == "https" ||
                                    uri.scheme == "http") &&
                                uri.host.isNotEmpty
                            ? null
                            : "请输入有效的 http 或 https 图片链接";
                      }),
                  Wrap(spacing: 8, children: [
                    TextButton.icon(
                        onPressed: _busy ? null : _pickImage,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text("从设备选择")),
                    TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _localCover = null;
                                  _url.clear();
                                  _apply = false;
                                }),
                        child: const Text("恢复默认封面")),
                  ]),
                  AppCheckboxRow(
                      key: const Key("playlist_apply_cover"),
                      label: Text("将歌单封面应用到此歌单的全部歌曲",
                          style: TextStyle(
                              fontSize: 13, color: _busy ? t.fgMute : t.fg)),
                      value: _apply,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _apply = value)),
                  if (_apply && _cover == null)
                    Text("请先设置自定义封面，再保存并应用到歌曲。",
                        style: TextStyle(
                            color: t.fgDim, fontSize: 12, height: 1.5)),
                  if (_apply && _cover != null)
                    Text(
                        "将覆盖当前 ${widget.playlist.count} 首歌曲的封面（包括已自定义封面）。这些歌曲在其他歌单和播放器中也会同步变化。以后新增歌曲不绑定此封面。",
                        style: TextStyle(
                            color: t.fgDim, fontSize: 12, height: 1.5)),
                  const SizedBox(height: 18),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        child: Text("取消",
                            style:
                                TextStyle(color: _busy ? t.fgMute : t.fgDim))),
                    Flexible(
                        child: TextButton(
                            key: const Key("playlist_edit_save"),
                            onPressed: _busy ? null : _save,
                            child: Text(
                                _busy
                                    ? "处理中…"
                                    : _apply && _cover != null
                                        ? "保存并更新 ${widget.playlist.count} 首歌曲"
                                        : "保存",
                                style: TextStyle(
                                    color: _busy ? t.fgMute : t.primary,
                                    fontWeight: FontWeight.w700)))),
                  ]),
                ],
              ),
            ))));
  }
}
