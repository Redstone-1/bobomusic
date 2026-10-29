import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/overlays/app_sheet.dart";
import "../../core/theme/aurora_tokens.dart";
import "playback_provider.dart";
import "playback_speed.dart";

/// 复用应用面板与主题；保留面板方便连续试听，错误由应用壳统一提示。
void showPlaybackSpeedSheet(BuildContext context) {
  AppSheet.show(context, child: const _PlaybackSpeedSheet());
}

class _PlaybackSpeedSheet extends ConsumerStatefulWidget {
  const _PlaybackSpeedSheet();

  @override
  ConsumerState<_PlaybackSpeedSheet> createState() =>
      _PlaybackSpeedSheetState();
}

class _PlaybackSpeedSheetState extends ConsumerState<_PlaybackSpeedSheet> {
  double? _previewSpeed;
  bool _dragging = false;
  int _request = 0;

  void _startPreview(double speed) {
    setState(() {
      _dragging = true;
      _previewSpeed = speed;
    });
  }

  Future<void> _commitSpeed(double speed) async {
    final request = ++_request;
    setState(() {
      _dragging = false;
      _previewSpeed = speed;
    });
    // 只在松手或点刻度时提交；等待确认期间仍可继续操作，旧结果不能清掉新预览。
    await ref.read(playbackProvider.notifier).setSpeed(speed);
    if (!mounted || request != _request || _dragging) return;
    // 重新显示状态机的实际速度，平台拒绝时自然恢复上一次成功值。
    setState(() => _previewSpeed = null);
  }

  @override
  Widget build(BuildContext context) {
    final actualSpeed =
        ref.watch(playbackProvider.select((state) => state.speed));
    final speed = _previewSpeed ?? actualSpeed;
    final tokens = AuroraTokens.of(context);
    final speedLabel = playbackSpeedLabel(speed);
    final valueLabel = speedLabel.replaceFirst("×", "");
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "倍速播放",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
              ),
              TextButton(
                key: const Key("playback_speed_reset"),
                onPressed: () => _commitSpeed(1.0),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.fgDim,
                  overlayColor: tokens.surface2,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Text(
                  "恢复正常",
                  style: TextStyle(
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    decorationColor: tokens.hairlineStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text.rich(
            key: const Key("playback_speed_value"),
            TextSpan(
              text: "$valueLabel ",
              children: const [
                TextSpan(
                  text: "倍",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            semanticsLabel: "播放速度：$speedLabel",
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            speed == 1.0 ? "正常速度 · 变速不变调" : "变速不变调",
            style: TextStyle(fontSize: 12, color: tokens.fgMute),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              // 轨道端点对齐等宽刻度格的中心，窄屏与桌面共用同一布局。
              final inset =
                  constraints.maxWidth / (playbackSpeedPresets.length * 2);
              return Stack(
                children: [
                  SizedBox(
                    height: 40,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: tokens.primary,
                        inactiveTrackColor: tokens.hairlineStrong,
                        thumbColor: tokens.primary,
                        overlayColor: tokens.glow,
                        trackShape: const RoundedRectSliderTrackShape(),
                        tickMarkShape: SliderTickMarkShape.noTickMark,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                          elevation: 0,
                          pressedElevation: 0,
                        ),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 18),
                        showValueIndicator: ShowValueIndicator.never,
                      ),
                      child: Slider(
                        key: const Key("playback_speed_slider"),
                        value: speed,
                        min: playbackSpeedPresets.first,
                        max: playbackSpeedPresets.last,
                        divisions: playbackSpeedPresets.length - 1,
                        padding: EdgeInsets.symmetric(horizontal: inset),
                        semanticFormatterCallback: playbackSpeedLabel,
                        onChangeStart: _startPreview,
                        onChanged: (value) =>
                            setState(() => _previewSpeed = value),
                        onChangeEnd: _commitSpeed,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 26),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final value in playbackSpeedPresets)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: speed == value,
                              label: value == 1.0
                                  ? "1.0×，正常速度"
                                  : playbackSpeedLabel(value),
                              excludeSemantics: true,
                              onTap: () => _commitSpeed(value),
                              child: InkWell(
                                key: ValueKey("playback_speed_$value"),
                                onTap: () => _commitSpeed(value),
                                borderRadius:
                                    BorderRadius.circular(tokens.radiusSm),
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minHeight: 48),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 1,
                                          height: 4,
                                          color: speed == value
                                              ? tokens.primary
                                              : tokens.hairlineStrong,
                                        ),
                                        const SizedBox(height: 4),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            playbackSpeedLabel(value)
                                                .replaceFirst("×", ""),
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: speed == value
                                                  ? tokens.primary
                                                  : tokens.fgDim,
                                              fontWeight: speed == value
                                                  ? FontWeight.w700
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          value == 1.0 ? "正常" : " ",
                                          style: TextStyle(
                                              fontSize: 9,
                                              color: tokens.fgMute),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            "滑动或轻触刻度，松手生效",
            style: TextStyle(fontSize: 11, color: tokens.fgMute),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
