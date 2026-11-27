import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fqapp/services/app_theme.dart';
import 'package:fqapp/theme/md3.dart';
import 'package:fqapp/widgets/shell_dock.dart';

/// MD3 改造的规范符合性测试。
///
/// 这里不重复实现规范，而是断言「实现确实委托给了 Flutter SDK 的官方
/// 常量 / 官方组件」——防止后续有人把手写色板、自研曲线、自研导航悄悄
/// 加回来。
void main() {
  group('官方 MD3 动态配色', () {
    test('浅/深主题都来自 ColorScheme.fromSeed 的 tonal palette', () {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.createTheme(brightness);
        final seed = ColorScheme.fromSeed(
          seedColor: appSeedColor,
          brightness: brightness,
        );
        expect(theme.useMaterial3, isTrue);
        expect(theme.colorScheme.primary, seed.primary);
        expect(theme.colorScheme.onPrimary, seed.onPrimary);
        expect(theme.colorScheme.surface, seed.surface);
        expect(theme.colorScheme.surfaceContainerLow, seed.surfaceContainerLow);
        expect(
          theme.colorScheme.surfaceContainerHighest,
          seed.surfaceContainerHighest,
        );
        expect(theme.colorScheme.outlineVariant, seed.outlineVariant);
        expect(theme.scaffoldBackgroundColor, seed.surface);
        expect(theme.canvasColor, seed.surface);
      }
    });

    test('官方组件主题取官方 role / shape / elevation', () {
      final theme = AppTheme.createTheme(Brightness.light);
      final scheme = theme.colorScheme;

      // M3 surfaceTint + surfaceContainer 才是官方高度模型，不是自研描边。
      expect(theme.appBarTheme.surfaceTintColor, scheme.surfaceTint);
      expect(
        theme.appBarTheme.scrolledUnderElevation,
        Md3Elevation.level2,
      );
      expect(theme.appBarTheme.centerTitle, isFalse); // small app bar 左对齐

      final card = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(card.borderRadius, Md3Shape.mediumRadius);
      expect(theme.cardTheme.color, scheme.surfaceContainerLow);
      expect(theme.cardTheme.elevation, Md3Elevation.level1);

      expect(theme.dialogTheme.shape, Md3Shape.dialogShape);
      expect(theme.dialogTheme.backgroundColor, scheme.surfaceContainerHigh);
      expect(theme.dividerTheme.color, scheme.outlineVariant);
      expect(theme.snackBarTheme.backgroundColor, scheme.inverseSurface);
      expect(
        theme.navigationBarTheme.height,
        Md3Dimens.navigationBarHeight,
      );
      expect(
        theme.navigationBarTheme.indicatorColor,
        scheme.secondaryContainer,
      );
      expect(
        theme.bottomSheetTheme.dragHandleSize,
        Md3Dimens.dragHandleSize,
      );
      expect(theme.bottomSheetTheme.showDragHandle, isTrue);
    });

    test('OLED 是显式可访问性变体，不污染标准外观', () {
      final standard = AppTheme.createTheme(Brightness.dark);
      final oled = AppTheme.createTheme(Brightness.dark, oledMode: true);
      expect(standard.scaffoldBackgroundColor, isNot(Colors.black));
      expect(oled.scaffoldBackgroundColor, Colors.black);
      expect(oled.colorScheme.surface, const Color(0xFF0C0C0E));
      // 浅色下 OLED 开关必须被忽略。
      expect(
        AppTheme.createTheme(Brightness.light, oledMode: true).colorScheme.surface,
        AppTheme.md3Scheme(Brightness.light).surface,
      );
    });
  });

  group('官方 MD3 motion', () {
    test('SDK 的 Easing / Durations 就是规范数值', () {
      // m3.material.io/styles/motion/easing-and-duration
      final emphasized = Easing.emphasizedDecelerate as Cubic;
      expect(emphasized.a, 0.05);
      expect(emphasized.b, 0.7);
      expect(emphasized.c, 0.1);
      expect(emphasized.d, 1.0);

      final standard = Easing.standard as Cubic;
      expect(standard.a, 0.2);
      expect(standard.b, 0.0);
      expect(standard.c, 0.0);
      expect(standard.d, 1.0);

      expect(Durations.short1.inMilliseconds, 50);
      expect(Durations.short4.inMilliseconds, 200);
      expect(Durations.medium1.inMilliseconds, 250);
      expect(Durations.medium4.inMilliseconds, 400);
      expect(Durations.long1.inMilliseconds, 450);
      expect(Durations.long4.inMilliseconds, 600);
    });

    test('Md3Motion 别名直接绑定 SDK 官方常量', () {
      expect(Md3Motion.emphasized, Easing.emphasizedDecelerate);
      expect(Md3Motion.standard, Easing.standard);
      expect(Md3Motion.short1, Durations.short1);
      expect(Md3Motion.long1, Durations.long1);
      expect(Md3Motion.transitionEnter, Durations.long1);
      expect(Md3Motion.transitionExit, Durations.medium3);
    });

    test('页面转场使用官方 emphasized 曲线与官方时长', () {
      final route = Md3SharedAxisPageRoute<void>(builder: (_) => const SizedBox());
      expect(route.transitionDuration, Durations.long1);
      expect(route.reverseTransitionDuration, Durations.medium3);
    });
  });

  group('官方 shape / elevation / 断点', () {
    test('M3 shape scale 与 elevation level', () {
      expect(Md3Shape.extraSmall, 4);
      expect(Md3Shape.small, 8);
      expect(Md3Shape.medium, 12);
      expect(Md3Shape.large, 16);
      expect(Md3Shape.extraLarge, 28);
      expect(Md3Elevation.level0, 0);
      expect(Md3Elevation.level2, 3);
      expect(Md3Elevation.level5, 12);
      expect(Md3Dimens.minTouchTarget, 48);
      expect(Md3State.pressed, 0.10);
    });

    testWidgets('window size class 按官方 600/840/1200/1600 断点', (
      tester,
    ) async {
      Future<Md3WindowSizeClass> at(double width) async {
        late Md3WindowSizeClass result;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: Size(width, 800)),
            child: Builder(
              builder: (context) {
                result = md3WindowSizeClassOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        return result;
      }

      expect(await at(399), Md3WindowSizeClass.compact);
      expect(await at(599), Md3WindowSizeClass.compact);
      expect(await at(600), Md3WindowSizeClass.medium);
      expect(await at(839), Md3WindowSizeClass.medium);
      expect(await at(840), Md3WindowSizeClass.expanded);
      expect(await at(1199), Md3WindowSizeClass.expanded);
      expect(await at(1200), Md3WindowSizeClass.large);
      expect(await at(1600), Md3WindowSizeClass.extraLarge);
    });
  });

  group('主导航是官方组件', () {
    testWidgets('ShellDock 渲染 NavigationBar 而非自研玻璃 dock', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.createTheme(Brightness.light),
          home: Scaffold(
            bottomNavigationBar: ShellDock(
              selectedIndex: 0,
              onSelected: (_) {},
              overVideo: false,
              staticMaterial: false,
            ),
          ),
        ),
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.text('首页'), findsOneWidget);
      expect(find.text('短剧'), findsOneWidget);
      expect(find.text('书架'), findsOneWidget);
      expect(find.text('手环'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.height, Md3Dimens.navigationBarHeight);
      expect(
        bar.labelBehavior,
        NavigationDestinationLabelBehavior.alwaysShow,
      );
    });
  });
}
