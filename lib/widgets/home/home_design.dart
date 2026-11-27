import 'package:flutter/material.dart';

import '../../services/app_theme.dart';
import '../../theme/md3.dart';

/// The home surface keeps its warm paper / tomato identity in both themes.
class HomePalette {
  static const accent = Color(0xFFEF5038);
  static const accentStrong = Color(0xFFC73D29);
  final bool dark;

  /// #15/#9：墨水屏时所有纸面 / 文字 / 线条退化为纯黑白。accent 静态常量
  /// 仍为品牌橙（93 处直接引用），本轮不全量替换，见收尾未验项。
  final bool eink;

  /// OLED 纯黑：画布用纯黑省电，卡片 / 弹层保持近黑，靠描边维持层次。
  /// 只在深色外观下生效（见 [oledActive]），这里的 `&& dark` 是二重保险。
  final bool oled;

  const HomePalette(this.dark, {this.eink = false, this.oled = false});

  factory HomePalette.of(BuildContext context) => HomePalette(
    Theme.of(context).brightness == Brightness.dark,
    eink: einkModeNotifier.value,
    oled: oledActive(),
  );

  /// 全 App 唯一配色源：与 [AppTheme.createTheme] 共用同一份
  /// [ColorScheme.fromSeed] 结果。这里不再手写档案纸色值，所有 role 直接
  /// 取官方 tonal palette（surface / surfaceContainer* / onSurfaceVariant…）。
  ColorScheme get scheme => AppTheme.md3Scheme(
    dark ? Brightness.dark : Brightness.light,
  );

  /// 档案纸 / 纯黑两套是显式的可访问性变体（墨水屏、OLED 省电），
  /// 不属于标准 MD3 外观；标准外观一律走 [scheme]。
  Color get canvas {
    if (eink) return Colors.white;
    if (oled && dark) return Colors.black;
    return scheme.surface;
  }

  Color get surface {
    if (eink) return Colors.white;
    if (oled && dark) return const Color(0xFF0C0C0E);
    return scheme.surfaceContainerLow;
  }

  Color get ink => eink ? Colors.black : scheme.onSurface;
  Color get muted => eink ? Colors.black : scheme.onSurfaceVariant;
  Color get accentText => eink ? Colors.black : scheme.primary;

  Color get soft {
    if (eink) return Colors.white;
    if (oled && dark) return const Color(0xFF141417);
    return scheme.surfaceContainer;
  }

  Color get line {
    if (eink) return Colors.black;
    if (oled && dark) return const Color(0xFF2E2E34);
    return scheme.outlineVariant;
  }

  /// 书架背景的方格纸。浅色是极淡的黑格，深色是极淡的白格，墨水屏不画。
  Color get grid => eink
      ? Colors.transparent
      : (dark ? const Color(0x06FFFFFF) : const Color(0x06000000));

  /// 细线之上的定位方块：分区标签、选中态都用它。
  Color get mark => eink ? Colors.black : ink;

  /// 官方 M3 SearchBar 底色 = surfaceContainerHighest。
  Color get searchBar => eink ? Colors.white : scheme.surfaceContainerHighest;

  /// 官方提示 / 次级文案色 = onSurfaceVariant。
  Color get searchBarText =>
      eink ? Colors.black : scheme.onSurfaceVariant;

  /// 官方正文次级色 = onSurfaceVariant（M3 用 tonal 灰而非 60% 黑叠色）。
  Color get body => eink ? Colors.black : scheme.onSurfaceVariant;
}

/// 底部弹层（bottom sheet）的底色。
///
/// 深色 / OLED 下换成比画布高一档的 surface：barrier 的黑色叠在纯黑画布
/// 上不会让页面变暗，弹层若仍取 canvas 就和页面连成一片，看不出上缘；
/// 浅色仍用原来的画布色，弹层靠 barrier 变暗区分。
Color homeSheetColor(HomePalette palette) =>
    palette.dark ? palette.surface : palette.canvas;

/// 弹层里成组的卡片：深色下比 [homeSheetColor] 再错一档（字段色），
/// 浅色仍是白卡。
Color homeSheetCardColor(HomePalette palette) =>
    palette.dark ? palette.soft : palette.surface;

/// 弹层上缘的一圈发丝线：OLED 下画布与浮层都是近黑，没有它边界仍不明显。
///
/// 只给深色 / OLED：浅色弹层与奶白画布本来就靠 barrier 区分，多一圈线反而
/// 突兀；墨水屏 `line` 是纯黑，下发了就会在弹层四周描出一圈黑边。
RoundedRectangleBorder homeSheetShape(
  HomePalette palette, {
  double top = Md3Shape.extraLarge,
}) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(top)),
      side: palette.dark
          ? BorderSide(color: palette.line.withValues(alpha: 0.8), width: 0.8)
          : BorderSide.none,
    );

/// 官方 M3 state layer 按压反馈。
///
/// 不再自研弹簧缩放：M3 规范里按压反馈是 ripple + 8% state layer，
/// 由 [InkWell] 按主题自动给出；缩放属于自定义动效，不是规范交互。
class HomePressable extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  /// 长按动作（可空）。听书页用它在倍速项上做「锁定倍速」。
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final String? semanticLabel;

  const HomePressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.borderRadius = Md3Shape.mediumRadius,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: borderRadius,
        child: child,
      ),
    ),
  );
}

/// 官方 M3 fade-through 进场：淡入 + 轻微上移，
/// 使用 [Easing.emphasizedDecelerate] 与 [Durations.long1]。
///
/// The fade costs an [Opacity] layer for as long as it runs, and a sliver
/// disposes the children that leave its cache extent, so a child that is
/// re-mounted by scrolling back up the feed must opt out ([animate] false).
class HomeEntrance extends StatelessWidget {
  final int index;
  final bool animate;
  final Widget child;

  const HomeEntrance({
    super.key,
    this.index = 0,
    this.animate = true,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!animate || MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Md3Motion.long1,
      curve: Md3Motion.emphasized,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
