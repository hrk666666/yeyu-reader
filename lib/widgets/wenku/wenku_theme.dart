import 'package:flutter/material.dart';

import '../../services/app_theme.dart';
import 'src/performance_preferences.dart';
import 'wenku_archive.dart';

/// 全部委托给 Flutter SDK 的官方 [Easing] / [Durations]。
///
/// 原先是 easeOutCubic / easeInCubic / Cubic(.2,1.08,.34,1) 这套自研曲线，
/// 与 m3.material.io 的 emphasized / standard easing 不一致。现在 16 个
/// 消费文件无需改动即可获得规范动效。
///
/// [spring] 是物理仿真用的 SpringDescription：基础 MD3 规范没有 spring
/// token（M3 Expressive 才引入），此处保留仅为兼容既有 SpringSimulation
/// 调用，不参与标准转场。
abstract final class WenkuMotion {
  static const contact = Durations.short3;
  static const enter = Durations.long1;
  static const exit = Durations.medium3;
  static const ease = Easing.emphasizedDecelerate;
  static const retract = Easing.emphasizedAccelerate;
  static const settle = Easing.standardDecelerate;
  static const spring = SpringDescription(
    mass: .64,
    stiffness: 270,
    damping: 19,
  );
}

/// The archive uses a neutral palette instead of fqapp's orange product accent.
/// The surrounding app keeps its own theme; this extension only changes the
/// ported Wenku8 surfaces below [WenkuScope].
@immutable
class WenkuAppearance extends ThemeExtension<WenkuAppearance> {
  const WenkuAppearance({
    required this.eink,
    required this.oled,
    required this.highContrast,
  });

  final bool eink;
  final bool oled;
  final bool highContrast;

  @override
  WenkuAppearance copyWith({bool? eink, bool? oled, bool? highContrast}) =>
      WenkuAppearance(
        eink: eink ?? this.eink,
        oled: oled ?? this.oled,
        highContrast: highContrast ?? this.highContrast,
      );

  @override
  WenkuAppearance lerp(WenkuAppearance? other, double t) => other == null
      ? this
      : WenkuAppearance(
          eink: t < .5 ? eink : other.eink,
          oled: t < .5 ? oled : other.oled,
          highContrast: t < .5 ? highContrast : other.highContrast,
        );
}

/// A small, interpolated set of archive/glass colors. Classic values reproduce
/// the upstream milk/stone palette exactly.
@immutable
class WenkuTonalColors extends ThemeExtension<WenkuTonalColors> {
  const WenkuTonalColors({
    required this.pageStart,
    required this.pageEnd,
    required this.milk,
    required this.darkMilk,
    required this.glassSurface,
    required this.active,
    required this.track,
    required this.thumb,
    required this.action,
  });

  final Color pageStart;
  final Color pageEnd;
  final Color milk;
  final Color darkMilk;
  final Color glassSurface;
  final Color active;
  final Color track;
  final Color thumb;
  final Color action;

  factory WenkuTonalColors.forScheme(
    ColorScheme scheme, {
    required bool eink,
    required bool oled,
    required bool highContrast,
  }) {
    if (eink) {
      return WenkuTonalColors(
        pageStart: Colors.white,
        pageEnd: Colors.white,
        milk: Colors.white,
        darkMilk: Colors.black,
        glassSurface: Colors.white,
        active: Colors.black,
        track: Colors.black,
        thumb: Colors.white,
        action: Colors.black,
      );
    }
    if (oled) {
      return WenkuTonalColors(
        pageStart: Colors.black,
        pageEnd: scheme.surfaceContainerLowest,
        milk: scheme.surfaceContainerLowest,
        darkMilk: scheme.onSurface,
        glassSurface: scheme.surface,
        active: scheme.onSurface,
        track: scheme.surfaceContainerHighest,
        thumb: scheme.onSurface,
        action: scheme.onSurface,
      );
    }
    // 官方 MD3：不再用上游牛奶 / 石头纸色，全部取 scheme 的 tonal role。
    // 「glassSurface」保留字段名以兼容调用方，语义改为 surfaceContainer
    // （MD3 没有毛玻璃表面，一律用 tonal elevation 分层）。
    return WenkuTonalColors(
      pageStart: scheme.surface,
      pageEnd: scheme.surfaceContainerLow,
      milk: scheme.surfaceContainerLowest,
      darkMilk: scheme.onSurface,
      glassSurface: scheme.surfaceContainer,
      active: scheme.primary,
      track: scheme.surfaceContainerHighest,
      thumb: scheme.primary,
      action: scheme.onSurface,
    );
  }

  Color tint(Brightness brightness, double opacity) =>
      brightness == Brightness.dark
      ? Color.lerp(darkMilk, glassSurface, opacity.clamp(0, 1))!
      : milk;

  @override
  WenkuTonalColors copyWith({
    Color? pageStart,
    Color? pageEnd,
    Color? milk,
    Color? darkMilk,
    Color? glassSurface,
    Color? active,
    Color? track,
    Color? thumb,
    Color? action,
  }) => WenkuTonalColors(
    pageStart: pageStart ?? this.pageStart,
    pageEnd: pageEnd ?? this.pageEnd,
    milk: milk ?? this.milk,
    darkMilk: darkMilk ?? this.darkMilk,
    glassSurface: glassSurface ?? this.glassSurface,
    active: active ?? this.active,
    track: track ?? this.track,
    thumb: thumb ?? this.thumb,
    action: action ?? this.action,
  );

  @override
  WenkuTonalColors lerp(WenkuTonalColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return WenkuTonalColors(
      pageStart: c(pageStart, other.pageStart),
      pageEnd: c(pageEnd, other.pageEnd),
      milk: c(milk, other.milk),
      darkMilk: c(darkMilk, other.darkMilk),
      glassSurface: c(glassSurface, other.glassSurface),
      active: c(active, other.active),
      track: c(track, other.track),
      thumb: c(thumb, other.thumb),
      action: c(action, other.action),
    );
  }
}

abstract final class WenkuTheme {
  static const ink = Color(0xFF181818);
  static const accent = Color(0xFF202020);
  static const canvas = ArchiveDesign.background;
  static const hairline = Color(0xFFD8DBD5);

  static WenkuAppearance appearanceOf(BuildContext context) =>
      Theme.of(context).extension<WenkuAppearance>() ??
      const WenkuAppearance(eink: false, oled: false, highContrast: false);

  static bool isEinkOf(BuildContext context) => appearanceOf(context).eink;

  static ThemeData create(
    Brightness requestedBrightness, {
    bool eink = false,
    bool oled = false,
    bool highContrast = false,
  }) {
    if (eink) {
      return _withWenkuExtensions(
        AppTheme.createTheme(Brightness.light, einkMode: true),
        eink: true,
        oled: false,
        highContrast: highContrast,
      );
    }
    // 关键改动：wenku 页面不再自建一套单色 ThemeData。
    //
    // 原先这里用 ColorScheme.fromSeed(monochrome) + 手抄 textTheme /
    // InkRipple / 4dp 圆角 / 自定义 snackbar，导致 WenkuScope 包裹的 11 个
    // 页面与全 App 主题完全割裂。现在统一复用 [AppTheme.createTheme] 的官方
    // MD3 ThemeData，只把 WenkuAppearance / WenkuTonalColors 两个
    // ThemeExtension 叠加上去（页面仍需要它们读取 eink / oled 标志）。
    final ThemeData base = AppTheme.createTheme(
      requestedBrightness,
      oledMode: oled && requestedBrightness == Brightness.dark,
    );
    return _withWenkuExtensions(
      base,
      eink: false,
      oled: oled && requestedBrightness == Brightness.dark,
      highContrast: highContrast,
    );
  }

  static ThemeData _withWenkuExtensions(
    ThemeData theme, {
    required bool eink,
    required bool oled,
    required bool highContrast,
  }) => theme.copyWith(
    extensions: [
      WenkuAppearance(eink: eink, oled: oled, highContrast: highContrast),
      WenkuTonalColors.forScheme(
        theme.colorScheme,
        eink: eink,
        oled: oled,
        highContrast: highContrast,
      ),
    ],
  );
}

/// Applies the ported Wenku8 monochrome theme and its finite entrance clock.
///
/// A host may wrap several pages in one scope. [WenkuPage] detects that scope
/// and will not install a second theme or animation controller.
class WenkuScope extends StatefulWidget {
  const WenkuScope({
    super.key,
    required this.child,
    this.reduceMotion,
    this.highContrast,
    this.entrance = true,
    this.performance = const PerformancePreferences(),
  });

  final Widget child;
  final bool? reduceMotion;
  final bool? highContrast;
  final bool entrance;
  final PerformancePreferences performance;

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WenkuScopeMarker>() != null;

  @override
  State<WenkuScope> createState() => _WenkuScopeState();
}

class _WenkuScopeState extends State<WenkuScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: WenkuMotion.enter,
      value: widget.entrance ? 0 : 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(WenkuScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entrance != widget.entrance ||
        oldWidget.reduceMotion != widget.reduceMotion ||
        oldWidget.performance != widget.performance) {
      _syncMotion();
    }
  }

  void _syncMotion() {
    final media = MediaQuery.maybeOf(context);
    final eink = einkModeNotifier.value;
    final reduce =
        widget.reduceMotion ??
        ((media?.disableAnimations ?? false) ||
            (widget.performance.enabled && !widget.performance.motion));
    if (!widget.entrance || eink || reduce) {
      _entrance
        ..stop()
        ..value = 1;
      return;
    }
    if (_started || _entrance.value > 0) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entrance.value == 0) _entrance.forward();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media =
        MediaQuery.maybeOf(context) ??
        const MediaQueryData(size: Size(800, 600));
    final outer = Theme.of(context);
    final eink = einkModeNotifier.value;
    final oled = !eink && oledActive(systemBrightness: outer.brightness);
    final highContrast = widget.highContrast ?? media.highContrast;
    final reduceMotion = widget.reduceMotion ?? media.disableAnimations;
    final disableAnimations =
        reduceMotion ||
        eink ||
        (widget.performance.enabled && !widget.performance.motion);
    final effectiveMedia = media.copyWith(
      disableAnimations: disableAnimations,
      highContrast: highContrast,
    );
    final theme = WenkuTheme.create(
      outer.brightness,
      eink: eink,
      oled: oled,
      highContrast: highContrast,
    );
    return MediaQuery(
      data: effectiveMedia,
      child: Theme(
        data: theme,
        child: PerformanceScope(
          preferences: widget.performance,
          explicitReduceMotion: disableAnimations,
          child: ArchiveMotionScope(
            animation: _entrance,
            enabled: !disableAnimations,
            child: _WenkuScopeMarker(
              eink: eink,
              oled: oled,
              highContrast: highContrast,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _WenkuScopeMarker extends InheritedWidget {
  const _WenkuScopeMarker({
    required this.eink,
    required this.oled,
    required this.highContrast,
    required super.child,
  });

  final bool eink;
  final bool oled;
  final bool highContrast;

  @override
  bool updateShouldNotify(_WenkuScopeMarker oldWidget) =>
      eink != oldWidget.eink ||
      oled != oldWidget.oled ||
      highContrast != oldWidget.highContrast;
}
