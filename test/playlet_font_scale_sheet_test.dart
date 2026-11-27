import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fqapp/services/app_theme.dart';
import 'package:fqapp/services/short_series_font_scale.dart';
import 'package:fqapp/widgets/player/playlet_font_scale_sheet.dart';

void main() {
  testWidgets('深色下字号弹层取浮层底与浅色字', (tester) async {
    // 弹层原来固定 #FAFAFA 底 + 黑字：深色主题下从深色播放器弹出来是一块
    // 白板。MD3 迁移后改为官方 showModalBottomSheet(showDragHandle)，
    // 底色取 homeSheetColor（深色=surfaceContainerLow 的 tonal 表面），
    // 文字取 palette.ink（scheme.onSurface）；三档改为官方 FilterChip，
    // 选中态交给 chip 的 selected/onSecondaryContainer 表达。
    ShortSeriesFontScale.instance = 0;
    addTearDown(() => ShortSeriesFontScale.instance = 0);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.createTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlayletFontScaleSheet(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.backgroundColor, const Color(0xFF231918));
    expect(
      tester.widget<Text>(find.text('字体大小')).style?.color,
      const Color(0xFFF1DFDB),
    );
    // 选中档（标准）selected=true，未选中档（大号）selected=false。
    final chips = tester.widgetList<FilterChip>(
      find.byType(FilterChip),
    ).toList();
    expect(chips.length, 3);
    expect(chips[0].selected, isTrue, reason: '默认选中「标准」');
    expect(chips[1].selected, isFalse);
    expect(chips[2].selected, isFalse);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('player-font-scale-preview')))
          .style
          ?.color,
      const Color(0xFFF1DFDB),
    );
    expect(tester.takeException(), isNull);
  });
}
