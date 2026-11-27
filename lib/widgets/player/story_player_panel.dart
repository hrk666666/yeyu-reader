import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';

import '../../models/media_item.dart';
import '../home/home_design.dart';
import 'player_toast.dart';
import '../../theme/md3.dart';

/// 选集格子的官方状态（`hj3/r0.java:217-235,539-554`）。
///
/// 颜色已从 APK 皮肤色值迁移到 M3 语义角色（见 [EpisodeTileColors]）：
/// - 选中：底 `primary @10%`、字 `primary`（官方是橙底橙字）
/// - 不可播：字 `onSurface @38%`（[Md3State.disabledContent]），
///   点击 Toast「该选集暂时无法播放」
/// - 已看：字 `onSurfaceVariant`
/// - 普通：字 `onSurface`、底 `surfaceContainerHighest`
///
/// 深色 / OLED / 墨水屏由 `ColorScheme` 自动翻转，不再分支。
enum EpisodeTileState {
  normal,
  current,
  watched,
  disabled;

  static EpisodeTileState of({
    required bool current,
    required bool watched,
    required bool disabled,
  }) {
    if (current) return EpisodeTileState.current;
    if (disabled) return EpisodeTileState.disabled;
    if (watched) return EpisodeTileState.watched;
    return EpisodeTileState.normal;
  }

  /// 语义状态层色：字色按 M3 role 取，深色 / OLED / 墨水屏自动跟随。
  Color textColor(ColorScheme scheme) => switch (this) {
    EpisodeTileState.current => scheme.primary,
    EpisodeTileState.disabled => scheme.onSurface.withValues(
      alpha: Md3State.disabledContent,
    ),
    EpisodeTileState.watched => scheme.onSurfaceVariant,
    EpisodeTileState.normal => scheme.onSurface,
  };

  /// 当前集底用 primary 的 10% state layer，其余格用一格容器色。
  Color backgroundColor(ColorScheme scheme) =>
      this == EpisodeTileState.current
      ? scheme.primary.withValues(alpha: Md3State.pressed)
      : scheme.surfaceContainerHighest;

  FontWeight get weight =>
      this == EpisodeTileState.current ? FontWeight.w500 : FontWeight.w400;
}

/// 官方选集格子文案（`hj3/r0.java:413-419`）：预告 -> 「预告」（`epd`）、
/// 推荐流插入项 -> 「高光」（`esr`），其余是纯序号。
String episodeTileLabel({
  required int index,
  bool trailer = false,
  bool highlight = false,
}) {
  if (trailer) return '预告';
  if (highlight) return '高光';
  return '${index + 1}';
}

/// 官方「新」角标（`bbw.xml:2-10`：18x18dp 容器、圆角 6dp、底
/// `@color/aom`=#1AFA6725、内文 `@string/e0f`=「新」）。
///
/// 显示条件（`hj3/r0.java:539-554` 的 `T1`）：
/// 未选中 && 未播过 && 不在观看历史里 && `isNewlyUpdate`。
bool episodeShowsNewBadge({
  required bool current,
  required bool played,
  required bool watched,
  required bool newlyUpdate,
}) => !current && !played && !watched && newlyUpdate;

/// 选集面板「关联原著」条的数据（官方 `VideoRelateBook.bookInfo`：
/// `book_id` / `book_name` / `thumb_url`，映射见 `bh3/c.java:21-43`）。
class EpisodeRelateBook {
  const EpisodeRelateBook({
    required this.id,
    required this.title,
    this.cover = '',
  });

  final String id;
  final String title;
  final String cover;
}

/// 官方头部的封面占位（没有封面图时用剧集首帧同款深色块）。
class _HeaderCoverFallback extends StatelessWidget {
  const _HeaderCoverFallback();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 86,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: Md3Shape.smallRadius,
      ),
      child: Icon(
        Icons.movie_creation_outlined,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// 官方头部集数/状态文案（`a1.java:554-568` 的 `A2()` 与 `:2034-2056` 的 `o1()`）。
///
/// 分支顺序照搬源码：
/// 1. 电影：`电影 · 共N分钟`（N = 时长向上取整到分钟）
/// 2. 虚幻短剧（`UnrealShortPlay`）：`string/d6d`「暂未上线」
/// 3. `SeriesStatus.SeriesUpdating`：漫改用 `string/e6u`
///    「看到%s集/更新至%s集」（第一个 %s 是当前集号），否则 `string/e6s`
///    「更新至%s集」
/// 4. 其余（`SeriesEnd`/今日更新/断更都落这里）：`string/e6q`「已完结 共%s集」
///
/// 注意取证笔记里把 `d6d` 记成「未上线」的通用文案，实际源码里它只服务
/// `UnrealShortPlay` 这一支，这里按**源码**实现。
String seriesEpisodeLabel({
  required int? status,
  required int count,
  required int currentIndex,
  bool motionComic = false,
  bool unrealShortPlay = false,
  int durationSeconds = 0,
}) {
  if (unrealShortPlay) return '暂未上线';
  if (durationSeconds > 0 && count <= 1) {
    final minutes = (durationSeconds / 60).ceil();
    if (minutes > 0) return '电影 · 共$minutes分钟';
  }
  if (status == SeriesStatus.updating) {
    if (motionComic) return '看到${currentIndex + 1}集/更新至$count集';
    return '更新至$count集';
  }
  if (count > 0) return '已完结 共$count集';
  return '';
}

/// 官方 `SeriesStatus`（`com/bytedance/kmp/reading/model/SeriesStatus.java`）：
/// **0=更新中（SeriesUpdating）**、1=已完结（SeriesEnd）、3=今日更新、
/// 4=断更。注意与书库 `creation_status` 的 0=完结/1=连载语义相反。
class SeriesStatus {
  const SeriesStatus._();
  static const int updating = 0;
  static const int finished = 1;
  static const int updateToday = 3;
  static const int updateStop = 4;
}

/// 官方长剧分页（`gj3/o.java:731` `setGroupByCount(30)`）：每 30 集一组
/// 「1-30/31-60/…」，>30 集出现、滚动联动，≤30 隐藏。
const _pageSize = 30;
const _defaultColumns = 6;

class StoryPlayerPanel extends StatefulWidget {
  final ScrollController scrollController;
  final List<Chapter> episodes;
  final int currentIndex;
  final int? playingIndex;
  final bool playing;

  /// 已看集（灰字 #66000000）。官方取观看历史（`hj3/r0.java:224-235`），
  /// 本仓库由宿主给：续播点之前的集 + 本次会话播过的集。
  final Set<int> watched;

  /// 头部剧信息（官方 `aa8.xml:7-15` 的 `hdp` 区块）：封面、标题、
  /// 集数/状态文案、免费角标。官方这些字段来自剧集详情。
  final String seriesTitle;
  final String seriesCover;
  final String episodeLabel;
  final bool freeWatch;

  /// 点头部（官方 `right_icon` 箭头）。
  final VoidCallback? onOpenSeries;
  final VoidCallback? onOpenRelatedSeries;

  /// 关联原著条（官方 `aa8.xml:17` 的 `gnh`，由
  /// `series_relate_book_config_v659.relate_book_in_episodes_dialog` 控制，
  /// **默认 false**）。为 null 时整条不显示。
  final EpisodeRelateBook? relateBook;
  final VoidCallback? onOpenRelateBook;

  final ValueChanged<int> onSelectEpisode;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final GestureDragCancelCallback onDragCancel;

  /// 嵌进播放页分屏时置 true：去掉 grabber、sheet 背景与内部标题行，
  /// 头部与背景由外层 [PlayerSplitPanel] 提供；网格、分页与当前集定位
  /// 逻辑保持不变。
  final bool embedded;

  /// 选集网格列数：竖屏 sheet 6 列，横屏右侧分栏 4 列。
  final int columns;

  const StoryPlayerPanel({
    super.key,
    required this.scrollController,
    required this.episodes,
    required this.currentIndex,
    required this.playingIndex,
    this.playing = false,
    this.watched = const <int>{},
    this.seriesTitle = '',
    this.seriesCover = '',
    this.episodeLabel = '',
    this.freeWatch = false,
    this.onOpenSeries,
    this.onOpenRelatedSeries,
    this.relateBook,
    this.onOpenRelateBook,
    required this.onSelectEpisode,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    this.embedded = false,
    this.columns = _defaultColumns,
  });

  @override
  State<StoryPlayerPanel> createState() => _StoryPlayerPanelState();
}

class _StoryPlayerPanelState extends State<StoryPlayerPanel> {
  late int _page;
  bool _needsLocate = true;
  bool _locating = false;
  double _tileHeight = 52;

  /// 最近一次居中定位用的视口高：展开动画期间逐帧对比，变了就重定位。
  double? _lastLocateViewport;

  @override
  void initState() {
    super.initState();
    _page = _pageOf(widget.currentIndex);
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(StoryPlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.episodes, widget.episodes)) _needsLocate = true;
    if (oldWidget.currentIndex != widget.currentIndex) _needsLocate = true;
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  int get _columns => widget.columns;

  /// 头部剧信息区只有在宿主给了剧名或集数文案时才出现（官方该区块常显，
  /// 本地没有数据源时不显示，避免出现空壳封面）。embedded 由外层
  /// [PlayerSplitPanel] 展示剧信息，这里不再重复。
  bool get _hasHeader =>
      !widget.embedded &&
      (widget.seriesTitle.isNotEmpty || widget.episodeLabel.isNotEmpty);

  double get _headerHeight => 12 + 96;

  /// 官方头部剧信息（`aa8.xml:7-15`）：封面 `hdb`、标题 `hdt`、
  /// 右箭头 `right_icon`、集数行 `he1`（免费角标 `dga` + 文案 `hdz`）、
  /// 收藏 `ddg`。角标从官方绿色 `#FF00AE83` 改为
  /// `tertiaryContainer` / `onTertiaryContainer`（品牌色不写死）。
  Widget _seriesHeader(HomePalette palette) {
    final scheme = palette.scheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          if (widget.seriesCover.isNotEmpty)
            ClipRRect(
              borderRadius: Md3Shape.smallRadius,
              child: CachedNetworkImage(
                imageUrl: widget.seriesCover,
                width: 64,
                height: 86,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const _HeaderCoverFallback(),
              ),
            )
          else
            const _HeaderCoverFallback(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  key: const ValueKey('story-panel-series-title'),
                  borderRadius: Md3Shape.smallRadius,
                  onTap: widget.onOpenSeries,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.seriesTitle.isEmpty ? '短剧' : widget.seriesTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(color: palette.ink),
                        ),
                      ),
                      if (widget.onOpenSeries != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: palette.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (widget.freeWatch)
                      Container(
                        key: const ValueKey('story-panel-free-badge'),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer,
                          borderRadius: Md3Shape.extraSmallRadius,
                        ),
                        child: Text(
                          '免费观看',
                          style: text.labelSmall?.copyWith(
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    if (widget.episodeLabel.isNotEmpty)
                      Text(
                        widget.episodeLabel,
                        key: const ValueKey('story-panel-episode-label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: palette.muted),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _pageOf(int index) => (index ~/ _pageSize).clamp(0, _lastPage);

  int get _lastPage => math.max(0, (widget.episodes.length - 1) ~/ _pageSize);

  /// 官方打开面板时自动滚动并把当前集**居中定位**（`gj3/o.java:237-272,
  /// 1116-1186`，偏移=视口高/2−半格−12dp）；长剧同时切到所在分页。
  void _locateEpisode() {
    if (!_needsLocate) return;
    _needsLocate = false;
    // build 期间不允许 setState；分页条在下一帧读到新值。
    _page = _pageOf(widget.currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.scrollController.hasClients ||
          !widget.scrollController.position.hasContentDimensions ||
          widget.scrollController.position.viewportDimension <= 0) {
        _needsLocate = true;
        return;
      }
      _centerCurrentEpisode();
      _relocateWhileSheetExpands();
    });
  }

  /// 把当前集滚到视口竖直居中（真机验证：面板有 200ms 展开动画，首帧
  /// viewportDimension 是展开中的瞬时小值，展开完成后当前集被顶到列表
  /// 顶部——定位必须跟随视口长大重算）。
  void _centerCurrentEpisode() {
    final position = widget.scrollController.position;
    final row = widget.currentIndex ~/ _columns;
    final stride = _tileHeight + 8;
    final cellTop = 4 + row * stride;
    _lastLocateViewport = position.viewportDimension;
    _locating = true;
    widget.scrollController.jumpTo(
      (cellTop - position.viewportDimension / 2 + _tileHeight / 2 - 12).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
    _locating = false;
  }

  /// 展开期间视口每帧都在变：逐帧用新视口重定位，视口高稳定（动画结束）
  /// 即停。用户滚动不改视口高，不会误触发。
  void _relocateWhileSheetExpands() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.scrollController.hasClients ||
          !widget.scrollController.position.hasContentDimensions ||
          widget.scrollController.position.viewportDimension <= 0) {
        return;
      }
      final viewport = widget.scrollController.position.viewportDimension;
      final located = _lastLocateViewport;
      if (located != null && (viewport - located).abs() <= 0.5) return;
      _centerCurrentEpisode();
      _relocateWhileSheetExpands();
    });
  }

  /// 官方 tab 条滚动联动：可视区顶部所在行换页时更新选中的「1-30」段
  /// （`view/f.java:669-739`）。打开定位（jumpTo）不联动——官方打开时
  /// 选中页就是当前集所在页，用户滚动后才跟随可视区。
  void _onScroll() {
    if (_locating || !mounted || !widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    if (!position.hasContentDimensions || position.viewportDimension <= 0) {
      return;
    }
    final topRow = (position.pixels / (_tileHeight + 8)).floor();
    final page = (topRow * _columns) ~/ _pageSize;
    if (page != _page && page >= 0 && page <= _lastPage) {
      setState(() => _page = page);
    }
  }

  void _jumpToPage(int page) {
    setState(() => _page = page);
    if (!widget.scrollController.hasClients ||
        !widget.scrollController.position.hasContentDimensions) {
      return;
    }
    final position = widget.scrollController.position;
    final row = (page * _pageSize) ~/ _columns;
    widget.scrollController.jumpTo(
      (4 + row * (_tileHeight + 8)).clamp(0.0, position.maxScrollExtent),
    );
  }

  /// 官方不可播集的点击是 Toast「该选集暂时无法播放」
  /// （`hj3/r0.java:598-601`），不会切换集。
  void _select(int index) {
    if (index >= 0 &&
        index < widget.episodes.length &&
        widget.episodes[index].disabled) {
      PlayerToast.show(context, '该选集暂时无法播放');
      return;
    }
    widget.onSelectEpisode(index);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    final scale = MediaQuery.textScalerOf(context);
    final tabHeight = math.max(
      widget.onOpenRelatedSeries == null ? 40.0 : 48.0,
      scale.scale(14) + 22,
    );
    final showPaging = widget.episodes.length > _pageSize;
    final headerHeight =
        12 +
        tabHeight +
        // 与 [_pagingStrip] 的实际高度（最小触区 48）保持一致，
        // 少算会让展开动画首帧的固定头部溢出面板底部。
        (showPaging ? Md3Dimens.minTouchTarget : 0) +
        (widget.relateBook != null ? 64 : 0) +
        (_hasHeader ? _headerHeight : 0);
    // A sheet-height change only needs layout. Keep the existing header and
    // lazy list children; state/data/text-scale changes create a fresh build.
    Widget? contents;
    final body = LayoutBuilder(
      builder: (context, constraints) {
        _tileHeight = math.max(
          44.0,
          ((constraints.maxWidth - 24 - (_columns - 1) * 8) / _columns) *
              52 /
              53,
        );
        _locateEpisode();
        if (widget.embedded) {
          // 分屏面板已有固定头部与 Tab 行，这里只保留分页条和网格；
          // 外层 Expanded 给出有界高度，不需要 sheet 的 OverflowBox。
          return Column(
            children: [
              if (showPaging) _pagingStrip(palette),
              Expanded(child: _episodes(palette)),
            ],
          );
        }
        // While the sheet closes, clip the fixed header instead of
        // squeezing its controls into a zero-height Column.
        return OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: math.max(headerHeight, constraints.maxHeight),
          maxHeight: math.max(headerHeight, constraints.maxHeight),
          child: contents ??= Column(
            children: [
              GestureDetector(
                key: const ValueKey('story-panel-drag'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: widget.onDragStart,
                onVerticalDragUpdate: widget.onDragUpdate,
                onVerticalDragEnd: widget.onDragEnd,
                onVerticalDragCancel: widget.onDragCancel,
                child: Column(
                  children: [
                    SizedBox(
                      height: 12,
                      child: Center(
                        child: Container(
                          // 官方 grabber：36×4dp、圆角 2（`aa8.xml:6`）；
                          // M3 规范的 32×4 见 [Md3Dimens.dragHandleSize]，
                          // 颜色走 outlineVariant 而不是手调 alpha。
                          width: Md3Dimens.dragHandleSize.width,
                          height: Md3Dimens.dragHandleSize.height,
                          decoration: BoxDecoration(
                            color: palette.line,
                            borderRadius: Md3Shape.extraSmallRadius,
                          ),
                        ),
                      ),
                    ),
                    if (_hasHeader)
                      SizedBox(
                        key: const ValueKey('story-panel-series-header'),
                        height: _headerHeight,
                        child: _seriesHeader(palette),
                      ),
                    // 官方关联原著条（`aa8.xml:17` 的 `gnh`；左右各 16dp、
                    // 底 24dp 外边距）。配置默认关，宿主不给数据就不显示。
                    if (widget.relateBook != null)
                      Padding(
                        key: const ValueKey('story-panel-relate-book'),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: _relateBookRow(widget.relateBook!, palette),
                      ),
                    SizedBox(
                      height: tabHeight,
                      child: Row(
                        children: [
                          // 官方单 tab「选集」：14sp 粗体（`hj3/p.java:97-124`）。
                          // 字重降到 M3 的 w500，字号走 labelLarge 语义层。
                          Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: Text(
                              '选集',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    height: 1.0,
                                    fontWeight: FontWeight.w500,
                                    color: palette.ink,
                                    leadingDistribution:
                                        TextLeadingDistribution.even,
                                  ),
                            ),
                          ),
                          const Spacer(),
                          if (widget.onOpenRelatedSeries != null)
                            TextButton(
                              key: const ValueKey('story-panel-related-series'),
                              onPressed: widget.onOpenRelatedSeries,
                              // 按钮色走 palette：原来面板自建 ThemeData 丢掉
                              // 了外层 colorScheme，这个按钮会落到 Material
                              // 默认主色（紫蓝）。
                              style: TextButton.styleFrom(
                                foregroundColor: palette.accentText,
                              ),
                              child: const Text('同系列'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (showPaging) _pagingStrip(palette),
              Expanded(child: _episodes(palette)),
            ],
          ),
        );
      },
    );
    // 面板跟随外层主题（不再自建 ThemeData，否则丢 colorScheme 与深色预设）。
    if (widget.embedded) {
      return KeyedSubtree(key: const ValueKey('story-panel'), child: body);
    }
    return Material(
      key: const ValueKey('story-panel'),
      // 官方 `skin_bg_short_series_episode_dialog`：顶部圆角 16dp；
      // 深色 / OLED 取浮层色，和听书/评论弹层同一规则。
      color: homeSheetColor(palette),
      shape: homeSheetShape(palette, top: 16),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }

  /// 官方关联原著条：封面 + 书名，右侧箭头（`aa8.xml:17` 的 `gnh`）。
  Widget _relateBookRow(EpisodeRelateBook book, HomePalette palette) =>
      InkWell(
        borderRadius: Md3Shape.smallRadius,
        onTap: widget.onOpenRelateBook,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: palette.soft,
            borderRadius: Md3Shape.smallRadius,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: Md3Shape.extraSmallRadius,
                child: _relateCover(book.cover),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.ink),
                ),
              ),
              if (widget.onOpenRelateBook != null)
                Icon(LucideIcons.chevron_right, size: 18, color: palette.muted),
            ],
          ),
        ),
      );

  /// 原著封面；没有封面图时用统一的占位块。
  Widget _relateCover(String cover) {
    if (cover.isEmpty) return const _HeaderCoverFallback();
    return CachedNetworkImage(
      imageUrl: cover,
      width: 36,
      height: 44,
      fit: BoxFit.cover,
      errorWidget: (_, _, _) => const _HeaderCoverFallback(),
    );
  }

  Widget _pagingStrip(HomePalette palette) => SizedBox(
    key: const ValueKey('story-episode-pages'),
    // 分页条同时是点击目标，按 M3 最小触区放到 48dp。
    height: Md3Dimens.minTouchTarget,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (var page = 0; page <= _lastPage; page++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: InkWell(
              borderRadius: Md3Shape.smallRadius,
              onTap: () => _jumpToPage(page),
              child: Center(
                child: Text(
                  '${page * _pageSize + 1}-'
                  '${math.min((page + 1) * _pageSize, widget.episodes.length)}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: page == _page
                        ? FontWeight.w500
                        : FontWeight.w400,
                    color: page == _page ? palette.ink : palette.muted,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _episodes(HomePalette palette) {
    if (widget.episodes.isEmpty) {
      return Center(
        key: const ValueKey('story-episodes'),
        child: Text('暂无剧集', style: TextStyle(color: palette.muted)),
      );
    }
    return CustomScrollView(
      key: const ValueKey('story-episodes'),
      controller: widget.scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          sliver: SliverGrid(
            key: const ValueKey('story-episode-grid'),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              mainAxisExtent: _tileHeight,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, position) => _episodeTile(position),
              childCount: widget.episodes.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: 16 + MediaQuery.paddingOf(context).bottom),
        ),
      ],
    );
  }

  Widget _episodeTile(int index) {
    final palette = HomePalette.of(context);
    final scheme = palette.scheme;
    final episode = widget.episodes[index];
    final active = index == (widget.playingIndex ?? widget.currentIndex);
    final state = EpisodeTileState.of(
      current: active,
      watched: widget.watched.contains(index),
      disabled: episode.disabled,
    );
    final badge = episodeShowsNewBadge(
      current: active,
      played: widget.playingIndex == index,
      watched: widget.watched.contains(index),
      newlyUpdate: episode.newlyUpdate,
    );
    return Semantics(
      key: ValueKey('story-episode-$index'),
      label: '第 ${index + 1} 集',
      value: active ? (widget.playing ? '正在播放' : '当前剧集') : null,
      button: true,
      selected: active,
      excludeSemantics: true,
      onTap: () => _select(index),
      child: Material(
        color: state.backgroundColor(scheme),
        shape: const RoundedRectangleBorder(
          borderRadius: Md3Shape.smallRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _select(index),
          child: Stack(
            children: [
              Center(
                child: Text(
                  episodeTileLabel(
                    index: index,
                    trailer: episode.trailer,
                    highlight: episode.highlight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: state.weight,
                    color: state.textColor(scheme),
                  ),
                ),
              ),
              if (active)
                Positioned(
                  top: 4,
                  right: 4,
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: Lottie.asset(
                      'assets/lottie/video_playing_orange.json',
                      animate: widget.playing,
                      repeat: true,
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else if (badge)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    key: ValueKey('story-episode-new-$index'),
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: Md3State.pressed),
                      borderRadius: Md3Shape.smallRadius,
                    ),
                    child: Text(
                      '新',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 官方横屏选集面板（真实 app 截图第二十三轮）：**右侧抽屉**——深色底、
/// 头部 ✕ + 居中「选集」、4 列格子；当前集橙底（`#B3FA6725`，暗色上的
/// 半透明橙）+ 橙字 + 右上声波，普通格白字浅底，已看淡白。竖屏的白色
/// bottom sheet（`StoryPlayerPanel`）不在此复用——两态的皮肤/列数/头部
/// 都不同，定位逻辑各自维护。
class StoryEpisodeDrawer extends StatefulWidget {
  final List<Chapter> episodes;
  final int currentIndex;
  final int? playingIndex;
  final bool playing;
  final Set<int> watched;
  final ValueChanged<int> onSelectEpisode;
  final VoidCallback onClose;
  final VoidCallback? onOpenRelatedSeries;

  const StoryEpisodeDrawer({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.playingIndex,
    this.playing = false,
    this.watched = const <int>{},
    required this.onSelectEpisode,
    required this.onClose,
    this.onOpenRelatedSeries,
  });

  @override
  State<StoryEpisodeDrawer> createState() => _StoryEpisodeDrawerState();
}

class _StoryEpisodeDrawerState extends State<StoryEpisodeDrawer> {
  final _scroll = ScrollController();
  double _tile = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerCurrent());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 打开时把当前集滚到视口竖直居中（竖屏面板同款语义，
  /// `gj3/o.java:237-272`；抽屉无展开动画，一帧定位即可）。格子尺寸来自
  /// 抽屉宽度，首帧未排版时顺延一帧重试。
  void _centerCurrent() {
    if (!_scroll.hasClients ||
        !_scroll.position.hasContentDimensions ||
        _tile <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerCurrent();
      });
      return;
    }
    final position = _scroll.position;
    final row = widget.currentIndex ~/ 4;
    _scroll.jumpTo(
      (16 + row * (_tile + 8) - position.viewportDimension / 2 + _tile / 2)
          .clamp(0.0, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playingIndex = widget.playingIndex ?? widget.currentIndex;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      key: const ValueKey('story-episode-drawer'),
      // 抽屉是浮在视频上的侧面板：用最低一档容器色（OLED 下即纯黑）。
      color: scheme.surfaceContainerLowest,
      // 抽屉贴在右缘：横向只该让开**右侧**的安全区（右挖孔机型），左边
      // 那条是另一侧屏幕边缘的挖孔，套进来会把标题和格子整体推右。
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            SizedBox(
              height: 64,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      key: const ValueKey('story-drawer-close'),
                      tooltip: '关闭',
                      onPressed: widget.onClose,
                      icon: Icon(Icons.close, color: scheme.onSurface),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      '选集',
                      style: text.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (widget.onOpenRelatedSeries != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey('story-drawer-related-series'),
                        onPressed: widget.onOpenRelatedSeries,
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onSurface,
                        ),
                        child: const Text('同系列'),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 4 列方格：宽 =（抽屉宽 − 左右 24 − 列距 3×8）/ 4。
                  _tile = (constraints.maxWidth - 24 - 24) / 4;
                  return GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                    itemCount: widget.episodes.length,
                    itemBuilder: (context, index) {
                      final active = index == playingIndex;
                      final watched = !active && widget.watched.contains(index);
                      return Semantics(
                        key: ValueKey('story-episode-$index'),
                        label: '第 ${index + 1} 集',
                        value: active
                            ? (widget.playing ? '正在播放' : '当前剧集')
                            : null,
                        button: true,
                        selected: active,
                        excludeSemantics: true,
                        onTap: () => widget.onSelectEpisode(index),
                        child: Material(
                          color: active
                              ? scheme.primary.withValues(alpha: 0.7)
                              : scheme.surfaceContainerHighest,
                          shape: const RoundedRectangleBorder(
                            borderRadius: Md3Shape.smallRadius,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => widget.onSelectEpisode(index),
                            child: Stack(
                              children: [
                                Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: text.labelLarge?.copyWith(
                                      fontWeight: active
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                      color: active
                                          ? scheme.onPrimary
                                          : watched
                                          ? scheme.onSurfaceVariant
                                          : scheme.onSurface,
                                    ),
                                  ),
                                ),
                                if (active)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: Lottie.asset(
                                        'assets/lottie/video_playing_orange.json',
                                        animate: widget.playing,
                                        repeat: true,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
