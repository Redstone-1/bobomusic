import "dart:async";
import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_dialog.dart";
import "../../core/overlays/app_toast.dart";
import "../../core/overlays/app_sheet.dart";
import "../../core/theme/aurora_tokens.dart";
import "../../core/widgets/aurora_background.dart";
import "../../core/widgets/desktop_content.dart";
import "../../core/widgets/page_header.dart";
import "../../core/widgets/app_form_field.dart";
import "../../core/widgets/app_checkbox_row.dart";
import "../../core/widgets/cover_placeholder.dart";
import "../../data/models/track.dart";
import "../../data/models/track_display_edit.dart";
import "../../data/playlist_cover_store.dart";
import "../../data/repositories/track_repository.dart";
import "../../data/track_rename.dart";
import "../player/mini_player_bar.dart";
import "../player/playback_provider.dart";
import "display_edit_actions.dart";

enum BatchTrackEditMode {
  rename("批量重命名"),
  author("批量设置歌手"),
  cover("批量设置封面");

  const BatchTrackEditMode(this.title);
  final String title;
}

class BatchTrackEditPage extends ConsumerStatefulWidget {
  const BatchTrackEditPage(
      {super.key, required this.tracks, required this.mode});
  final List<Track> tracks;
  final BatchTrackEditMode mode;

  @override
  ConsumerState<BatchTrackEditPage> createState() => _BatchTrackEditPageState();
}

class _RenameDraft {
  // 不跳过手动编辑过的条目：用户想改就改，命中规则即默认勾选。
  _RenameDraft(this.suggestion)
      : name = suggestion.name,
        author = suggestion.author,
        selected = suggestion.confident && suggestion.changed;
  final TrackRenameSuggestion suggestion;
  String name;
  String author;
  bool selected;
  bool get changed =>
      name != suggestion.track.effectiveName ||
      author != suggestion.track.effectiveAuthor;
}

class _BatchTrackEditPageState extends ConsumerState<BatchTrackEditPage> {
  TrackRenameRule _rule = TrackRenameRule.leadingDigits;
  final _removeChars = TextEditingController();
  final _value = TextEditingController();
  final _coverStore = PlaylistCoverStore();
  final _stagedCovers = <String>[];
  final _previousCovers = <String>{};
  String? _localCover;
  Future<DisplayEditResult>? _pendingWrite;
  bool _busy = false;
  // 最后一次写库方向仅用于刷新失败提示文案（保存 / 撤销）。
  bool _lastWasUndo = false;
  List<TrackDisplayEdit>? _undo;
  bool _refreshPending = false;
  List<String> _refreshIds = const [];
  // 应用/撤销成功后按库内最新数据重读，页面保持可继续操作。
  late List<Track> _tracks = widget.tracks;
  late List<_RenameDraft> _drafts = _suggest();

  @override
  void initState() {
    super.initState();
    // 入口传入的是详情页列表快照，可能落后于库内最新编辑；
    // 进入即按库内数据重建预览，写库/撤销后也走同一重读。
    unawaited(_reloadFromDb());
  }

  bool get _renaming => widget.mode == BatchTrackEditMode.rename;
  bool get _settingCover => widget.mode == BatchTrackEditMode.cover;
  String get _cover => _localCover ?? _value.text.trim();
  Key _key(String name) =>
      Key(_renaming ? "rename_$name" : "batch_${widget.mode.name}_$name");

  String? _validateValue(String? value) {
    if (!_settingCover) {
      return value?.trim().isNotEmpty == true ? null : "请填写新的歌手名称";
    }
    if (_localCover != null) return null;
    final uri = Uri.tryParse(value?.trim() ?? "");
    return uri != null &&
            (uri.scheme == "https" || uri.scheme == "http") &&
            uri.host.isNotEmpty
        ? null
        : "请填写有效的 http 或 https 图片链接，或从设备选择图片";
  }

  bool _changed(_RenameDraft draft) {
    if (_renaming) return draft.changed;
    if (_validateValue(_value.text) != null) return false;
    final track = draft.suggestion.track;
    return _settingCover
        ? _cover != track.effectiveCover
        : _value.text.trim() != track.effectiveAuthor;
  }

  static const _ruleLabels = {
    TrackRenameRule.leadingDigits: "清除开头数字",
    TrackRenameRule.specialChars: "清除特殊字符",
    TrackRenameRule.removeChars: "删除指定字符",
  };

  // 规则自身图标 + 选中瓦片高亮，不再用对勾图标表达选择态。
  static const _ruleIcons = {
    TrackRenameRule.leadingDigits: Icons.format_list_numbered,
    TrackRenameRule.specialChars: Icons.auto_fix_high,
    TrackRenameRule.removeChars: Icons.backspace_outlined,
  };

  void _chooseRule() {
    FocusManager.instance.primaryFocus?.unfocus();
    AppSheet.show(context, inset: true, actions: [
      for (final entry in _ruleLabels.entries)
        AppSheetAction(
          icon: _ruleIcons[entry.key]!,
          label: entry.value,
          selected: entry.key == _rule,
          onTap: () {
            if (!mounted) return;
            _rule = entry.key;
            _regenerate();
          },
        ),
    ]);
  }

  List<_RenameDraft> _suggest() => !_renaming
      ? [
          for (final track in _tracks)
            _RenameDraft(TrackRenameSuggestion(
                track: track,
                name: track.effectiveName,
                author: track.effectiveAuthor,
                confident: false,
                reason: ""))
              ..selected = true
        ]
      : suggestTrackRenames(_tracks,
              rule: _rule, removeChars: _removeChars.text)
          .map(_RenameDraft.new)
          .toList();

  // 预览是规则与输入的纯函数：规则切换或输入变化时实时重算，无需手动刷新。
  // 副作用：改规则或输入会覆盖手动单首编辑，属可预期行为。
  void _regenerate() => setState(() {
        _drafts = _suggest();
      });

  @override
  void dispose() {
    _removeChars.dispose();
    _value.dispose();
    unawaited(_cleanupCovers(_pendingWrite));
    super.dispose();
  }

  Future<void> _cleanupCovers(Future<DisplayEditResult>? pending) async {
    // 保存期间被外部路由移除时，先等事务结束，避免误删即将被歌曲引用的图片。
    try {
      final result = await pending;
      if (result != null) _rememberPreviousCovers(result);
    } catch (_) {
      // 保存失败已由应用入口处理，此处仍需回收未被引用的临时图片。
    }
    // 本页仍可撤销时不回收旧图；离页后再按最终库内引用清理新旧副本。
    for (final cover in {..._stagedCovers, ..._previousCovers}) {
      await _coverStore.removeIfUnused(cover);
    }
  }

  void _rememberPreviousCovers(DisplayEditResult result) {
    for (final edit in result.undo) {
      if (edit.updateCover && edit.cover != null) {
        _previousCovers.add(edit.cover!);
      }
    }
  }

  Future<void> _pickCover() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFile(
          type: FileType.image, dialogTitle: "选择歌曲封面");
      if (picked?.path == null) return;
      final cover = await _coverStore.importFile(File(picked!.path!));
      if (!mounted) {
        await _coverStore.removeIfUnused(cover);
        return;
      }
      _stagedCovers.add(cover);
      setState(() {
        _localCover = cover;
        _value.clear();
      });
    } catch (error) {
      print("选择批量封面失败：$error");
      if (mounted) {
        AppToast.show(
            context, error is FormatException ? error.message : "无法读取图片，请重新选择");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(_RenameDraft draft) async {
    final t = AuroraTokens.of(context);
    var name = draft.name;
    var author = draft.author;
    final form = GlobalKey<FormState>();
    final result = await AppDialog.show<({String name, String author})>(
      context,
      title: "编辑重命名建议",
      content: Flexible(
          child: SingleChildScrollView(
              child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppFormField(
                          initialValue: name,
                          label: "建议歌名",
                          onChanged: (value) => name = value,
                          validator: (value) => value?.trim().isNotEmpty == true
                              ? null
                              : "歌名不能为空"),
                      const SizedBox(height: 10),
                      AppFormField(
                          initialValue: author,
                          label: "建议歌手",
                          onChanged: (value) => author = value),
                    ],
                  )))),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: Text("取消", style: TextStyle(color: t.fgDim))),
        TextButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.of(context, rootNavigator: true)
                    .pop((name: name.trim(), author: author.trim()));
              }
            },
            child: Text("确认建议",
                style:
                    TextStyle(color: t.primary, fontWeight: FontWeight.w700))),
      ],
    );
    if (result == null || !mounted) return;
    setState(() {
      draft.name = result.name;
      draft.author = result.author.isEmpty
          ? draft.suggestion.track.effectiveAuthor
          : result.author;
      draft.selected = draft.selected || draft.changed;
    });
  }

  Future<void> _apply() async {
    final edits = [
      for (final draft in _drafts)
        if (draft.selected && (!_renaming || _changed(draft)))
          if (!_renaming)
            TrackDisplayEdit(
                trackId: draft.suggestion.track.id,
                author: _settingCover ? null : _value.text.trim(),
                cover: _settingCover ? _cover : null,
                updateAuthor: !_settingCover,
                updateCover: _settingCover,
                validateOnly: !_changed(draft),
                expected: draft.suggestion.track)
          else
            TrackDisplayEdit(
              trackId: draft.suggestion.track.id,
              name: draft.name,
              author: draft.author,
              updateName: draft.name != draft.suggestion.track.effectiveName,
              updateAuthor:
                  draft.author != draft.suggestion.track.effectiveAuthor,
              expected: draft.suggestion.track,
            ),
    ];
    if (!edits.any((edit) => !edit.validateOnly) || _busy) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      final write = ref.read(trackDisplayActionsProvider).apply(edits);
      _pendingWrite = write;
      final result = await write;
      _rememberPreviousCovers(result);
      if (!mounted) return;
      setState(() {
        _undo = result.undo;
        _lastWasUndo = false;
        _refreshPending = !result.refreshed;
        _refreshIds = edits.map((edit) => edit.trackId).toList();
      });
      AppToast.show(
          context,
          result.refreshed
              ? "已更新 ${result.undo.length} 首歌曲"
              : "修改已保存，界面刷新失败，可重试刷新");
      // 按库内最新数据重建预览，本页可直接继续下一轮操作。
      await _reloadFromDb();
    } catch (error) {
      print("${widget.mode.title}失败：$error");
      if (mounted) {
        AppToast.show(
            context, error is StateError ? error.message : "保存失败，本批修改未应用，请重试");
      }
    } finally {
      _pendingWrite = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoChanges() async {
    final undo = _undo;
    if (undo == null || _busy) return;
    setState(() => _busy = true);
    try {
      final write = ref.read(trackDisplayActionsProvider).apply(undo);
      _pendingWrite = write;
      final result = await write;
      _rememberPreviousCovers(result);
      if (!mounted) return;
      setState(() {
        // 撤销事务已成功，刷新失败时也不能保留已执行过的反向操作。
        _undo = null;
        _lastWasUndo = true;
        _refreshPending = !result.refreshed;
        _refreshIds = undo.map((edit) => edit.trackId).toList();
      });
      AppToast.show(
          context, result.refreshed ? "已恢复本次操作前的信息" : "修改已撤销，界面刷新失败，可重试刷新");
      await _reloadFromDb();
    } catch (error) {
      print("撤销${widget.mode.title}失败：$error");
      if (mounted) {
        AppToast.show(context,
            error is StateError ? "歌曲又被编辑过，无法撤销，请重新查看歌曲信息" : "撤销失败，请重试");
      }
    } finally {
      _pendingWrite = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryRefresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final refreshed =
          await ref.read(trackDisplayActionsProvider).refresh(_refreshIds);
      if (!mounted) return;
      setState(() => _refreshPending = !refreshed);
      AppToast.show(context, refreshed ? "已刷新歌曲信息" : "界面刷新失败，请稍后重试");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 按库内最新数据重读并重建预览，顺序与原列表保持一致。
  Future<void> _reloadFromDb() async {
    try {
      final fresh =
          await TrackRepository().getByIds(_tracks.map((t) => t.id).toList());
      final byId = {for (final track in fresh) track.id: track};
      final ordered = [
        for (final track in _tracks)
          if (byId[track.id] != null) byId[track.id]!
      ];
      if (!mounted) return;
      setState(() {
        _tracks = ordered;
        _drafts = _suggest();
      });
    } catch (error) {
      // 重读失败不影响已保存的数据，保留当前预览即可继续操作。
      print("重读曲目信息失败：$error");
    }
  }

  Widget _batchInputs(bool disabled) {
    final t = AuroraTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_settingCover) ...[
        Center(
            child: CoverPlaceholder(
                cover: _validateValue(_value.text) == null ? _cover : null,
                size: 80,
                radius: t.radiusMd)),
        const SizedBox(height: 12),
      ],
      AppFormField(
          key: _key("value"),
          controller: _value,
          label: _settingCover ? "新封面图片链接" : "新的歌手名称",
          helper:
              _settingCover && _localCover != null ? "已选择设备图片，填写链接可替换" : null,
          enabled: !disabled,
          keyboardType: _settingCover ? TextInputType.url : null,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: _validateValue,
          suffix: _settingCover
              ? IconButton(
                  key: _key("pick_cover"),
                  tooltip: "从设备选择",
                  onPressed: disabled ? null : _pickCover,
                  icon: const Icon(Icons.image_outlined))
              : null,
          onChanged: (_) => setState(() {
                // 更新输入只更新预览，保留用户逐首调整过的勾选。
                _localCover = null;
              })),
      if (_settingCover)
        TextButton(
            onPressed: disabled
                ? null
                : () => setState(() {
                      _localCover = null;
                      _value.clear();
                    }),
            child: const Text("清除输入")),
    ]);
  }

  Widget _batchPreview(_RenameDraft draft) {
    final t = AuroraTokens.of(context);
    final track = draft.suggestion.track;
    final valid = _validateValue(_value.text) == null;
    Widget coverPreview(String label, String? cover) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: t.fgDim, fontSize: 12)),
          const SizedBox(height: 4),
          CoverPlaceholder(
              cover: cover,
              text: track.effectiveName,
              size: 40,
              radius: t.radiusSm),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(track.effectiveName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: t.fg, fontSize: 14)),
      const SizedBox(height: 4),
      if (_settingCover)
        Wrap(spacing: 16, runSpacing: 8, children: [
          coverPreview("原封面", track.effectiveCover),
          coverPreview("新封面", valid ? _cover : null),
        ])
      else
        Text(
            "原歌手：${track.effectiveAuthor.isEmpty ? "未填写" : track.effectiveAuthor}\n"
            "新歌手：${valid ? _value.text.trim() : "待填写"}",
            style: TextStyle(color: t.fgDim, fontSize: 12, height: 1.5)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = AuroraTokens.of(context);
    final selected = _drafts.where((d) => d.selected).length;
    final changes = _drafts.where((d) => d.selected && _changed(d)).length;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final hasMiniPlayer = !keyboardVisible &&
        !DesktopContent.of(context) &&
        ref.watch(playbackProvider.select((s) => s.track != null));
    final duplicates = <String, int>{};
    for (final draft in _drafts) {
      duplicates.update(draft.name, (n) => n + 1, ifAbsent: () => 1);
    }
    final disabled = _busy;
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
            body: AuroraBackground(
          child: MiniBarPage(
              showMiniPlayer: !keyboardVisible,
              child: SafeArea(
                  child: Column(children: [
                Expanded(
                    child: CustomScrollView(slivers: [
                  SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text("返回歌曲列表")),
                              PageHeader(
                                  title: widget.mode.title,
                                  subtitle: "共 ${_drafts.length} 首 · 预览确认后应用"),
                              const SizedBox(height: 12),
                              Text(
                                  _renaming
                                      ? "只修改勾选项；同一首歌在其他歌单和播放器中的名称、歌手也会同步更新。"
                                      : "默认选中全部，可逐首取消勾选；只修改本次设置的${_settingCover ? "封面" : "歌手"}，同一首歌在其他歌单和播放器中也会同步更新。",
                                  style: TextStyle(
                                      color: t.fgDim,
                                      fontSize: 12,
                                      height: 1.5)),
                              const SizedBox(height: 12),
                              if (!_renaming) _batchInputs(disabled),
                              if (_renaming)
                                AppSelectionField(
                                    key: const Key("rename_rule"),
                                    value: _ruleLabels[_rule]!,
                                    onTap: disabled ? null : _chooseRule),
                              if (_renaming &&
                                  _rule == TrackRenameRule.removeChars) ...[
                                const SizedBox(height: 12),
                                AppFormField(
                                    key: const Key("rename_remove_chars"),
                                    controller: _removeChars,
                                    enabled: !disabled,
                                    label: "要删除的指定字符",
                                    onChanged: (_) => _regenerate()),
                              ],
                              if (_refreshPending)
                                Row(children: [
                                  Expanded(
                                      child: Text(
                                          _lastWasUndo
                                              ? "修改已撤销，界面刷新待重试"
                                              : "修改已保存，界面刷新待重试",
                                          style: TextStyle(color: t.fgDim))),
                                  TextButton(
                                      key: _key("retry_refresh"),
                                      onPressed: _busy ? null : _retryRefresh,
                                      child: const Text("重试刷新")),
                                ]),
                              if (_undo != null)
                                Row(children: [
                                  Expanded(
                                      child: Text("本次修改已保存",
                                          style: TextStyle(color: t.primary))),
                                  TextButton(
                                      key: _key("undo"),
                                      onPressed: _busy ? null : _undoChanges,
                                      child: const Text("撤销本次修改")),
                                ]),
                            ]),
                      )),
                  SliverList.builder(
                      itemCount: _drafts.length,
                      itemBuilder: (context, index) {
                        final draft = _drafts[index];
                        final track = draft.suggestion.track;
                        return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            child: AppCheckboxRow(
                              key: _key("track_${track.id}"),
                              value: draft.selected,
                              onChanged: disabled
                                  ? null
                                  : (value) =>
                                      setState(() => draft.selected = value),
                              label: !_renaming
                                  ? _batchPreview(draft)
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                          Text(
                                              "${draft.name} · ${draft.author.isEmpty ? "未填写歌手" : draft.author}",
                                              style: TextStyle(
                                                  color: t.fg, fontSize: 14)),
                                          const SizedBox(height: 4),
                                          Text(
                                              "原：${track.effectiveName} · ${track.effectiveAuthor.isEmpty ? "未填写歌手" : track.effectiveAuthor}\n"
                                              "${draft.suggestion.reason}"
                                              "${(duplicates[draft.name] ?? 0) > 1 ? "\n存在同名歌曲，各自保留" : ""}",
                                              style: TextStyle(
                                                  color: t.fgDim,
                                                  fontSize: 12,
                                                  height: 1.5)),
                                        ]),
                              trailing: !_renaming
                                  ? null
                                  : IconButton(
                                      key: ValueKey("rename_edit_${track.id}"),
                                      tooltip: "编辑建议",
                                      onPressed:
                                          disabled ? null : () => _edit(draft),
                                      icon: const Icon(Icons.edit_note)),
                            ));
                      }),
                ])),
                Padding(
                    padding: EdgeInsets.fromLTRB(
                        20, 12, 20, hasMiniPlayer ? 100 : 16),
                    child: Row(children: [
                      // 三态全选：全选=勾、全不选=空、部分=横线；
                      // 点击只看当前状态（未全选→全选，已全选→清空），与回调值无关。
                      SizedBox(
                          width: 32,
                          height: 40,
                          child: Checkbox(
                              key: _key("toggle_all"),
                              tristate: true,
                              value: _drafts.isEmpty
                                  ? false
                                  : selected == _drafts.length
                                      ? true
                                      : selected == 0
                                          ? false
                                          : null,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: disabled
                                  ? null
                                  : (_) => setState(() {
                                        final selectAll =
                                            selected != _drafts.length;
                                        for (final draft in _drafts) {
                                          draft.selected = selectAll;
                                        }
                                      }))),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text("已选 $selected 首",
                              style: TextStyle(color: t.fgDim))),
                      FilledButton(
                          key: _key("apply"),
                          onPressed: disabled || changes == 0 ? null : _apply,
                          child: Text(_busy
                              ? "处理中…"
                              : "应用所选 $changes 首")),
                    ])),
              ]))),
        )));
  }
}
