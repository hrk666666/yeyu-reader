import 'package:flutter/material.dart';

import '../../services/episode_source_cache.dart';
import '../../theme/md3.dart';
import '../../services/playback_format.dart';
import '../../services/player_preferences.dart';

/// 竖屏底栏「倍速」「清晰度」的档位弹层。
///
/// 这两项不再放进「视频设置」：底栏右下角已经写着当前档，点它要的是换档，
/// 不是再进一层设置列表。横屏同款入口走右侧面板
/// （[PlayerSidePanelOptionList]），这里只管竖屏的底部弹层。
///
/// 选中即 `pop(值)` 并收起，由宿主落地（倍速 `_applyRate` / 清晰度
/// `onQualitySelected`），与横屏档位面板同语义。
Future<double?> showPlayletRateSheet(
  BuildContext context, {
  required double rate,
  bool dark = true,
}) => _showOptionSheet<double>(
  context,
  dark: dark,
  child: PlayletOptionSheet<double>(
    sheetKey: 'player-rate-sheet',
    title: '倍速',
    dark: dark,
    isSelected: (value) => value == rate,
    options: [
      for (final value in PlayerPreferences.playbackRates)
        PlayletOption(
          // 档位文案用 chip 形（1x 而不是底栏上的「倍速」）。
          label: '${formatPlaybackRate(value)}x',
          value: value,
        ),
    ],
  ),
);

Future<EpisodeVariant?> showPlayletQualitySheet(
  BuildContext context, {
  required List<EpisodeVariant> variants,
  String? currentUrl,
  bool dark = true,
}) => _showOptionSheet<EpisodeVariant>(
  context,
  dark: dark,
  child: PlayletOptionSheet<EpisodeVariant>(
    sheetKey: 'player-quality-sheet',
    title: '清晰度',
    dark: dark,
    isSelected: (variant) => variant.url == currentUrl,
    options: [
      for (final variant in variants)
        PlayletOption(label: variant.name, value: variant),
    ],
  ),
);

Future<T?> _showOptionSheet<T>(
  BuildContext context, {
  required bool dark,
  required Widget child,
}) => showModalBottomSheet<T>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: dark
      ? Theme.of(context).colorScheme.inverseSurface
      : Theme.of(context).colorScheme.surfaceContainerLow,
  elevation: Md3Elevation.level1,
  shape: const RoundedRectangleBorder(borderRadius: Md3Shape.sheetTop),
  builder: (_) => child,
);

/// 档位弹层本体：拖拽手柄 + 居中标题 + 单选行。
///
/// 行高 48dp、选中档品牌橙 + 对勾；档位多的（清晰度三档以上）在弹层高度
/// 内可滚，不会把弹层撑到盖住整屏。
class PlayletOptionSheet<T> extends StatelessWidget {
  const PlayletOptionSheet({
    super.key,
    required this.title,
    required this.options,
    required this.isSelected,
    required this.sheetKey,
    this.dark = true,
  });

  final String title;
  final List<PlayletOption<T>> options;
  final bool Function(T value) isSelected;

  /// 弹层根 key（`player-rate-sheet` / `player-quality-sheet`）与档位 key
  /// 前缀：档位渲染成 `ValueKey('$sheetKey-$index')`。
  final String sheetKey;

  /// 深色（`#1C1C1C`）或浅色（`#FAFAFA`）皮肤，与视频设置面板同源。
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSheet = dark ? scheme.onInverseSurface : scheme.onSurface;
    return SafeArea(
      top: false,
      child: Column(
        key: ValueKey(sheetKey),
        mainAxisSize: MainAxisSize.min,
        children: [
          // The official showDragHandle draws the handle; keep the key as a
          // zero-height anchor for widget tests.
          const SizedBox(
            key: ValueKey('player-option-drag-handle'),
            height: 0,
            width: double.infinity,
          ),
          SizedBox(
            height: 44,
            child: Center(
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(color: onSheet),
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Md3Shape.small),
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                final selected = isSelected(option.value);
                return ListTile(
                  key: ValueKey('$sheetKey-$index'),
                  dense: true,
                  selected: selected,
                  selectedTileColor: scheme.secondaryContainer,
                  title: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: selected
                          ? scheme.onSecondaryContainer
                          : onSheet,
                    ),
                  ),
                  trailing: selected
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: scheme.onSecondaryContainer,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, option.value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 档位弹层的一项。
class PlayletOption<T> {
  const PlayletOption({required this.label, required this.value});

  final String label;
  final T value;
}
