import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/pages/reader_page.dart';
import 'package:fqapp/services/kosync/kosync_client.dart';
import 'package:fqapp/services/kosync/kosync_preferences.dart';
import 'package:fqapp/services/kosync/kosync_sync_service.dart';
import 'package:fqapp/services/secure_key_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// 阅读器与 kosync 的接线测试。
///
/// 验证的是「阅读器确实把进度发出去了、也确实会把远端进度接回来」这两条
/// 接线，而不是协议的细节（协议细节在 kosync_client_test 里逐条断言）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;

  Future<void> installSync({
    required bool enabled,
    String remoteProgress = '',
    double remotePercentage = 0,
    int remoteTimestamp = 0,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 必须先给安全存储换掉再碰 instance：单例在首次访问时就构造好了。
    KosyncPreferences.testStorage = InMemorySecureKeyStorage();
    final prefs = KosyncPreferences.instance;
    // 每个用例都从干净状态开始：上一个用例留下的值会混进来。
    prefs.resetForTest();
    requests = <http.Request>[];
    // 上一��用例可能已经在全局单例里缓存了客户端，必须丢掉，否则复用的
    // 还是上一次的传输层。
    KosyncSyncService.instance.invalidate();
    KosyncSyncService.clientFactory = () => KosyncClient(
      baseUrl: 'https://sync.example.com',
      username: 'reader',
      authKey: 'a' * 32,
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path.startsWith('/syncs/progress/')) {
          if (remoteProgress.isEmpty) return http.Response('{}', 200);
          return http.Response(
            jsonEncode({
              'progress': remoteProgress,
              'percentage': remotePercentage,
              'device': 'Other',
              'document': 'doc',
              'device_id': 'other',
              'timestamp': remoteTimestamp,
            }),
            200,
          );
        }
        return http.Response('{"document":"doc","timestamp":1700000000}', 200);
      }),
    );
    await prefs.load();
    await prefs.setEnabled(enabled);
    await prefs.setServerUrl('https://sync.example.com');
    await prefs.setUsername('reader');
    await prefs.setPassword('secret');
  }

  tearDown(() {
    KosyncSyncService.clientFactory = null;
    KosyncPreferences.testStorage = null;
  });

  Future<MemoryReaderStore> mountReader(
    WidgetTester tester, {
    required String bookId,
    int chapterCount = 3,
  }) async {
    final store = MemoryReaderStore();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          bookId: bookId,
          title: '同步测试',
          chapters: [
            for (var i = 0; i < chapterCount; i++)
              Chapter(itemId: 'ch$i', title: '第 $i 章', volumeName: ''),
          ],
          startIndex: 0,
          readerStore: store,
          chapterCache: MemoryChapterCache(),
          chapterLoader: (_) async => '这是用于验证同步接线的正文内容。',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return store;
  }

  group('阅读器与进度同步的接线', () {
    testWidgets('未开启同步时不发出任何请求', (tester) async {
      await installSync(enabled: false);
      await mountReader(tester, bookId: 'book-off');
      await tester.pump(const Duration(milliseconds: 300));

      expect(requests, isEmpty);
    });

    testWidgets('开启同步后阅读器把进度推给服务器', (tester) async {
      await installSync(enabled: true);
      await mountReader(tester, bookId: 'book-on');
      await tester.pump(const Duration(milliseconds: 500));

      final pushes = requests
          .where((r) => r.method == 'PUT' && r.url.path == '/syncs/progress')
          .toList();
      expect(pushes, isNotEmpty);

      final body = jsonDecode(pushes.last.body) as Map<String, dynamic>;
      expect(body['document'], isNotEmpty);
      expect(body['progress'], startsWith('y1:'));
      expect(body['percentage'], isA<num>());
      expect(body['device_id'], isNotEmpty);
    });

    testWidgets('远端进度更新时把阅读位置带到对应章节', (tester) async {
      // 远端记录在第 2 章、时间戳远晚于本地。
      await installSync(
        enabled: true,
        remoteProgress: 'y1:2:0',
        remotePercentage: 0.66,
        // 远端比现在新一分钟：属于「远端更新」。
        remoteTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60,
      );
      final store = await mountReader(tester, bookId: 'book-remote');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // 阅读器保存的进度落在远端指定的那一章。
      expect(store.entry?['chapterId'], 'ch2');
      expect(store.entry?['episode'], 2);
    });

    testWidgets('远端进度比本地旧时不改动当前阅读位置', (tester) async {
      // 时间戳在 2000 年，远早于本地刚写下的时间。
      await installSync(
        enabled: true,
        remoteProgress: 'y1:2:0',
        remotePercentage: 0.66,
        // 远端是很久以前的记录：不许把用户拽回去。
        remoteTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400,
      );
      final store = await mountReader(tester, bookId: 'book-stale');
      await tester.pump(const Duration(milliseconds: 600));

      expect(store.entry?['chapterId'], 'ch0');
      expect(store.entry?['episode'], 0);
    });
  });
}
