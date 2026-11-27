import 'package:flutter/material.dart';

import '../home/home_design.dart';

/// 主行动填充色：标准外观走官方 [ColorScheme.primary]，墨水屏退化为纯黑。
Color detailAccentFill(HomePalette palette) =>
    palette.eink ? palette.ink : palette.scheme.primary;

/// 强调色块上的文字 / 图标色：官方 [ColorScheme.onPrimary]。
Color detailOnAccent(HomePalette palette) =>
    palette.eink ? palette.surface : palette.scheme.onPrimary;

/// 星标色：官方 [ColorScheme.tertiary] 语义强调色，墨水屏退化为纯黑。
Color detailStarColor(HomePalette palette) =>
    palette.eink ? palette.ink : palette.scheme.tertiary;

/// Tabular figures for the score, ID and progress (`font-variant-numeric`).
/// No font family is set: the detail page keeps the app's own font.
const List<FontFeature> detailNumericFeatures = [
  FontFeature.tabularFigures(),
];

/// Rank pill fill：官方 [ColorScheme.secondaryContainer]，墨水屏退化。
Color detailRankFill(HomePalette palette) {
  if (palette.eink) return palette.surface;
  return palette.scheme.secondaryContainer;
}

/// Progress track fill (官方 surfaceContainer 一档)。
Color detailProgressTrack(HomePalette palette) => palette.soft;

/// Progress bar fill: 官方 [ColorScheme.primary]，墨水屏实心纯黑。
Color detailProgressFill(HomePalette palette) =>
    palette.eink ? palette.ink : palette.scheme.primary;

/// Primary action: 官方 [FilledButton]，填充取官方 primary / onPrimary。
ButtonStyle detailPrimaryButtonStyle(
  HomePalette palette, {
  Size minimumSize = const Size(110, 46),
}) => FilledButton.styleFrom(
  backgroundColor: detailAccentFill(palette),
  foregroundColor: detailOnAccent(palette),
  disabledBackgroundColor: palette.scheme.onSurface.withValues(alpha: 0.12),
  disabledForegroundColor: palette.scheme.onSurface.withValues(alpha: 0.38),
  minimumSize: minimumSize,
  visualDensity: VisualDensity.standard,
  shape: const StadiumBorder(),
);

/// Secondary action: 官方 [OutlinedButton]，描边取官方 outline。
ButtonStyle detailOutlineButtonStyle(
  HomePalette palette, {
  Size minimumSize = const Size(110, 46),
}) => OutlinedButton.styleFrom(
  foregroundColor: palette.ink,
  side: BorderSide(color: palette.line),
  minimumSize: minimumSize,
  visualDensity: VisualDensity.standard,
  shape: const StadiumBorder(),
);
