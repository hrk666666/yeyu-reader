import 'package:flutter/material.dart';

import '../../theme/md3.dart';
import '../home/home_design.dart';

/// 漫画阅读器 chrome（顶栏 / 底栏）共用的图标按钮。
///
/// 视觉上是 20dp Lucide 图标 + 44dp 点击区，走官方 [IconButton] 的
/// state layer；颜色取 [HomePalette]，墨水屏自动黑图标 / 白底。
/// 禁用态由 [IconButton.onPressed] 为 null 交给框架处理。
class ComicChromeButton extends StatelessWidget {
  const ComicChromeButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 44,
    this.iconSize = 20,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize),
      iconSize: iconSize,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        foregroundColor: palette.ink,
        disabledForegroundColor: palette.muted.withValues(
          alpha: Md3State.disabledContent,
        ),
      ),
    );
  }
}
