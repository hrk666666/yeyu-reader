import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/pages/about_page.dart';
import 'package:fqapp/services/app_theme.dart';
import 'package:fqapp/theme/md3.dart';
import 'package:fqapp/widgets/settings/settings_widgets.dart';
import 'package:fqapp/widgets/wenku/wenku_ui.dart';

/// 关于页改版后的结构与交互：全部信息行齐备、版本行点按复制、开源许可
/// 打开框架许可页。
void main() {
  Future<void> pumpAbout(WidgetTester tester) async {
    // 页面内容高于默认 800x600 视口，ListView 外的行不会被构建；
    // 拉高测试视口让整页一次排完，断言才能覆盖每一行。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.createTheme(Brightness.light),
        home: const AboutPage(),
      ),
    );
    await tester.pump();
  }

  testWidgets('关于页渲染出介绍与全部信息行', (tester) async {
    await pumpAbout(tester);

    expect(find.text('页屿'), findsOneWidget);
    expect(find.text('小说 / 短剧 / 漫剧 / 漫画 / 听书聚合客户端'), findsOneWidget);
    // 介绍是一段正文，不再是「项目介绍」标题行。
    expect(find.textContaining('所有签名与解密都在你的手机本地完成'), findsOneWidget);
    expect(find.text('项目介绍'), findsNothing);

    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text(AboutPage.versionText), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('检查新版本与公告（经 update.json）'), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.text('GPL-3.0 与第三方组件许可'), findsOneWidget);
    expect(find.text('Source Code'), findsNothing);
    expect(find.text('源代码'), findsOneWidget);
    expect(find.text('问题反馈'), findsOneWidget);
    // 信息行已是官方 MD3 ListTile（leading icon + 标题/副标题 + 右箭头）。
    final panel = find.byType(ContentPanel);
    expect(panel, findsOneWidget);
    expect(find.byType(SettingsRow), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(6));
    // Six rows, five of them tappable. ContentPanel owns one InkWell of its
    // own and every ListTile owns one too, so the panel subtree has seven.
    expect(
      find.descendant(of: panel, matching: find.byType(InkWell)),
      findsNWidgets(7),
    );
    const infoRows = ['当前版本', '作者', '检查更新', '开源许可', '源代码', '问题反馈'];
    var previousTop = double.negativeInfinity;
    for (final title in infoRows) {
      final row = find.descendant(of: panel, matching: find.text(title));
      expect(row, findsOneWidget);
      final top = tester.getTopLeft(row).dy;
      expect(top, greaterThan(previousTop), reason: '$title 的行顺序');
      previousTop = top;
    }

    expect(find.text('作者'), findsOneWidget);
    expect(find.text('hrk_'), findsOneWidget);
    expect(find.text('开发说明'), findsOneWidget);
    expect(find.textContaining('二次开发：hrk_'), findsOneWidget);
    expect(find.textContaining('仅限个人学习研究使用'), findsOneWidget);
  });

  testWidgets('点当前版本行复制版本号并提示', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpAbout(tester);
    await tester.tap(find.text('当前版本'));
    await tester.pump();

    expect(copied, AboutPage.versionText);
    expect(find.text('已复制版本号'), findsOneWidget);
  });

  testWidgets('点开源许可打开许可页', (tester) async {
    await pumpAbout(tester);
    await tester.tap(find.text('开源许可'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LicensePage), findsOneWidget);
    // 许可页要等 LicenseRegistry 的真实异步结果，FakeAsync 推不动，
    // 用 runAsync 给它真实时间，页眉的应用名随后出现。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
    expect(find.text('页屿'), findsWidgets);
  });

  testWidgets('墨水屏下 logo 不投彩色阴影，浅色仍保留', (tester) async {
    final original = einkModeNotifier.value;
    addTearDown(() => einkModeNotifier.value = original);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.reset);

    Future<BoxDecoration> logoDecoration() async {
      final eink = einkModeNotifier.value;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.createTheme(Brightness.light, einkMode: eink),
          // 用 key 强制换一棵新树：同一页面在两种主题间切换时，const 子树
          // 可能复用旧 element，测不到重建后的配色。
          home: AboutPage(key: ValueKey('about-$eink')),
        ),
      );
      await tester.pump();
      final plate = tester.widget<Container>(
        find.byKey(const ValueKey('about-logo-plate')),
      );
      return plate.decoration! as BoxDecoration;
    }

    einkModeNotifier.value = true;
    final einkDecoration = await logoDecoration();
    // M3 迁移后 logo 不再画任何 BoxShadow（彩色投影删除，层次交给主题），
    // 墨水屏与浅色一致；圆角是官方 medium shape。
    expect(einkDecoration.boxShadow, isNull);
    expect(einkDecoration.borderRadius, Md3Shape.mediumRadius);

    einkModeNotifier.value = false;
    final lightDecoration = await logoDecoration();
    expect(lightDecoration.boxShadow, isNull);
    expect(lightDecoration.borderRadius, Md3Shape.mediumRadius);
  });
}
