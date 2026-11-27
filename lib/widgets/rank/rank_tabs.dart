import 'package:flutter/material.dart';

import '../../models/rank.dart';

/// 榜单层级：官方 MD3 [TabBar]（可滚动、下划线选中态、state layer）。
///
/// 选中索引由父级 [selectedIndex] 驱动；内部 [TabController] 与之同步，
/// 点击通过 [onSelect] 上报，业务逻辑不变。
class RankBoardTabs extends StatefulWidget {
  const RankBoardTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<RankTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  State<RankBoardTabs> createState() => _RankBoardTabsState();
}

class _RankBoardTabsState extends State<RankBoardTabs>
    with SingleTickerProviderStateMixin {
  late TabController _controller;

  int get _clampedIndex =>
      widget.tabs.isEmpty ? 0 : widget.selectedIndex.clamp(0, widget.tabs.length - 1);

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: widget.tabs.length,
      vsync: this,
      initialIndex: _clampedIndex,
    );
  }

  @override
  void didUpdateWidget(RankBoardTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabs.length != oldWidget.tabs.length) {
      _controller.dispose();
      _controller = TabController(
        length: widget.tabs.length,
        vsync: this,
        initialIndex: _clampedIndex,
      );
    } else if (widget.selectedIndex != oldWidget.selectedIndex &&
        _clampedIndex != _controller.index) {
      _controller.animateTo(_clampedIndex);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TabBar(
      key: const Key('rank_tabs'),
      controller: _controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      onTap: widget.onSelect,
      tabs: [
        for (final tab in widget.tabs)
          Tab(text: tab.name, key: ValueKey('rank_tab_${tab.algo}')),
      ],
    );
  }
}
