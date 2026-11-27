// 阅读外观设置：官方 Material 3 组件。
// 弹层走 md3ShowModalSheet，背景色块用 ChoiceChip(selected)，亮度用官方
// Slider，跟随系统用 FilterChip，动作钮用 FilledButton.tonal，字号步进用
// IconButton.filledTonal，取色与字号走 Theme.colorScheme / textTheme。
// 所有排版选项、Key、持久化与「更多设置」子面板保持不变；亮度 Slider 的
// onChanged/onChangeEnd 契约由 reader_interface_test 覆盖，保持官方实现。

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../services/reader_device.dart';
import '../../services/reader_preferences.dart';
import '../../theme/md3.dart';
import 'reader_theme.dart';
import 'settings/reader_turn_settings.dart';
import 'settings/reader_font_picker_sheet.dart';
import 'settings/reader_more_settings_sheet.dart';
import 'settings/reader_settings_state.dart';
import 'settings/reader_settings_widgets.dart';

/// 打开阅读设置面板。
Future<void> showReaderSettingsSheet({
  required BuildContext context,
  required ReaderPreferences initialValue,
  required ValueChanged<ReaderPreferences> onChanged,
  required Future<ReaderFont?> Function() onPickFont,
  required bool deviceAvailable,
  required double? systemBrightness,
  required ValueChanged<double> onBrightness,
  required VoidCallback onBrightnessEnd,
  required VoidCallback onFollowSystem,
  required bool autoTurnActive,
  required VoidCallback? onAutoTurn,
  bool einkOverride = false,
  bool oledOverride = false,
  VoidCallback? onTextReplacement,
  VoidCallback? onListeningSource,
}) {
  return md3ShowModalSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ReaderAppearanceSheet(
      initialValue: initialValue,
      onChanged: onChanged,
      onPickFont: onPickFont,
      deviceAvailable: deviceAvailable,
      systemBrightness: systemBrightness,
      onBrightness: onBrightness,
      onBrightnessEnd: onBrightnessEnd,
      onFollowSystem: onFollowSystem,
      autoTurnActive: autoTurnActive,
      onAutoTurn: onAutoTurn,
      einkOverride: einkOverride,
      oledOverride: oledOverride,
      onTextReplacement: onTextReplacement,
      onListeningSource: onListeningSource,
    ),
  );
}

/// 阅读设置：亮度、字号、背景、翻页、间距一屏放下，重排版项收进「更多设置」。
class ReaderAppearanceSheet extends StatefulWidget {
  final ReaderPreferences initialValue;
  final ValueChanged<ReaderPreferences> onChanged;
  final Future<ReaderFont?> Function() onPickFont;

  /// 设备亮度可用时才显示亮度行。
  final bool deviceAvailable;
  final double? systemBrightness;
  final ValueChanged<double> onBrightness;
  final VoidCallback onBrightnessEnd;
  final VoidCallback onFollowSystem;

  final bool autoTurnActive;
  final VoidCallback? onAutoTurn;

  /// 全局墨水屏模式已开启时，阅读背景跟随全局，不由本面板的色块决定。
  final bool einkOverride;

  /// 全局 OLED 纯黑已开启：阅读背景强制夜间 + 纯黑画布，同样禁用色块。
  final bool oledOverride;

  final VoidCallback? onTextReplacement;
  final VoidCallback? onListeningSource;

  const ReaderAppearanceSheet({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.onPickFont,
    required this.deviceAvailable,
    required this.systemBrightness,
    required this.onBrightness,
    required this.onBrightnessEnd,
    required this.onFollowSystem,
    required this.autoTurnActive,
    required this.onAutoTurn,
    this.einkOverride = false,
    this.oledOverride = false,
    this.onTextReplacement,
    this.onListeningSource,
  });

  @override
  State<ReaderAppearanceSheet> createState() => _ReaderAppearanceSheetState();
}

typedef _SpacingPreset = ({
  String label,
  String key,
  double lineHeight,
  double paragraphSpacing,
  double horizontalPadding,
  double verticalPadding,
});

class _ReaderAppearanceSheetState
    extends ReaderSettingsState<ReaderAppearanceSheet> {
  @override
  ReaderPreferences get initialPreferences => widget.initialValue;

  @override
  ValueChanged<ReaderPreferences> get onPreferencesChanged => widget.onChanged;

  static const _spacingPresets = <_SpacingPreset>[
    (
      label: '紧凑',
      key: 'reader-spacing-compact',
      lineHeight: 1.5,
      paragraphSpacing: 6,
      horizontalPadding: 12,
      verticalPadding: 8,
    ),
    (
      label: '标准',
      key: 'reader-spacing-standard',
      lineHeight: 1.8,
      paragraphSpacing: 12,
      horizontalPadding: 20,
      verticalPadding: 16,
    ),
    (
      label: '宽松',
      key: 'reader-spacing-loose',
      lineHeight: 2.1,
      paragraphSpacing: 20,
      horizontalPadding: 32,
      verticalPadding: 28,
    ),
  ];

  /// 面板显示用的预设：全局墨水屏 / OLED 纯黑开启时强制到对应预设，
  /// 与保存的预设分开，其它排版改动仍写保存的预设。
  ReaderThemePreset get _displayPreset {
    if (widget.einkOverride) return ReaderThemePreset.eink;
    if (widget.oledOverride) return ReaderThemePreset.dark;
    return value.themePreset;
  }

  bool get _backgroundLocked => widget.einkOverride || widget.oledOverride;

  double get _brightnessLevel => value.followSystemBrightness
      ? widget.systemBrightness ?? value.brightness
      : value.brightness;

  void _apply(ReaderPreferences Function(ReaderPreferences) change) =>
      commitPreferences(change(value));

  /// 拖动亮度：与内联面板一致，手动调整即退出「跟随系统」。
  void _setBrightness(double level) {
    setState(
      () => value = value.copyWith(
        brightness: level,
        followSystemBrightness: false,
      ),
    );
    widget.onBrightness(level);
  }

  /// 跟随系统由阅读页计算并应用设备亮度；面板只同步自身显示。
  void _toggleFollowSystem() {
    setState(
      () => value = value.copyWith(
        followSystemBrightness: !value.followSystemBrightness,
      ),
    );
    widget.onFollowSystem();
  }

  void _toggleAutoTurn() {
    Navigator.pop(context);
    widget.onAutoTurn?.call();
  }

  Future<void> _openFontPicker() async {
    final selection = await showReaderFontPicker(
      context: context,
      preset: _displayPreset,
      currentPath: value.fontPath,
      currentName: value.fontName,
      onPickFont: widget.onPickFont,
    );
    if (!mounted || selection == null) return;
    _apply(
      (current) =>
          current.copyWith(fontPath: selection.path, fontName: selection.name),
    );
  }

  Future<void> _openMore() async {
    final result = await showReaderMoreSettings(
      context: context,
      initialValue: value,
      einkOverride: widget.einkOverride,
      oledOverride: widget.oledOverride,
      backgroundLocked: _backgroundLocked,
      showListeningSource: widget.onListeningSource != null,
      onChanged: (next) {
        if (!mounted) return;
        // 子面板已经按 120ms 合并过，这里直接同步本地并转给阅读页。
        adoptPreferences(next);
        widget.onChanged(next.normalized());
      },
    );
    if (!mounted) return;
    if (result == ReaderMoreSettingsResult.textReplacement) {
      Navigator.pop(context);
      widget.onTextReplacement?.call();
    } else if (result == ReaderMoreSettingsResult.listeningSource) {
      Navigator.pop(context);
      widget.onListeningSource?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = _displayPreset;
    return ReaderSettingsSheetFrame(
      preset: preset,
      title: '阅读设置',
      closeTooltip: '关闭排版设置',
      scrollKey: const ValueKey('reader-appearance-scroll'),
      onClose: flushPreferences,
      children: [
        if (widget.deviceAvailable) _brightnessRow(),
        _fontSizeRow(),
        _backgroundRow(preset),
        if (_backgroundLocked) _backgroundLockNotice(preset),
        ReaderTurnSettings(value: value, onChanged: commitPreferences),
        _spacingRow(),
        const ReaderSettingsDivider(),
        _actionsRow(),
      ],
    );
  }

  Widget _brightnessRow() => ReaderSettingsRow(
    label: '亮度',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final slider = Slider(
          key: const ValueKey('reader-brightness'),
          value: _brightnessLevel.clamp(0.02, 1),
          min: 0.02,
          max: 1,
          onChanged: _setBrightness,
          onChangeEnd: (_) => widget.onBrightnessEnd(),
          semanticFormatterCallback: (level) => '亮度 ${(level * 100).round()}%',
        );
        final follow = FilterChip(
          key: const ValueKey('reader-follow-system'),
          label: const Text('跟随系统'),
          selected: value.followSystemBrightness,
          onSelected: (_) => _toggleFollowSystem(),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
        if (constraints.maxWidth < 220) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [slider, follow],
          );
        }
        return Row(
          children: [
            Expanded(child: slider),
            const SizedBox(width: 4),
            follow,
          ],
        );
      },
    ),
  );

  Widget _fontSizeRow() => ReaderSettingsRow(
    label: '字号',
    child: _FontSizeStepper(
      value: value.fontSize,
      onChanged: (size) =>
          _apply((current) => current.copyWith(fontSize: size)),
    ),
  );

  Widget _backgroundRow(ReaderThemePreset preset) => ReaderSettingsRow(
    label: '背景',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final count = ReaderThemePreset.values.length;
        final diameter = (constraints.maxWidth / count - 4)
            .clamp(24.0, 38.0)
            .toDouble();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final choice in ReaderThemePreset.values)
              _swatch(preset, choice, diameter),
          ],
        );
      },
    ),
  );

  Widget _backgroundLockNotice(ReaderThemePreset preset) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Text(
      widget.einkOverride ? '全局墨水屏模式已开启，背景跟随全局设置' : '全局 OLED 纯黑已开启，背景跟随全局设置',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    ),
  );

  Widget _spacingRow() => ReaderSettingsRow(
    label: '间距',
    child: ReaderSettingsChipRow(
      children: [
        for (final option in _spacingPresets)
          ReaderSettingsChip(
            key: ValueKey(option.key),
            label: option.label,
            selected: _matchesSpacing(option),
            onTap: () => _apply(
              (current) => current.copyWith(
                lineHeight: option.lineHeight,
                paragraphSpacing: option.paragraphSpacing,
                horizontalPadding: option.horizontalPadding,
                verticalPadding: option.verticalPadding,
              ),
            ),
          ),
      ],
    ),
  );

  /// 四个字段同时吻合才算命中预设；自定义值不显示任何选中项。
  bool _matchesSpacing(_SpacingPreset option) =>
      (value.lineHeight - option.lineHeight).abs() < 0.001 &&
      (value.paragraphSpacing - option.paragraphSpacing).abs() < 0.001 &&
      (value.horizontalPadding - option.horizontalPadding).abs() < 0.001 &&
      (value.verticalPadding - option.verticalPadding).abs() < 0.001;

  Widget _actionsRow() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
    child: Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: 4,
      runSpacing: 4,
      children: [
        _actionButton(
          key: const ValueKey('reader-auto-turn'),
          icon: widget.autoTurnActive
              ? LucideIcons.circle_pause
              : LucideIcons.circle_play,
          label: widget.autoTurnActive ? '停止自动翻页' : '自动翻页',
          onTap: _toggleAutoTurn,
        ),
        _actionButton(
          key: const ValueKey('reader-font-picker'),
          icon: LucideIcons.type,
          label: '字体',
          onTap: _openFontPicker,
        ),
        _actionButton(
          key: const ValueKey('reader-more-appearance'),
          icon: LucideIcons.sliders_horizontal,
          label: '更多设置',
          trailing: true,
          onTap: _openMore,
        ),
      ],
    ),
  );

  Widget _actionButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool trailing = false,
  }) {
    final chevron = trailing
        ? Icon(
            LucideIcons.chevron_right,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )
        : null;
    return FilledButton.tonal(
      key: key,
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 4),
          Text(label),
          if (chevron != null) ...[const SizedBox(width: 2), chevron],
        ],
      ),
    );
  }

  /// 背景色块：官方 ChoiceChip 承载 selected 状态与纸张预览色，
  /// 全局模式接管时 onSelected 置空即禁用。
  Widget _swatch(
    ReaderThemePreset preset,
    ReaderThemePreset choice,
    double diameter,
  ) {
    final selected = choice == preset;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: '${choice.label}阅读背景',
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: ChoiceChip(
          key: ValueKey('reader-theme-${choice.name}'),
          label: Text(
            '阅',
            style: TextStyle(
              color: choice.textColor,
              fontSize: diameter * 13 / 38,
            ),
          ),
          selected: selected,
          onSelected: _backgroundLocked
              ? null
              : (_) => _apply((current) => current.copyWith(themePreset: choice)),
          showCheckmark: false,
          backgroundColor: choice.backgroundColor,
          selectedColor: choice.backgroundColor,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          labelPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// 字号步进器：A− / 当前字号 / A+。
class _FontSizeStepper extends StatelessWidget {
  const _FontSizeStepper({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const _min = 14.0;
  static const _max = 32.0;

  @override
  Widget build(BuildContext context) {
    final preset = ReaderSettingsTheme.of(context);
    Widget end({
      required String glyph,
      required double fontSize,
      required double delta,
      required String tooltip,
    }) {
      final next = value + delta;
      return Expanded(
        // 官方 IconButton 自带 48dp 触摸目标；Tooltip 仍包在按钮本身上，
        // 让可访问性定位落在真实可点目标上。
        child: Center(
          child: Tooltip(
            message: tooltip,
            child: IconButton.filledTonal(
              onPressed: next < _min || next > _max
                  ? null
                  : () => onChanged(next.clamp(_min, _max).toDouble()),
              icon: Text(
                glyph,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      key: const ValueKey('reader-font-size'),
      child: Row(
        children: [
          end(glyph: 'A−', fontSize: 14, delta: -1, tooltip: '减小字号'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              value.round().toString(),
              style: TextStyle(color: preset.accentColor, fontSize: 13),
            ),
          ),
          end(glyph: 'A+', fontSize: 20, delta: 1, tooltip: '增大字号'),
        ],
      ),
    );
  }
}
