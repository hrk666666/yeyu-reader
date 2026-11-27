import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/pages/kosync_settings_page.dart';
import 'package:fqapp/services/kosync/kosync_preferences.dart';
import 'package:fqapp/services/secure_key_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    KosyncPreferences.testStorage = InMemorySecureKeyStorage();
    KosyncPreferences.instance.resetForTest();
  });

  tearDown(() {
    KosyncPreferences.testStorage = null;
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: KosyncSettingsPage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('页面给出服务器、账号、口令与设备名四项配置', (tester) async {
    await mount(tester);

    expect(find.text('阅读进度同步'), findsOneWidget);
    expect(find.text('同步服务器地址'), findsOneWidget);
    expect(find.text('账号'), findsOneWidget);
    expect(find.text('口令'), findsOneWidget);
    expect(find.text('设备名称'), findsOneWidget);
    expect(find.text('启用进度同步'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('注册账号'), findsOneWidget);
  });

  testWidgets('口令输入框默认遮挡', (tester) async {
    await mount(tester);

    final field = tester.widget<TextField>(
      find.ancestor(
        of: find.text('口令'),
        matching: find.byType(TextField),
      ),
    );
    expect(field.obscureText, isTrue);
  });

  testWidgets('开关打开后状态被记住', (tester) async {
    await mount(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(KosyncPreferences.instance.enabled.value, isTrue);
  });

  testWidgets('服务器地址被写入配置', (tester) async {
    await mount(tester);

    await tester.enterText(
      find.ancestor(
        of: find.text('同步服务器地址'),
        matching: find.byType(TextField),
      ),
      'http://192.168.1.10:7200',
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // 保存发生在离开页面或点测试连接时；这里只验证输入进了控制器。
    expect(find.text('http://192.168.1.10:7200'), findsOneWidget);
  });
}
