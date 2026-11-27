import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/app_theme.dart';
import '../../services/audio_page_theme.dart';
import '../../services/poster_cache.dart';
import '../../theme/md3.dart';
import 'audio_floating_glyphs.dart';

/// The expanded dk5/hm.xml player; experimental edge folding stays disabled.
class AudioFloatingPlayer extends StatefulWidget {
  const AudioFloatingPlayer({
    super.key,
    required this.title,
    required this.cover,
    required this.progress,
    required this.readProgress,
    required this.playing,
    required this.loading,
    required this.canToggle,
    required this.visible,
    required this.bottomInset,
    required this.onOpen,
    required this.onToggle,
    required this.onClose,
    this.onMore,
    this.canMore = true,
    this.inReaderMenu = false,
    this.monochrome = false,
    this.keyPrefix = 'audio-floating',
  });

  final String title;
  final String cover;

  /// Notifies when [readProgress] changes, without rebuilding the capsule.
  final Listenable progress;

  /// Played fraction of the current item, 0..1 (official `fa3/a` ring).
  final double Function() readProgress;
  final bool playing;
  final bool loading;
  final bool canToggle;
  final bool visible;
  final double bottomInset;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  /// 阅读菜单内那颗三点的动作。
  ///
  /// 语义随胶囊状态变：未播放是「选择播放引擎」，官方播放中是音色面板，
  /// 系统朗读中是朗读设置。桌面悬浮胶囊不传，那里没有菜单上下文。
  final VoidCallback? onMore;

  /// Keeps [onMore] visible but disabled while the action is in flight.
  final bool canMore;
  final bool inReaderMenu;
  final bool monochrome;

  /// 前缀给按钮的 key。悬浮胶囊与阅读菜单内那颗是同一个控件，同时存在时
  /// key 必须能区分，否则自动化只能靠出现顺序猜。
  final String keyPrefix;

  @override
  State<AudioFloatingPlayer> createState() => _AudioFloatingPlayerState();
}

class _AudioFloatingPlayerState extends State<AudioFloatingPlayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _width = 162.0;
  static const _height = 50.0;
  late final _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  /// 封面取色结果（官方取 Palette swatch 色相后套固定饱和度/明度）。
  /// null = 没取到色，用 `surfaceContainerHigh` 兜底。
  Color? _coverBackground;
  bool _right = false;
  double _vertical = 1;
  Offset? _drag;
  bool _closing = false;
  Timer? _closeTimer;
  bool _systemReducedMotion = false;
  bool get _eink => widget.monochrome || einkModeNotifier.value;
  bool get _reducedMotion => _systemReducedMotion || _eink;
  bool _active =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    einkModeNotifier.addListener(_motionChanged);
    unawaited(_loadColor());
  }

  void _motionChanged() {
    setState(() {});
    _syncRotation();
  }

  Future<void> _loadColor() async {
    final cover = widget.cover;
    // 官方 GlobalPlayerView 取 Palette swatch 的色相，再套固定的饱和度/明度。
    final hue = await fetchCoverPaletteHue(cover);
    if (!mounted || widget.cover != cover) return;
    setState(() {
      _coverBackground = hue == null
          ? null
          : HSVColor.fromAHSV(252 / 255, hue, 0.23, 0.54).toColor();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _systemReducedMotion =
        media.disableAnimations || media.accessibleNavigation;
    _syncRotation();
  }

  @override
  void didUpdateWidget(AudioFloatingPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cover != widget.cover) {
      _coverBackground = null;
      unawaited(_loadColor());
    }
    _syncRotation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _syncRotation();
  }

  void _syncRotation() {
    if (_active &&
        widget.visible &&
        widget.playing &&
        !widget.loading &&
        !_reducedMotion &&
        !_closing) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
    }
  }

  void _close() {
    if (_closing) return;
    if (_reducedMotion) {
      widget.onClose();
      return;
    }
    setState(() => _closing = true);
    _syncRotation();
    // A route may hide/mute the widget during the dismissal animation.
    _closeTimer = Timer(Md3Motion.medium2, () {
      _closeTimer = null;
      widget.onClose();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    einkModeNotifier.removeListener(_motionChanged);
    if (_closeTimer != null) {
      _closeTimer!.cancel();
      // Returning the menu's borrowed view must not cancel a requested stop.
      widget.onClose();
    }
    _rotation.dispose();
    super.dispose();
  }

  // Official plain click targets: no tooltip; M3 state layer 由 InkWell 提供。
  Widget _button({
    required Key key,
    required String label,
    required double width,
    required VoidCallback? onTap,
    required Widget child,
  }) => Semantics(
    key: key,
    container: true,
    button: true,
    enabled: onTap != null,
    label: label,
    onTap: onTap,
    child: InkWell(
      // 胶囊本身是 StadiumBorder：水波也必须是胶囊，方角会溢出圆角。
      borderRadius: BorderRadius.circular(_height),
      excludeFromSemantics: true,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: _height,
        child: Center(child: ExcludeSemantics(child: child)),
      ),
    ),
  );

  Widget _capsule(BuildContext context, {double closeProgress = 0}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final eink = _eink;
    final more = widget.inReaderMenu ? widget.onMore : null;
    // Background and cover fade linearly across the 300ms dismissal; the
    // play/close icons finish their 200ms fade earlier.
    final fade = (1 - closeProgress).clamp(0.0, 1.0);
    final controlFade =
        (1 -
                Md3Motion.standardOut.transform(
                  (closeProgress * 1.5).clamp(0.0, 1.0),
                ))
            .clamp(0.0, 1.0);
    // 官方取封面色相染胶囊；取不到时用 M3 浮层色（不再写死 #666666）。
    final background = eink
        ? scheme.surface
        : (_coverBackground ?? scheme.surfaceContainerHigh);
    // 胶囊底色来自封面取色（可能偏暗），图标用与底色对比的语义前景。
    final ink = eink
        ? scheme.onSurface
        : (ThemeData.estimateBrightnessForColor(background) == Brightness.dark
              ? Colors.white
              : scheme.onSurface);
    // Official skin_loading_book_cover_light: a flat grey cover, no glyph.
    final placeholder = ColoredBox(color: scheme.surfaceContainerHighest);
    final cover = ClipOval(
      child: SizedBox.square(
        dimension: 42,
        child: RotationTransition(
          turns: _rotation,
          child: widget.cover.isEmpty
              ? placeholder
              : CachedNetworkImage(
                  imageUrl: widget.cover,
                  cacheManager: PosterCache.instance,
                  fit: BoxFit.cover,
                  memCacheWidth: (42 * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                  fadeInDuration: Duration.zero,
                  placeholder: (_, _) => placeholder,
                  errorWidget: (_, _, _) => placeholder,
                  // 夜间把封面压暗一档（遮罩走 scrim role）。
                  color: dark
                      ? scheme.scrim.withValues(alpha: Md3State.dragged)
                      : null,
                  colorBlendMode: BlendMode.darken,
                ),
        ),
      ),
    );
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: background),
      // 官方用 TransitionDrawable 做 300ms 交叉淡入；夜间/墨水屏保持瞬切。
      duration: eink || dark ? Duration.zero : Md3Motion.medium2,
      builder: (context, color, child) {
        final tint = color ?? background;
        return Card(
          color: tint.withValues(alpha: tint.a * fade),
          surfaceTintColor: Colors.transparent,
          // 浮在页面内容之上：用 M3 level2 高度出层，不再手绘阴影。
          elevation: Md3Elevation.level2,
          margin: EdgeInsets.zero,
          shape: StadiumBorder(
            side: eink ? const BorderSide() : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
      child: Row(
        children: [
          const SizedBox(width: 4),
          _button(
            key: ValueKey("${widget.keyPrefix}-open"),
            label: '\u6253\u5f00\u542c\u4e66\uff1a${widget.title}',
            width: 42,
            onTap: widget.onOpen,
            child: Opacity(opacity: fade, child: cover),
          ),
          SizedBox(width: more == null ? 14 : 2),
          _button(
            key: ValueKey("${widget.keyPrefix}-toggle"),
            label: widget.loading
                ? '\u6b63\u5728\u52a0\u8f7d'
                : widget.playing
                ? '\u6682\u505c\u64ad\u653e'
                : '\u7ee7\u7eed\u64ad\u653e',
            width: 32,
            // Buffering keeps the button live, as on the listening page.
            onTap: widget.canToggle ? widget.onToggle : null,
            child: SizedBox.square(
              dimension: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Official LOADING keeps the icon and swaps the ring for a
                  // rotating white sweep (`fa3/a.java:48-58`). The ring frame
                  // is not faded on close (`pn2/b0.java:288-314`).
                  if (widget.loading)
                    LoadingRing(color: ink, animate: !_reducedMotion)
                  else
                    ListenableBuilder(
                      listenable: widget.progress,
                      builder: (context, _) {
                        final value = widget.readProgress();
                        return CustomPaint(
                          size: const Size.square(32),
                          painter: RingPainter(
                            progress: value.isFinite
                                ? value.clamp(0.0, 1.0)
                                : 0,
                            color: ink,
                          ),
                        );
                      },
                    ),
                  Opacity(
                    opacity: controlFade,
                    child: CustomPaint(
                      // 官方 `pn2/b0.java:819-823` 把播放图形覆盖为 16dp。
                      size: const Size.square(16),
                      painter: widget.playing
                          ? PauseGlyph(ink)
                          : PlayGlyph(ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (more != null) ...[
            const SizedBox(width: 2),
            _button(
              key: ValueKey("${widget.keyPrefix}-more"),
              label: '更多选项',
              width: 26,
              onTap: widget.canMore ? more : null,
              child: Opacity(
                opacity: controlFade * (widget.canMore ? 1 : 0.45),
                child: CustomPaint(
                  size: const Size.square(16),
                  painter: MoreGlyph(ink),
                ),
              ),
            ),
            const SizedBox(width: 2),
          ] else
            const SizedBox(width: 10),
          _button(
            key: ValueKey("${widget.keyPrefix}-close"),
            label: '\u5173\u95ed\u64ad\u653e',
            width: 26,
            onTap: _close,
            // Official swaps `cav` for the 16dp `alh` cross in code.
            child: Opacity(
              opacity: controlFade,
              child: CustomPaint(
                size: const Size.square(16),
                painter: CloseGlyph(ink),
              ),
            ),
          ),
          SizedBox(width: more == null ? 10 : 2),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inReaderMenu) return _readerMenuPlayer();
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        // Rest rect: 1dp inset on each side (still respecting safe areas),
        // 142dp from the top, bottom margin = 18 + bottom safe area / IME.
        final left = math.max(1.0, media.viewPadding.left);
        final right = width - math.max(1.0, media.viewPadding.right) - _width;
        final top = 142.0;
        final bottom =
            height -
            _height -
            18 -
            math.max(
              media.viewPadding.bottom + widget.bottomInset,
              media.viewInsets.bottom,
            );
        if (right < left || bottom < top) return const SizedBox.shrink();
        final rest = Offset(
          _right ? right : left,
          top + (bottom - top) * _vertical,
        );
        // While dragging the capsule may leave the rest rect: horizontally
        // -12dp..width+12dp (folding is off) and vertically the whole container.
        final dragLeft = -12.0;
        final dragRight = math.max(dragLeft, width + 12 - _width);
        final dragBottom = math.max(0.0, height - _height);
        Offset dragBounded(Offset value) => Offset(
          value.dx.clamp(dragLeft, dragRight),
          value.dy.clamp(0.0, dragBottom),
        );
        final position = _drag == null ? rest : dragBounded(_drag!);
        void snap() {
          final released = _drag ?? position;
          setState(() {
            _right = released.dx + _width / 2 >= width / 2;
            _vertical = bottom == top
                ? 1
                : ((released.dy - top) / (bottom - top)).clamp(0.0, 1.0);
            _drag = null;
          });
        }

        return Visibility(
          visible: widget.visible,
          maintainState: true,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: _drag != null || _reducedMotion
                    ? Duration.zero
                    : Md3Motion.short4,
                curve: Md3Motion.standard,
                left: position.dx,
                top: position.dy,
                width: _width,
                height: _height,
                child: IgnorePointer(
                  ignoring: _closing,
                  child: GestureDetector(
                    onPanStart: (_) => setState(() => _drag = position),
                    onPanUpdate: (details) => setState(() {
                      _drag = dragBounded((_drag ?? position) + details.delta);
                    }),
                    onPanEnd: (_) => snap(),
                    onPanCancel: snap,
                    child: _dismissal(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _readerMenuPlayer() => Visibility(
    visible: widget.visible,
    maintainState: true,
    maintainSize: true,
    maintainAnimation: true,
    child: SizedBox(
      width: _width,
      height: _height,
      child: IgnorePointer(ignoring: _closing, child: _dismissal()),
    ),
  );

  /// Official close (`pn2/b0.java:288-314`): 162→74dp over 300ms, always
  /// anchored to the left; the capsule fades its own parts inside.
  Widget _dismissal() => TweenAnimationBuilder<double>(
    tween: Tween(end: _closing ? 1 : 0),
    duration: Md3Motion.medium2,
    builder: (context, value, child) {
      final shrink = Md3Motion.emphasized.transform(value);
      return Align(
        alignment: Alignment.centerLeft,
        child: ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1 - shrink * (_width - 74) / _width,
            child: RepaintBoundary(
              child: Padding(
                // The four-control reader variant keeps the official 138dp
                // content footprint instead of growing toward the right-hand
                // f7s listen button.
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _capsule(context, closeProgress: value),
              ),
            ),
          ),
        ),
      );
    },
  );
}
