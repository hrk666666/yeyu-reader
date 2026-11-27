import 'package:flutter/material.dart';

import '../../theme/md3.dart';
import 'home_design.dart';

/// 首页 / 搜索 / 分类共用的筛选 chip，直接基于官方 [ChoiceChip]。
///
/// 选中态 secondaryContainer / onSecondaryContainer、未选中态
/// surfaceContainerLow + outlineVariant 描边，切换动画与 state layer 由框架
/// 按 M3 规范处理。墨水屏是显式黑白可访问性变体：黑底白字 / 白底黑字 +
/// 1px 描边，保证选中态不与未选中态撞色。
///
/// 视觉高度 32dp，触控高度不小于 48dp（由 Chip 的 tap target 保证）。
class HomeChip extends StatelessWidget {
  const HomeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
  });

  /// 视觉胶囊高度；触控高度见 [minTapTarget]。
  static const double height = 32;

  /// 触控区域最小高度（比视觉高度多出的部分是透明留白）。
  static const double minTapTarget = 48;

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = HomePalette.of(context);
    // 官方 ChoiceChip：选中态 secondaryContainer / onSecondaryContainer，
    // 未选中态 surfaceContainerLow + outlineVariant 描边；切换动画与 state
    // layer 全部交给框架按 M3 规范处理，不再自绘胶囊、不再手写按压。
    // 墨水屏是显式黑白可访问性变体：黑底白字 / 白底黑字 + 1dp 描边，
    // 避免选中态与未选中态撞色。
    final selectedBg = palette.eink
        ? palette.ink
        : scheme.secondaryContainer;
    final selectedFg = palette.eink
        ? palette.canvas
        : scheme.onSecondaryContainer;
    final unselectedBg = palette.eink
        ? palette.canvas
        : scheme.surfaceContainerLow;
    final foreground = selected ? selectedFg : palette.muted;
    final side = selected
        ? BorderSide.none
        : BorderSide(
            color: palette.eink ? palette.ink : scheme.outlineVariant,
          );
    return Semantics(
      label: semanticLabel,
      selected: selected,
      button: true,
      child: ChoiceChip(
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(color: foreground),
        ),
        selected: selected,
        onSelected: onTap == null ? null : (_) => onTap!(),
        showCheckmark: false,
        selectedColor: selectedBg,
        backgroundColor: unselectedBg,
        disabledColor: unselectedBg,
        side: side,
        shape: RoundedRectangleBorder(borderRadius: Md3Shape.smallRadius),
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }
}
