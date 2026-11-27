import 'package:flutter/material.dart';

import '../../theme/md3.dart';

class HomeCategory {
  final String label;

  const HomeCategory(this.label);
}

const homeCategories = [
  HomeCategory('推荐'),
  HomeCategory('小说'),
  HomeCategory('短剧'),
  HomeCategory('漫剧'),
  HomeCategory('漫画'),
  HomeCategory('听书'),
];

/// 六个媒介分类固定在顶部；切换动画交给官方 [TabBar] 自带的 indicator，
/// 不再自绘下划线与 180ms 文字渐变。
class HomeTabBar extends StatefulWidget {
  static const double sidePadding = 16;
  static const double tabSpacing = 22;
  static const double selectedSize = 15;
  static const double unselectedSize = 15;

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<HomeCategory> categories;

  const HomeTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.categories = homeCategories,
  });

  @override
  State<HomeTabBar> createState() => _HomeTabBarState();
}

class _HomeTabBarState extends State<HomeTabBar>
    with SingleTickerProviderStateMixin {
  late TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: widget.categories.length,
      initialIndex: widget.selectedIndex,
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant HomeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.categories.length != _controller.length) {
      _controller.dispose();
      _controller = TabController(
        length: widget.categories.length,
        initialIndex: widget.selectedIndex,
        vsync: this,
      );
      return;
    }
    // 横滑 / 外部选中：同步官方 controller，indicator 自带 M3 动画。
    if (widget.selectedIndex != _controller.index) {
      _controller.index = widget.selectedIndex;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TabBar(
      controller: _controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: HomeTabBar.sidePadding),
      labelPadding: const EdgeInsets.symmetric(horizontal: HomeTabBar.tabSpacing / 2),
      onTap: widget.onSelect,
      dividerColor: scheme.outlineVariant,
      indicatorColor: scheme.primary,
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: theme.textTheme.titleSmall,
      unselectedLabelStyle: theme.textTheme.titleSmall,
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.pressed)) {
          return scheme.primary.withValues(alpha: Md3State.pressed);
        }
        if (states.contains(WidgetState.hovered)) {
          return scheme.primary.withValues(alpha: Md3State.hover);
        }
        if (states.contains(WidgetState.focused)) {
          return scheme.primary.withValues(alpha: Md3State.focus);
        }
        return null;
      }),
      tabs: [
        for (var index = 0; index < widget.categories.length; index++)
          Tab(
            key: ValueKey('home_category_$index'),
            text: widget.categories[index].label,
          ),
      ],
    );
  }
}
