import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../theme/md3.dart';

/// Persisted theme-mode preference key: 'theme_mode' = 'light'|'dark'|'system'.
/// 墨水屏是第四种外观，单独存 [einkModeKey]。
const themeModeKey = 'theme_mode';

/// Brand seed color for the whole app (also used by the player slider and
/// the detail page's accent text).
const appSeedColor = Color(0xFFEF5038);

/// Global theme-mode notifier; the settings page writes it, MaterialApp
/// rebuilds with the new mode.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
);

/// Persisted e-ink mode key: 'eink_mode' = bool.
/// #15/#9：墨水屏模式（设置 → 外观 → 主题模式的第四项）。开启时全应用
/// 纯黑白、无毛玻璃、无过渡动画，避免墨水屏量化灰阶 / 残影。切回其它
/// 主题即恢复。
const einkModeKey = 'eink_mode';

/// Global e-ink mode notifier; the settings page writes it, MaterialApp
/// rebuilds with the e-ink theme.
final ValueNotifier<bool> einkModeNotifier = ValueNotifier(false);

/// Persisted OLED pure-black key: 'oled_mode' = bool.
/// OLED 模式：大面积底色用纯黑省电；卡片 / 弹层等交互表面保持近黑 + 描边，
/// 避免纯黑把文字、图标和纯黑海报一起吞掉。只在深色外观下生效（跟随系统
/// 时看系统亮度），与墨水屏互斥。
const oledModeKey = 'oled_mode';

/// Global OLED mode notifier; the settings page writes it, MaterialApp
/// rebuilds with the pure-black palette.
final ValueNotifier<bool> oledModeNotifier = ValueNotifier(false);

/// 当前外观实际是不是深色：墨水屏恒为浅色（纯黑白），跟随系统时取系统亮度。
/// [systemBrightness] 供设置页传入 `MediaQuery.platformBrightnessOf(context)`，
/// 这样系统切换深浅色时页面会跟着重建；其余调用方省略即可。
bool isDarkAppearance({Brightness? systemBrightness}) {
  if (einkModeNotifier.value) return false;
  switch (themeModeNotifier.value) {
    case ThemeMode.light:
      return false;
    case ThemeMode.dark:
      return true;
    case ThemeMode.system:
      return (systemBrightness ??
              PlatformDispatcher.instance.platformBrightness) ==
          Brightness.dark;
  }
}

/// OLED 纯黑当前是否生效：开关打开并且外观确实处于深色。深色以外的外观
/// 忽略该开关，阅读页 / 首页色板都按它取纯黑白板。
bool oledActive({Brightness? systemBrightness}) =>
    oledModeNotifier.value &&
    isDarkAppearance(systemBrightness: systemBrightness);

/// No page transition: e-ink screens ghost on every animated frame, so
/// route changes must swap instantly instead of sliding / fading.
class _NoPageTransitionBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

ThemeMode themeModeFromName(String? name) {
  switch (name) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// Unified design system and theme factory for fqapp.
class AppTheme {
  static const Color accent = Color(0xFFEF5038);
  static const Color accentStrong = Color(0xFFC73D29);
  static const Color accentDark = Color(0xFFF05E47);

  /// Pure black-on-white theme for e-ink (#15/#9). No tonal / seed palette,
  /// no grey scale except black-on-white, no ripple, no page transition.
  /// Dark mode is intentionally not honoured here: inverted e-ink pages
  /// ghost badly and the issue asks for #FFFFFF surface / #000000 text.
  static ThemeData _createEinkTheme() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Colors.black,
      onPrimary: Colors.white,
      primaryContainer: Colors.white,
      onPrimaryContainer: Colors.black,
      secondary: Colors.black,
      onSecondary: Colors.white,
      secondaryContainer: Colors.white,
      onSecondaryContainer: Colors.black,
      tertiary: Colors.black,
      onTertiary: Colors.white,
      surface: Colors.white,
      onSurface: Colors.black,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerHigh: Colors.white,
      surfaceContainerHighest: Colors.white,
      onSurfaceVariant: Colors.black,
      outline: Colors.black,
      outlineVariant: Colors.black,
      error: Colors.black,
      onError: Colors.white,
      errorContainer: Colors.white,
      onErrorContainer: Colors.black,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoPageTransitionBuilder(),
          TargetPlatform.iOS: _NoPageTransitionBuilder(),
          TargetPlatform.macOS: _NoPageTransitionBuilder(),
          TargetPlatform.windows: _NoPageTransitionBuilder(),
          TargetPlatform.linux: _NoPageTransitionBuilder(),
          TargetPlatform.fuchsia: _NoPageTransitionBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          color: Colors.black,
        ),
        iconTheme: IconThemeData(size: 22, color: Colors.black),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Md3Shape.mediumRadius,
          side: const BorderSide(color: Colors.black, width: 0.6),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Md3Shape.extraLargeRadius,
          side: const BorderSide(color: Colors.black, width: 0.6),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w400,
          color: Colors.black,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          color: Colors.black,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Md3Shape.sheetTop,
        ),
        dragHandleColor: Colors.black,
        dragHandleSize: Md3Dimens.dragHandleSize,
      ),
      dividerTheme: const DividerThemeData(
        color: Colors.black,
        thickness: 0.6,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: false,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: Colors.black,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Colors.black,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.black,
        contentTextStyle: const TextStyle(fontSize: 13, color: Colors.white),
      ),
    );
  }

  /// 官方 MD3 动态色：以品牌色为 seed 生成完整 tonal palette。
  ///
  /// 静态缓存，避免每帧重算 HCT；[HomePalette] 与 [WenkuTheme] 都复用这里
  /// 的同一份 scheme，全 App 只有一个配色源头。
  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: appSeedColor,
    brightness: Brightness.light,
  );
  static final ColorScheme _darkScheme = ColorScheme.fromSeed(
    seedColor: appSeedColor,
    brightness: Brightness.dark,
  );

  static ColorScheme md3Scheme(Brightness brightness) =>
      brightness == Brightness.dark ? _darkScheme : _lightScheme;

  /// OLED 纯黑是显式的省电 / 可访问性变体，不属于标准 MD3 外观：
  /// 它把 surface 层级压成纯黑并保留一圈发丝描边，否则黑底黑卡无法分辨。
  /// 标准模式（oled=false）完全走 [ColorScheme.fromSeed] 的官方 tonal 值。
  static ColorScheme _oledScheme() => _darkScheme.copyWith(
    surface: const Color(0xFF0C0C0E),
    surfaceContainerLowest: Colors.black,
    surfaceContainerLow: const Color(0xFF121215),
    surfaceContainer: const Color(0xFF17171A),
    surfaceContainerHigh: const Color(0xFF1F1F23),
    surfaceContainerHighest: const Color(0xFF27272C),
    onSurface: const Color(0xFFF5F1EB),
    outline: const Color(0xFF8A867F),
    outlineVariant: const Color(0xFF3F3F47),
  );

  static ThemeData createTheme(
    Brightness brightness, {
    bool einkMode = false,
    bool oledMode = false,
  }) {
    if (einkMode) return _createEinkTheme();
    final isDark = brightness == Brightness.dark;
    // OLED 纯黑只在深色下成立；浅色模式忽略该开关。
    final oled = oledMode && isDark;
    final scheme = oled ? _oledScheme() : md3Scheme(brightness);

    // 不覆盖 pageTransitionsTheme、textTheme、splashFactory、visualDensity：
    // Flutter 在 useMaterial3 下给的就是官方默认值（Zoom/FadeForwards 转场、
    // Typography.material2021、InkSparkle、standard density）。自己抄一遍
    // 数值反而容易与 SDK 版本漂移。
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: oled ? Colors.black : scheme.surface,
      canvasColor: oled ? Colors.black : scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: oled ? Colors.black : scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: Md3Elevation.level0,
        scrolledUnderElevation: Md3Elevation.level2,
        centerTitle: false, // 官方 small top app bar 标题左对齐
        iconTheme: IconThemeData(size: 24, color: scheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: scheme.surfaceTint,
        elevation: Md3Elevation.level1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Md3Shape.mediumRadius,
          side: oled
              ? const BorderSide(color: Color(0xFF2E2E34), width: 0.8)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: scheme.surfaceTint,
        elevation: Md3Elevation.level3,
        shape: Md3Shape.dialogShape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: scheme.surfaceTint,
        elevation: Md3Elevation.level1,
        modalElevation: Md3Elevation.level1,
        shape: const RoundedRectangleBorder(borderRadius: Md3Shape.sheetTop),
        showDragHandle: true,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
        dragHandleSize: Md3Dimens.dragHandleSize,
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: false,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: Md3Shape.extraSmallRadius,
        ),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        elevation: Md3Elevation.level3,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: Md3Dimens.navigationBarHeight,
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: scheme.surfaceTint,
        elevation: Md3Elevation.level2,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: Md3Shape.navIndicatorShape,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        minWidth: Md3Dimens.navigationRailWidth,
        elevation: Md3Elevation.level0,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: Md3Shape.navIndicatorShape,
        elevation: Md3Elevation.level1,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: scheme.surfaceTint,
        elevation: Md3Elevation.level1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(Md3Shape.extraLarge),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, Md3Dimens.minTouchTarget),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, Md3Dimens.minTouchTarget),
          elevation: Md3Elevation.level1,
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, Md3Dimens.minTouchTarget),
          side: BorderSide(color: scheme.outline),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, Md3Dimens.minTouchTarget),
          shape: const StadiumBorder(),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: Md3Elevation.level3,
        focusElevation: Md3Elevation.level3,
        hoverElevation: Md3Elevation.level4,
        shape: const RoundedRectangleBorder(
          borderRadius: Md3Shape.largeRadius,
        ),
        sizeConstraints: const BoxConstraints.tightFor(
          width: Md3Dimens.fabSize,
          height: Md3Dimens.fabSize,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: const StadiumBorder(),
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textColor: scheme.onError,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: Md3Shape.extraSmallRadius,
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.secondaryContainer,
        disabledColor: scheme.surfaceContainerLow,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(
          borderRadius: Md3Shape.smallRadius,
        ),
        labelStyle: TextStyle(color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(color: scheme.onSecondaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(Md3Dimens.minTouchTarget),
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
