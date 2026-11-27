import 'package:flutter/material.dart';

import '../home/home_design.dart';

/// 短剧详情页的配色换算。
///
/// 页面跟随应用主题，标准外观一律取官方 [ColorScheme] 的 role；剧集自己的
/// `series_color_hex` 只留作顶栏后面一条淡色带（动态取色，见 [seriesBandTint]）。
/// 墨水屏是无彩变体：强调色退化为纯黑，黑白对比就是全部层级。

/// 主行动钮与当前集描边用官方 [ColorScheme.primary]。
Color seriesAccent(HomePalette palette) =>
    palette.eink ? palette.ink : palette.scheme.primary;

/// 强调色块上的文字 / 图标色：官方 [ColorScheme.onPrimary]。
Color seriesOnAccent(HomePalette palette) =>
    palette.eink ? palette.canvas : palette.scheme.onPrimary;

/// 强调色文字（当前集数字）：官方 [ColorScheme.primary]，
/// 在深 / 浅外观下由 fromSeed 自动保证对比度。
Color seriesAccentText(HomePalette palette) {
  if (palette.eink) return palette.canvas;
  return palette.scheme.primary;
}

/// 当前集格子的浅强调底：官方 [ColorScheme.secondaryContainer]。
Color seriesCurrentFill(HomePalette palette) {
  if (palette.eink) return palette.ink;
  return palette.scheme.secondaryContainer;
}

/// 剧集主色在画布上的淡色带（动态取色，属语义色例外）。
///
/// 只接受六位 hex；缺失、非法或灰色系（饱和度 < 0.05）都不出色带。
/// 墨水屏整页纯黑白，同样不出色带。
Color? seriesBandTint(String hex, HomePalette palette) {
  if (palette.eink) return null;
  final match = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  if (match == null) return null;
  final color = Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
  if (HSLColor.fromColor(color).saturation < 0.05) return null;
  // 深色下同一条色相的色带要更实一点才看得出来，但仍远低于正文对比度。
  return color.withValues(alpha: palette.dark ? 0.16 : 0.10);
}
