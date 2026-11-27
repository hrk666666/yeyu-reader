// 阅读器底部控制栏（官方 Material 3）。
// 进度胶囊用 Card.filled + 官方 Slider，动作坞用 Card.filled + InkWell，
// 翻页按钮用官方 IconButton，取色走 Theme.colorScheme / Md3Shape。
// 去掉 LiquidGlass / 玻璃按钮 / 玻璃滑条 / 果冻点击与自研阴影。
// DockLayout 仅保留几何常量；跨章 seek 的回调契约保持不变。
// 听书与视频胶囊在 reader_page_menu_players.dart，不属此坞。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/reader_preferences.dart';
import '../../theme/md3.dart';
import '../wenku/wenku_ui.dart';
import 'reader_theme.dart';

/// Reading menu. Listening starts from the separate round entry above this bar.
class ReaderControls extends StatelessWidget {
  final ReaderPreferences preferences;
  final int chapterIndex;
  final int chapterCount;
  final String chapterTitle;
  final double seekValue;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onDirectory;
  final VoidCallback onNight;
  final VoidCallback onAppearance;

  const ReaderControls({
    super.key,
    required this.preferences,
    required this.chapterIndex,
    required this.chapterCount,
    required this.chapterTitle,
    required this.seekValue,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    required this.onSeekEnd,
    required this.onDirectory,
    required this.onNight,
    required this.onAppearance,
  });

  @override
  Widget build(BuildContext context) {
    final preset = preferences.themePreset;
    final max = (chapterCount - 1).toDouble();
    final upper = max < 0 ? 0.0 : max;
    final tint = preset.panelColor;
    final night = preset.isDark;
    Widget content(BuildContext context) => Theme(
      data: preset.theme(Theme.of(context)),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _chapterLine(preset),
                  const SizedBox(height: 6),
                  // Upstream narrows the capsule and dock to their action
                  // count: `DockLayout.widthFor(5) - 32` and
                  // `DockLayout.widthFor(n)` (pages.dart). Centering keeps the
                  // glass compact on phones and tablets alike.
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: DockLayout.widthFor(5) - 32,
                      ),
                      child: _progressCapsule(context, preset, tint, upper),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: DockLayout.widthFor(3),
                      ),
                      child: _dock(context, preset, tint, night),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // 墨水屏：实时折射会在 EPD 上留下灰阶残影，坞与胶囊退回轻量底板。
    // Builder 让内容（包括玻璃滑条）真正位于这个 PerformanceScope 之下。
    return preset.isEink
        ? PerformanceScope(
            preferences: const PerformancePreferences(enabled: true),
            explicitReduceMotion: true,
            child: Builder(builder: content),
          )
        : Builder(builder: content);
  }

  /// Chapter title and ordinal stay visible above the capsule; upstream only
  /// shows them in the drag hint, but fqapp readers rely on the chapter name.
  Widget _chapterLine(ReaderThemePreset preset) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            chapterTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: preset.textColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${chapterIndex + 1} / $chapterCount',
          style: TextStyle(color: preset.mutedTextColor, fontSize: 12),
        ),
      ],
    ),
  );

  /// Upstream `ReaderChapterProgress(compact: true)`: one glass capsule with
  /// chapter-step icon actions on both ends and the shared glass slider inside.
  Widget _progressCapsule(
    BuildContext context,
    ReaderThemePreset preset,
    Color tint,
    double upper,
  ) {
    final value = seekValue.clamp(0, upper).toDouble();
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      key: const ValueKey('reader-progress-capsule'),
      color: scheme.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Md3Shape.extraLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('reader-previous-chapter'),
              tooltip: '上一章',
              icon: const Icon(CupertinoIcons.backward_end),
              onPressed: onPrevious,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Slider(
                key: const ValueKey('reader-chapter-seek'),
                value: value,
                min: 0,
                max: upper,
                divisions: chapterCount > 1 ? chapterCount - 1 : null,
                semanticFormatterCallback: (v) => '第 ${v.round() + 1} 章',
                onChanged: chapterCount > 1 ? onSeek : null,
                onChangeEnd: chapterCount > 1 ? onSeekEnd : null,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('reader-next-chapter'),
              tooltip: '下一章',
              icon: const Icon(CupertinoIcons.forward_end),
              onPressed: onNext,
            ),
          ],
        ),
      ),
    );
  }

  /// Upstream `_readerBottomControls` dock: one live glass capsule, icon over
  /// label, shared `DockLayout` geometry.
  Widget _dock(
    BuildContext context,
    ReaderThemePreset preset,
    Color tint,
    bool night,
  ) => Card.filled(
    key: const ValueKey('reader-liquid-dock'),
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Md3Shape.full),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DockLayout.horizontalInset,
      ),
      child: Row(
        children: [
          _DockAction(
            key: const ValueKey('reader-catalogue-entry'),
            icon: CupertinoIcons.list_bullet,
            label: '目录',
            onPressed: onDirectory,
          ),
          _DockAction(
            key: const ValueKey('reader-night-entry'),
            icon: night ? CupertinoIcons.sun_max : CupertinoIcons.moon,
            label: night ? '日间' : '夜间',
            onPressed: onNight,
          ),
          _DockAction(
            key: const ValueKey('reader-settings'),
            icon: CupertinoIcons.textformat,
            label: '设置',
            onPressed: onAppearance,
          ),
        ],
      ),
    ),
  );
}

/// One dock item; geometry from upstream `_readerAction` / `DockLayout`.
class _DockAction extends StatelessWidget {
  const _DockAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabledColor = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: Md3State.disabledContent);
    return Expanded(
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: Md3Shape.smallRadius,
          child: SizedBox(
            height: DockLayout.heightOf(context),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: DockLayout.iconSize,
                    color: onPressed == null ? disabledColor : null,
                  ),
                  const SizedBox(height: DockLayout.labelGap),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: DockLayout.labelFontSize,
                          color: onPressed == null ? disabledColor : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 阅读页顶栏的缓存入口：分成阅读菜单后，缓存不再占底部一行。
class ReaderCacheButton extends StatelessWidget {
  const ReaderCacheButton({
    super.key,
    required this.preset,
    required this.onTap,
  });

  final ReaderThemePreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('reader-cache'),
    tooltip: '缓存',
    icon: const Icon(CupertinoIcons.tray_arrow_down),
    onPressed: onTap,
  );
}
