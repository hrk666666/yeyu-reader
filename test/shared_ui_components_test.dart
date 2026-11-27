import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fqapp/services/app_theme.dart';
import 'package:fqapp/theme/md3.dart';
import 'package:fqapp/widgets/home/home_back_button.dart';
import 'package:fqapp/widgets/home/home_chip.dart';
import 'package:fqapp/widgets/home/home_design.dart';
import 'package:fqapp/widgets/home/home_feed_states.dart';
import 'package:fqapp/widgets/home/home_sheet.dart';
import 'package:fqapp/widgets/home/home_stream_footer.dart';
import 'package:fqapp/widgets/settings/settings_widgets.dart';
import 'package:fqapp/widgets/shelf/shelf_design.dart';

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.createTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    einkModeNotifier.value = false;
    themeModeNotifier.value = ThemeMode.system;
  });

  test('全局画布与 HomePalette.canvas 对齐，AppBar 不再另起一色', () {
    void expectsAligned(
      ThemeData theme,
      HomePalette palette, {
      bool eink = false,
    }) {
      expect(theme.scaffoldBackgroundColor, palette.canvas);
      expect(theme.canvasColor, palette.canvas);
      expect(theme.appBarTheme.backgroundColor, palette.canvas);
      expect(theme.appBarTheme.elevation, 0);
      // 官方 M3 top app bar 滚动后施加 level2 tonal elevation 与 surfaceTint；
      // 墨水屏是显式的无特效可访问性变体，两者都关掉。
      expect(
        theme.appBarTheme.scrolledUnderElevation,
        eink ? 0 : Md3Elevation.level2,
      );
      expect(
        theme.appBarTheme.surfaceTintColor,
        eink ? Colors.transparent : theme.colorScheme.surfaceTint,
      );
    }

    expectsAligned(
      AppTheme.createTheme(Brightness.light),
      const HomePalette(false),
    );
    expectsAligned(
      AppTheme.createTheme(Brightness.dark),
      const HomePalette(true),
    );
    expectsAligned(
      AppTheme.createTheme(Brightness.dark, oledMode: true),
      const HomePalette(true, oled: true),
    );
    expectsAligned(
      AppTheme.createTheme(Brightness.light, einkMode: true),
      const HomePalette(false, eink: true),
      eink: true,
    );
    // 官方 MD3：画布色取自 ColorScheme.fromSeed 的 surface role。
    expect(
      AppTheme.createTheme(Brightness.light).scaffoldBackgroundColor,
      AppTheme.md3Scheme(Brightness.light).surface,
    );
  });

  testWidgets('浅色 HomeChip 选中 secondaryContainer 实心、未选中 surface 描边', (tester) async {
    await tester.pumpWidget(
      _app(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HomeChip(
              key: const Key('chip-light-selected'),
              label: '已选',
              selected: true,
              onTap: () {},
            ),
            HomeChip(
              key: const Key('chip-light-plain'),
              label: '未选',
              selected: false,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    final scheme = AppTheme.md3Scheme(Brightness.light);
    ChoiceChip chip(String key) => tester.widget<ChoiceChip>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(ChoiceChip),
      ),
    );
    // 官方 ChoiceChip：选中 secondaryContainer 实心、无描边。
    final selected = chip('chip-light-selected');
    expect(selected.selectedColor, scheme.secondaryContainer);
    expect(selected.side, BorderSide.none);
    // 未选中 surfaceContainerLow 底 + outlineVariant 描边，M3 small 圆角。
    final plain = chip('chip-light-plain');
    expect(plain.backgroundColor, scheme.surfaceContainerLow);
    expect(plain.side!.color, scheme.outlineVariant);
    expect(
      (plain.shape as RoundedRectangleBorder).borderRadius,
      Md3Shape.smallRadius,
    );
    expect(
      tester.widget<Text>(find.text('已选')).style!.color,
      scheme.onSecondaryContainer,
    );
    expect(
      tester.widget<Text>(find.text('未选')).style!.color,
      const HomePalette(false).muted,
    );
  });

  testWidgets('墨水屏下 HomeChip 选中黑底白字、未选中白底黑字并描边', (tester) async {
    einkModeNotifier.value = true;
    final theme = AppTheme.createTheme(Brightness.light, einkMode: true);
    await tester.pumpWidget(
      _app(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HomeChip(
              key: const Key('chip-eink-selected'),
              label: '已选',
              selected: true,
              onTap: () {},
            ),
            HomeChip(
              key: const Key('chip-eink-plain'),
              label: '未选',
              selected: false,
              onTap: () {},
            ),
          ],
        ),
        theme: theme,
      ),
    );

    ChoiceChip chip(String key) => tester.widget<ChoiceChip>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(ChoiceChip),
      ),
    );
    // 墨水屏是显式黑白可访问性变体：黑底白字 / 白底黑字。
    final selected = chip('chip-eink-selected');
    final plain = chip('chip-eink-plain');
    expect(selected.selectedColor, Colors.black);
    expect(selected.side, BorderSide.none);
    expect(plain.backgroundColor, Colors.white);
    final plainSide = plain.side!;
    expect(plainSide.color, Colors.black);
    expect(plainSide.width, 1);
    // 官方 ChoiceChip 形状：M3 small 圆角（不再是自研胶囊）。
    for (final c in [selected, plain]) {
      expect(
        (c.shape as RoundedRectangleBorder).borderRadius,
        Md3Shape.smallRadius,
      );
    }
    expect(tester.widget<Text>(find.text('已选')).style!.color, Colors.white);
    expect(tester.widget<Text>(find.text('未选')).style!.color, Colors.black);
    for (final key in ['chip-eink-selected', 'chip-eink-plain']) {
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(HomeChip.minTapTarget),
      );
    }
  });

  testWidgets('墨水屏下 SettingsSwitch 纯黑白且两种状态可区分', (tester) async {
    einkModeNotifier.value = true;
    final theme = AppTheme.createTheme(Brightness.light, einkMode: true);
    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsSwitch(
              key: const Key('switch-on'),
              value: true,
              onChanged: (_) {},
            ),
            SettingsSwitch(
              key: const Key('switch-off'),
              value: false,
              onChanged: (_) {},
            ),
          ],
        ),
        theme: theme,
      ),
    );
    Switch switchOf(String key) => tester.widget<Switch>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Switch)),
    );

    final on = switchOf('switch-on');
    // 新实现是官方 Switch，颜色全部交给主题（eink scheme 已退化为纯黑白）。
    expect(on.thumbColor, isNull);
    expect(on.trackColor, isNull);
    expect(on.trackOutlineColor, isNull);
    // M3 规范：选中轨道 primary / 滑块 onPrimary —— 黑底白滑块。
    final scheme = theme.colorScheme;
    expect(scheme.primary, Colors.black);
    expect(scheme.onPrimary, Colors.white);
    expect(scheme.secondaryContainer, Colors.white);

    final off = switchOf('switch-off');
    expect(off.thumbColor, isNull);
    expect(off.trackColor, isNull);
    // 未选中轨道 surfaceContainerHighest / 滑块与描边 outline —— 白底黑滑块。
    expect(scheme.surfaceContainerHighest, Colors.white);
    expect(scheme.outline, Colors.black);
  });

  testWidgets('流尾三态用 muted 文字色，重试可点高度不小于 44', (tester) async {
    var retried = 0;
    const palette = HomePalette(false);
    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HomeStreamFooter.loading(key: Key('footer-loading')),
            const HomeStreamFooter.done(key: Key('footer-done')),
            HomeStreamFooter.retry(
              key: const Key('footer-retry'),
              onRetry: () => retried++,
            ),
          ],
        ),
      ),
    );
    for (final key in ['footer-loading', 'footer-done']) {
      final text = tester.widget<Text>(
        find
            .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
            .first,
      );
      expect(text.style!.color, palette.muted);
    }
    expect(
      tester.widget<Text>(find.text('加载失败，点击重试')).style!.color,
      palette.muted,
    );
    final hit = find.descendant(
      of: find.byKey(const Key('footer-retry')),
      matching: find.byType(GestureDetector),
    );
    expect(tester.getSize(hit).height, greaterThanOrEqualTo(44));
    await tester.tap(find.text('加载失败，点击重试'));
    expect(retried, 1);
  });

  testWidgets('showHomeSheet 使用 homeSheetColor 与统一圆角', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.createTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showHomeSheet<void>(
                  context: context,
                  title: '选择一项',
                  children: const [Text('内容')],
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.backgroundColor, homeSheetColor(const HomePalette(true)));
    final shape = sheet.shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      const BorderRadius.vertical(top: Radius.circular(HomeSheetFrame.radius)),
    );
    expect(find.text('选择一项'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('内容'), findsNothing);
  });

  testWidgets('SettingsGroupCard 单一圆角 + surface/line 描边', (tester) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 360,
          child: SettingsGroupCard(
            children: [
              const SettingsRow(title: '第一项'),
              const SettingsRow(title: '第二项'),
            ],
          ),
        ),
      ),
    );
    final palette = HomePalette(false);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(SettingsGroupCard),
            matching: find.byType(Material),
          )
          .first,
    );
    // M3 filled 卡片：surfaceContainerLow 底、无描边、medium 圆角。
    expect(material.color, palette.surface);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.side, BorderSide.none);
    expect(shape.borderRadius, Md3Shape.mediumRadius);
    final divider = tester.widget<Divider>(find.byType(Divider));
    expect(divider.indent, SettingsGroupCard.dividerIndent);
    expect(divider.color, palette.line);
  });

  testWidgets('深色下设置卡片与行跟随 surface / ink', (tester) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 360,
          child: SettingsGroupCard(children: const [SettingsRow(title: '深色行')]),
        ),
        theme: AppTheme.createTheme(Brightness.dark),
      ),
    );
    const palette = HomePalette(true);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(SettingsGroupCard),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, palette.surface);
    // M3 filled 卡片：深色下同样无描边，靠 surface 层级区分。
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.side, BorderSide.none);
    expect(tester.widget<Text>(find.text('深色行')).style!.color, palette.ink);
  });

  testWidgets('SettingsRow 无副标题至少 52、有副标题至少 64', (tester) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 360,
          child: SettingsGroupCard(
            children: [
              const SettingsRow(key: Key('row-plain'), title: '仅标题'),
              const SettingsRow(
                key: Key('row-sub'),
                title: '带副标题',
                subtitle: '说明文字',
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('row-plain'))).height,
      greaterThanOrEqualTo(SettingsRow.minHeight),
    );
    expect(
      tester.getSize(find.byKey(const Key('row-sub'))).height,
      greaterThanOrEqualTo(SettingsRow.minHeightWithSubtitle),
    );
    expect(tester.widget<Text>(find.text('仅标题')).style!.fontSize, 16);
    final subtitle = tester.widget<Text>(find.text('说明文字'));
    expect(subtitle.style!.fontSize, 14);
    expect(subtitle.style!.color, const HomePalette(false).muted);
  });

  testWidgets('SettingsScaffold 画布与 AppBar 同色且无 elevation', (tester) async {
    final theme = AppTheme.createTheme(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(theme: theme, home: const SettingsScaffold(title: '设置', body: Text('内容'))),
    );
    final scheme = AppTheme.md3Scheme(Brightness.light);
    // MD3：画布取 ColorScheme surface，AppBar 由 appBarTheme 跟随同一 role。
    expect(theme.scaffoldBackgroundColor, scheme.surface);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, isNull);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, isNull);
    expect(theme.appBarTheme.elevation, 0);
    expect(theme.appBarTheme.scrolledUnderElevation, Md3Elevation.level2);
    expect(theme.appBarTheme.surfaceTintColor, scheme.surfaceTint);
    expect(find.byTooltip('返回'), findsOneWidget);
  });

  testWidgets('HomeBackButton 使用 Material chevron_left 且 tooltip 为返回', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const HomeBackButton()));
    expect(find.byTooltip('返回'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.chevron_left));
    expect(icon.size, 20);
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.tooltip, '返回');
  });

  testWidgets('HomeStateView 紧凑态显示图标砖、标题、说明与动作', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _app(
        HomeStateView(
          icon: LucideIcons.cloud_off,
          title: '没有更多',
          message: '换个分类试试',
          actionLabel: '重试',
          onAction: () => tapped++,
        ),
      ),
    );
    expect(find.byIcon(LucideIcons.cloud_off), findsOneWidget);
    expect(find.text('没有更多'), findsOneWidget);
    expect(find.text('换个分类试试'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(TextButton, '重试')).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.text('重试'));
    expect(tapped, 1);
  });

  testWidgets('showSettingsConfirmDialog 破坏性确认使用书架删除红', (tester) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  confirmed = await showSettingsConfirmDialog(
                    context: context,
                    title: '删除',
                    message: '无法撤销',
                    confirmLabel: '删除',
                    destructive: true,
                  );
                },
                child: const Text('执行'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('执行'));
    await tester.pumpAndSettle();
    expect(find.text('无法撤销'), findsOneWidget);
    final confirmButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '删除'),
    );
    expect(
      confirmButton.style!.foregroundColor!.resolve(const {}),
      ShelfTokens.deleteRed,
    );
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('墨水屏破坏性确认键为黑字黑描边，与白色对话框可区分', (tester) async {
    einkModeNotifier.value = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.createTheme(Brightness.light, einkMode: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showSettingsConfirmDialog(
                  context: context,
                  title: '删除',
                  confirmLabel: '删除',
                  destructive: true,
                ),
                child: const Text('执行'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('执行'));
    await tester.pumpAndSettle();

    final confirmButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '删除'),
    );
    final scheme = Theme.of(
      tester.element(find.byType(AlertDialog)),
    ).colorScheme;
    final style = confirmButton.style!;
    // 破坏红不进入墨屏主题：eink scheme.error 退化为纯黑前景。
    expect(style.foregroundColor!.resolve(const {}), scheme.error);
    expect(scheme.error, Colors.black);
    // tonal 容器与对话框底都跟随 scheme：eink 下均为白色。
    expect(scheme.secondaryContainer, Colors.white);
    expect(scheme.surfaceContainerHigh, Colors.white);
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
      scheme.surfaceContainerHigh,
    );
  });
}
