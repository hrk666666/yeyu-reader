import 'package:flutter/material.dart';

/// Material Design 3 官方规范在 Flutter 里的单一入口。
///
/// 这里只放**官方明文规定的数值**，并且凡是 Flutter SDK 已经提供的
/// （[Easing] / [Durations] / [ColorScheme.fromSeed] / 各 `*ThemeData`）
/// 一律直接引用 SDK，不自己抄一遍数字，避免版本漂移。
///
/// 参考：
/// - m3.material.io/styles/motion/easing-and-duration
/// - m3.material.io/styles/shape/shape-scale
/// - m3.material.io/styles/elevation
/// - m3.material.io/foundations/layout/understanding-layout/breakpoints
/// - api.flutter.dev/flutter/material/Easing-class.html

// ---------------------------------------------------------------------------
// 形状：M3 shape scale
// ---------------------------------------------------------------------------

abstract final class Md3Shape {
  static const double extraSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double extraLarge = 28;
  static const double full = 9999;

  static const BorderRadius extraSmallRadius = BorderRadius.all(
    Radius.circular(extraSmall),
  );
  static const BorderRadius smallRadius = BorderRadius.all(
    Radius.circular(small),
  );
  static const BorderRadius mediumRadius = BorderRadius.all(
    Radius.circular(medium),
  );
  static const BorderRadius largeRadius = BorderRadius.all(
    Radius.circular(large),
  );
  static const BorderRadius extraLargeRadius = BorderRadius.all(
    Radius.circular(extraLarge),
  );

  /// 官方 modal bottom sheet 顶部圆角 = extraLarge (28dp)。
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(extraLarge),
  );

  /// 官方 dialog 圆角 = extraLarge (28dp)。
  static const ShapeBorder dialogShape = RoundedRectangleBorder(
    borderRadius: extraLargeRadius,
  );

  /// 官方 NavigationBar active indicator：胶囊。
  static const ShapeBorder navIndicatorShape = StadiumBorder();
}

// ---------------------------------------------------------------------------
// 高度：M3 elevation levels
// ---------------------------------------------------------------------------

abstract final class Md3Elevation {
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 3;
  static const double level3 = 6;
  static const double level4 = 8;
  static const double level5 = 12;
}

// ---------------------------------------------------------------------------
// 状态层：M3 state layer opacity
// ---------------------------------------------------------------------------

abstract final class Md3State {
  static const double hover = 0.08;
  static const double focus = 0.10;
  static const double pressed = 0.10;
  static const double dragged = 0.16;
  static const double disabledContent = 0.38;
  static const double disabledContainer = 0.12;
}

// ---------------------------------------------------------------------------
// 尺寸：M3 硬性布局约束
// ---------------------------------------------------------------------------

abstract final class Md3Dimens {
  /// 最小触摸目标。
  static const double minTouchTarget = 48;

  /// NavigationBar / NavigationRail 高度与宽度。
  static const double navigationBarHeight = 80;
  static const double navigationRailWidth = 80;
  static const double extendedNavigationRailWidth = 256;

  /// 小/中/大 top app bar 高度。
  static const double appBarSmallHeight = 64;
  static const double appBarMediumHeight = 112;
  static const double appBarLargeHeight = 152;

  /// FAB。
  static const double fabSize = 56;
  static const double fabSmallSize = 40;
  static const double fabLargeSize = 96;

  /// 布局边距 / 栏距。
  static const double compactMargin = 16;
  static const double mediumMargin = 24;
  static const double expandedMargin = 24;
  static const double gutter = 8;

  /// 官方 drag handle：32×4，圆角 2。
  static const Size dragHandleSize = Size(32, 4);
}

// ---------------------------------------------------------------------------
// 动效：全部委托给 Flutter SDK 的官方 Easing / Durations
// ---------------------------------------------------------------------------

/// 语义化的 M3 动效别名。底层值来自 [Easing] 与 [Durations]，
/// 这两个类就是 Flutter 对 m3.material.io motion spec 的直接实现。
abstract final class Md3Motion {
  // Easing
  static const Curve emphasized = Easing.emphasizedDecelerate;
  static const Curve emphasizedIn = Easing.emphasizedAccelerate;
  static const Curve standard = Easing.standard;
  static const Curve standardIn = Easing.standardAccelerate;
  static const Curve standardOut = Easing.standardDecelerate;
  static const Curve linear = Easing.linear;

  // Durations
  static const Duration short1 = Durations.short1;
  static const Duration short2 = Durations.short2;
  static const Duration short3 = Durations.short3;
  static const Duration short4 = Durations.short4;
  static const Duration medium1 = Durations.medium1;
  static const Duration medium2 = Durations.medium2;
  static const Duration medium3 = Durations.medium3;
  static const Duration medium4 = Durations.medium4;
  static const Duration long1 = Durations.long1;
  static const Duration long2 = Durations.long2;
  static const Duration long3 = Durations.long3;
  static const Duration long4 = Durations.long4;

  /// 官方转场时长：shared axis / fade through 用 long2 (500ms) 中的
  /// emphasized decelerate；进出分离时进入 long1、退出 medium3。
  static const Duration transitionEnter = Durations.long1;
  static const Duration transitionExit = Durations.medium3;

  /// 官方强调型减速曲线，用于进场元素（FAB、卡片、弹层）。
  static const Curve enterCurve = Easing.emphasizedDecelerate;

  /// 官方加速曲线，用于退出元素。
  static const Curve exitCurve = Easing.emphasizedAccelerate;

  /// M3 的 container transform / shared axis 推荐 300–500ms。
  static const Duration containerTransform = Durations.long1;
}

// ---------------------------------------------------------------------------
// 窗口尺寸类：M3 window size classes
// ---------------------------------------------------------------------------

/// 官方断点：compact < 600, medium < 840, expanded < 1200,
/// large < 1600, extra-large >= 1600（宽度 dp）。
enum Md3WindowSizeClass { compact, medium, expanded, large, extraLarge }

Md3WindowSizeClass md3WindowSizeClassOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 600) return Md3WindowSizeClass.compact;
  if (width < 840) return Md3WindowSizeClass.medium;
  if (width < 1200) return Md3WindowSizeClass.expanded;
  if (width < 1600) return Md3WindowSizeClass.large;
  return Md3WindowSizeClass.extraLarge;
}

/// 官方推荐：compact 用 NavigationBar，medium/expanded 用 NavigationRail，
/// large/extra-large 可用 NavigationDrawer（标准抽屉常驻）。
bool md3UseNavigationBar(BuildContext context) =>
    md3WindowSizeClassOf(context) == Md3WindowSizeClass.compact;

bool md3UseNavigationRail(BuildContext context) {
  final size = md3WindowSizeClassOf(context);
  return size == Md3WindowSizeClass.medium ||
      size == Md3WindowSizeClass.expanded;
}

double md3ContentMargin(BuildContext context) {
  return switch (md3WindowSizeClassOf(context)) {
    Md3WindowSizeClass.compact => Md3Dimens.compactMargin,
    Md3WindowSizeClass.medium ||
    Md3WindowSizeClass.expanded => Md3Dimens.mediumMargin,
    Md3WindowSizeClass.large ||
    Md3WindowSizeClass.extraLarge => Md3Dimens.expandedMargin,
  };
}

// ---------------------------------------------------------------------------
// 官方页面转场
// ---------------------------------------------------------------------------

/// Material 3 shared-axis (Z) 转场：进入页从 0.8 缩放 + 淡入，退出页淡出。
///
/// 规范：m3.material.io/styles/motion/transitions/transition-patterns
/// 用 [Easing.emphasizedDecelerate] 与 [Durations.long1]，与 SDK 默认 M3
/// 转场（ZoomPageTransitionsBuilder）语义一致。
class Md3SharedAxisPageRoute<T> extends MaterialPageRoute<T> {
  Md3SharedAxisPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
    super.allowSnapshotting,
  });

  @override
  Duration get transitionDuration => Md3Motion.transitionEnter;

  @override
  Duration get reverseTransitionDuration => Md3Motion.transitionExit;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: Md3Motion.enterCurve,
      reverseCurve: Md3Motion.exitCurve,
    );
    return FadeTransition(
      opacity: enter,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.8, end: 1.0).animate(enter),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Material 3 fade-through 转场：用于没有共享元素、层级不相邻的切换
/// （如底部导航换 tab）。先完全淡出，再淡入并轻微放大。
class Md3FadeThroughPageRoute<T> extends MaterialPageRoute<T> {
  Md3FadeThroughPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
    super.allowSnapshotting,
  });

  @override
  Duration get transitionDuration => Md3Motion.transitionEnter;

  @override
  Duration get reverseTransitionDuration => Md3Motion.transitionExit;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(0.35, 1.0, curve: Md3Motion.enterCurve),
      reverseCurve: Md3Motion.exitCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 官方组件封装：统一 state layer / 触摸目标 / 形状
// ---------------------------------------------------------------------------

/// 官方 modal bottom sheet：28dp 顶圆角、drag handle、surfaceContainerLow。
Future<T?> md3ShowModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = true,
  bool showDragHandle = true,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    backgroundColor: theme.colorScheme.surfaceContainerLow,
    elevation: Md3Elevation.level1,
    shape: const RoundedRectangleBorder(borderRadius: Md3Shape.sheetTop),
    clipBehavior: Clip.antiAlias,
    builder: builder,
  );
}

/// 官方 SnackBar：inverseSurface 底色 + onInverseSurface 文案 + 8dp 圆角。
void md3ShowSnackBar(BuildContext context, String message, {SnackBarAction? action}) {
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: Md3Shape.smallRadius,
        ),
        backgroundColor: theme.colorScheme.inverseSurface,
        action: action,
        duration: const Duration(seconds: 4),
        content: Text(
          message,
          style: TextStyle(color: theme.colorScheme.onInverseSurface),
        ),
      ),
    );
}

/// 官方 AlertDialog：28dp 圆角、headlineSmall 标题、bodyMedium 正文。
/// 确认返回 `true`，取消 / 点外部返回 `null`（固定 bool，避免泛型强转崩溃）。
Future<bool?> md3ShowDialog({
  required BuildContext context,
  required String title,
  required String content,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool barrierDismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => AlertDialog(
      shape: Md3Shape.dialogShape,
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// 官方 section header：M3 titleSmall / onSurfaceVariant，16dp 水平内边距。
Widget md3SectionHeader(BuildContext context, String text, {Widget? trailing}) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(
      Md3Dimens.compactMargin,
      16,
      Md3Dimens.compactMargin,
      8,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// 官方分割线：outlineVariant，1dp。
Widget md3Divider(BuildContext context, {double indent = 0, double endIndent = 0}) {
  return Divider(
    color: Theme.of(context).colorScheme.outlineVariant,
    height: 1,
    thickness: 1,
    indent: indent,
    endIndent: endIndent,
  );
}

/// 官方 Filled tonal 图标按钮：state layer 由框架负责。
Widget md3TonalIconButton({
  required VoidCallback? onPressed,
  required IconData icon,
  String? tooltip,
  Color? color,
}) {
  return IconButton.filledTonal(
    onPressed: onPressed,
    icon: Icon(icon, color: color),
    tooltip: tooltip,
  );
}

/// 官方自适应导航壳。
///
/// compact → NavigationBar（底部 80dp + active indicator）
/// medium / expanded → NavigationRail（80dp，可选 extended）
/// large / extra-large → NavigationDrawer（常驻标准抽屉）
///
/// [destinations] 数量必须为 3..5（官方约束）。
class Md3AdaptiveNavigation extends StatelessWidget {
  const Md3AdaptiveNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.body,
    this.labelType,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Md3Destination> destinations;
  final Widget body;
  final NavigationDestinationLabelBehavior? labelType;

  @override
  Widget build(BuildContext context) {
    final size = md3WindowSizeClassOf(context);
    if (size == Md3WindowSizeClass.compact) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          labelBehavior: labelType,
          height: Md3Dimens.navigationBarHeight,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon ?? d.icon),
                label: d.label,
              ),
          ],
        ),
      );
    }
    if (size == Md3WindowSizeClass.medium || size == Md3WindowSizeClass.expanded) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.8,
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon ?? d.icon),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            child: SizedBox(
              width: Md3Dimens.extendedNavigationRailWidth,
              child: NavigationDrawer(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                children: [
                  for (final d in destinations)
                    NavigationDrawerDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon ?? d.icon),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

@immutable
class Md3Destination {
  const Md3Destination({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}
