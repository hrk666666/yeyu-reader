import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fqapp/theme/md3.dart';
import 'package:fqapp/widgets/wenku/src/easy_glass.dart';
import 'package:fqapp/widgets/wenku/src/glass_morph.dart';

// 官方 MD3 迁移后 EasyGlassSurface 不再是 LiquidGlassLens，而是
// surfaceContainer 底色 + surfaceTint + level1 elevation 的官方 tonal
// elevation Material。测试用固定 seed 的官方 ColorScheme 校验。
final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFEF5038));

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(colorScheme: scheme),
  home: Scaffold(
    body: Center(child: SizedBox(width: 240, height: 160, child: child)),
  ),
);

Finder _surfaceMaterial() => find.descendant(
  of: find.byWidgetPredicate((w) => w is SizedBox && w.width == 240),
  matching: find.byType(Material),
);

Material _material(WidgetTester tester) =>
    tester.widget<Material>(_surfaceMaterial());

double _cornerRadius(Material material) =>
    (material.shape as RoundedRectangleBorder).borderRadius
        .resolve(TextDirection.ltr)
        .topLeft
        .x;

EasyGlassSurface _surface({WenkuGlassMorph? morph, bool physical = true}) =>
    EasyGlassSurface(
      radius: 24,
      thickness: 20,
      blur: 0,
      refractiveIndex: 1.45,
      tint: const Color(0x00000000),
      emission: 0,
      activation: 0,
      physicalOptics: physical,
      morph: morph,
      child: const Text('菜单内容'),
    );

void main() {
  test('resolve interpolates the material from control to overlay', () {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 300),
    );
    addTearDown(controller.dispose);
    final morph = WenkuGlassMorph(
      animation: controller,
      radius: 12,
      thickness: 6,
      blur: 3,
    );

    expect(morph.progress, 0);
    expect(morph.resolve(12, 28), 12);
    expect(morph.resolve(6, 20), 6);
    expect(morph.resolve(3, 12), 3);

    controller.value = 1;
    expect(morph.progress, 1);
    expect(morph.resolve(12, 28), 28);
    expect(morph.resolve(6, 20), 20);
    expect(morph.resolve(3, 12), 12);

    // 官方 M3 emphasized decelerate 曲线。
    controller.value = .5;
    final progress = Easing.emphasizedDecelerate.transform(.5);
    expect(morph.progress, closeTo(progress, 1e-9));
    expect(morph.resolve(12, 28), closeTo(12 + 16 * progress, 1e-9));
    expect(morph.resolve(3, 12), closeTo(3 + 9 * progress, 1e-9));
  });

  testWidgets('preserveOptics keeps menu content above a morphing lens', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _wrap(
        _surface(
          morph: WenkuGlassMorph(
            animation: controller,
            radius: 12,
            thickness: 6,
            blur: 0,
          ),
        ),
      ),
    );

    expect(find.text('菜单内容'), findsOneWidget);
    expect(_surfaceMaterial(), findsOneWidget);
    final material = _material(tester);
    expect(material.color, scheme.surfaceContainer);
    expect(material.surfaceTintColor, scheme.surfaceTint);
    expect(material.shadowColor, Colors.transparent);
    expect(material.elevation, Md3Elevation.level1);
    expect(_cornerRadius(material), 24);
  });

  testWidgets('the lens follows the morph clock each frame', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 300),
    );
    addTearDown(controller.dispose);
    // EasyGlassSurface 在 build 时求值，由调用方逐帧 rebuild 驱动。
    final morph = WenkuGlassMorph(
      animation: controller,
      radius: 12,
      thickness: 6,
      blur: 6,
    );
    await tester.pumpWidget(_wrap(_surface(morph: morph)));

    controller.value = .5;
    await tester.pumpWidget(_wrap(_surface(morph: morph)));
    final progress = Easing.emphasizedDecelerate.transform(.5);
    expect(
      _cornerRadius(_material(tester)),
      closeTo(12 + 12 * progress, 1e-9),
    );

    controller.value = 1;
    await tester.pumpWidget(_wrap(_surface(morph: morph)));
    expect(_cornerRadius(_material(tester)), 24);
  });

  testWidgets('a null morph keeps the previous static material', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_surface()));
    expect(find.text('菜单内容'), findsOneWidget);
    final material = _material(tester);
    expect(_cornerRadius(material), 24);
    expect(material.color, scheme.surfaceContainer);
  });

  testWidgets('non-physical optics still show the menu content', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_surface(physical: false)));
    expect(find.text('菜单内容'), findsOneWidget);
    expect(_surfaceMaterial(), findsOneWidget);
  });
}
