import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fqapp/pages/log_viewer_page.dart';
import 'package:fqapp/services/app_log.dart';
import 'package:fqapp/services/app_theme.dart';

/// 日志页墨水屏回归：级别色、搜索框描边与筛选胶囊的选中可区分性。
void main() {
  setUp(() => AppLog.instance.resetForTest());
  tearDown(() => AppLog.instance.resetForTest());

  testWidgets('墨水屏下警告用黑色、搜索框保留可见描边', (tester) async {
    final original = einkModeNotifier.value;
    einkModeNotifier.value = true;
    addTearDown(() => einkModeNotifier.value = original);
    AppLog.w('api', '接口超时');

    await tester.pumpWidget(const MaterialApp(home: LogViewerPage()));
    await tester.pump();

    final badge = tester.widget<Text>(find.text('警告'));
    expect(badge.style?.color, Colors.black, reason: 'e-ink warning is black');
    final field = tester.widget<TextField>(find.byType(TextField));
    final border = field.decoration?.enabledBorder;
    expect(border, isA<OutlineInputBorder>());
    expect(
      (border! as OutlineInputBorder).borderSide.color,
      Colors.black,
      reason: 'white search bar needs an outline on a white canvas',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('墨水屏下筛选弹层的选中与未选中胶囊可区分', (tester) async {
    final original = einkModeNotifier.value;
    einkModeNotifier.value = true;
    addTearDown(() => einkModeNotifier.value = original);

    // 筛选胶囊已是官方 FilterChip，颜色由主题接管：需套用 eink 主题
    // （scheme 全黑白）才能验证灰度下两态可区分。
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.createTheme(Brightness.light, einkMode: true),
        home: const LogViewerPage(),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('筛选日志'));
    await tester.pumpAndSettle();

    final selected = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '全部级别'),
    );
    final unselected = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '调试'),
    );
    expect(selected.selected, isTrue);
    expect(unselected.selected, isFalse);

    // 官方 FilterChip 的对勾与底色由框架绘制，从 chip 的 Material /
    // Ink 上读取最终样式：墨水屏 scheme 全黑白，未选中态靠 1dp 黑描边
    // （outlineVariant），选中态无描边 + 白底（secondaryContainer）。
    Material chipMaterial(String label) => tester.widget<Material>(
      find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
    );
    final selectedShape = chipMaterial('全部级别').shape as RoundedRectangleBorder;
    final unselectedShape = chipMaterial('调试').shape as RoundedRectangleBorder;
    expect(unselectedShape.side.color, Colors.black);
    expect(selectedShape.side.color, Colors.transparent);
    final selectedBg = (tester.widget<Ink>(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('全部级别'),
              matching: find.byType(Material),
            ).first,
            matching: find.byType(Ink),
          )
          .first,
    ).decoration! as ShapeDecoration).color;
    expect(selectedBg, Colors.white);
  });
}
