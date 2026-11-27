import 'package:flutter/material.dart';

import '../services/app_theme.dart';
import '../theme/md3.dart';

/// 主壳层导航：官方 Material 3 [NavigationBar]。
///
/// 原先是自研液态玻璃 GlassDock（胶囊、拖动预览、折射选中区、underlay 渐变），
/// 这些都不是 MD3 组件。现在统一换成官方实现：80dp 高、3–5 个目的地、
/// secondaryContainer 胶囊 indicator、官方 state layer / ripple / 标签行为。
///
/// [overVideo] 仍保留：短剧推荐频道压在深色视频流上，局部套深色主题，
/// 让 NavigationBar 用深色 tonal role 取色；[staticMaterial] 保留是为了
/// 兼容壳层的调用签名，官方组件不再有「实时折射 / 静态底板」之分。
class ShellDock extends StatelessWidget {
  const ShellDock({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.overVideo,
    required this.staticMaterial,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 短剧推荐频道背后是全屏视频流：导航栏按深色外观绘制。
  final bool overVideo;

  /// 兼容参数：官方 NavigationBar 不区分静态 / 动态材质，保留以免影响壳层。
  final bool staticMaterial;

  static const _items = [
    Md3Destination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: '首页',
    ),
    Md3Destination(
      icon: Icons.play_circle_outline,
      selectedIcon: Icons.play_circle,
      label: '短剧',
    ),
    Md3Destination(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: '书架',
    ),
    // 手环传书紧挨书架：它是「书往外传」的延伸场景（书架 → 传到手环），
    // 放在书架旁比塞进「我的」更好找，也避开短剧下标（1）不动。
    Md3Destination(
      icon: Icons.watch_outlined,
      selectedIcon: Icons.watch,
      label: '手环',
    ),
    Md3Destination(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        einkModeNotifier.value || MediaQuery.disableAnimationsOf(context);
    Widget bar = NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      height: Md3Dimens.navigationBarHeight,
      animationDuration: reduceMotion ? Duration.zero : Md3Motion.medium2,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        for (final item in _items)
          NavigationDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon ?? item.icon),
            label: item.label,
          ),
      ],
    );
    if (overVideo && Theme.of(context).brightness != Brightness.dark) {
      bar = Theme(
        data: AppTheme.createTheme(Brightness.dark),
        child: bar,
      );
    }
    return bar;
  }
}

/// OLED 纯黑只在深色外观下生效；壳层据此决定系统导航栏取色。
bool shellDockStaticMaterial({required bool overVideo}) =>
    overVideo || oledActive();
