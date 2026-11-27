import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/imported_book_store.dart';
import 'package:fqapp/services/kosync/kosync_client.dart';
import 'package:fqapp/services/kosync/kosync_preferences.dart';
import 'package:fqapp/services/kosync/kosync_sync_service.dart';
import 'package:fqapp/services/secure_key_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookText = '第一章 正文内容。\n第二段。\n'
      '第二章 正文内容。\n第二段。\n'
      '第三章 正文内容。\n第二段。\n';

  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = await Directory.systemTemp.createTemp('kosync_service');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<KosyncPreferences> buildPreferences() async {
    final prefs = KosyncPreferences(
      secureStorage: InMemorySecureKeyStorage(),
    );
    await prefs.load();
    await prefs.setEnabled(true);
    await prefs.setServerUrl('https://sync.example.com');
    await prefs.setUsername('reader');
    await prefs.setPassword('secret');
    return prefs;
  }

  group('KosyncSyncService 书籍标识', () {
    test('网络小说的标识稳定且是 32 位十六进制', () async {
      final prefs = await buildPreferences();
      final service = KosyncSyncService(
        preferences: prefs,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );

      final first = await service.documentIdFor('123456789');
      final second = await service.documentIdFor('123456789');

      expect(first, second);
      expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
      // 服务端只接受 [A-Za-z0-9_]。
      expect(KosyncClient.isServableDocument(first), isTrue);
    });

    test('不同的书得到不同的标识', () async {
      final prefs = await buildPreferences();
      final service = KosyncSyncService(
        preferences: prefs,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );

      expect(
        await service.documentIdFor('111'),
        isNot(await service.documentIdFor('222')),
      );
    });

    test('本地书在不同设备上算出同一个标识', () async {
      final prefs = await buildPreferences();

      // 「设备一」导入这本书。
      final deviceOne = ImportedBookStore(
        rootDirectoryProvider: () async => root,
      );
      final book = await deviceOne.importBytes(
        fileName: 'sample.txt',
        bytes: Uint8List.fromList(utf8.encode(bookText)),
        decodedText: bookText,
        sourceByteLength: utf8.encode(bookText).length,
      );

      // 「设备二」上，同一本书已经导入过了（目录里已有同一份内容）。
      final deviceTwo = ImportedBookStore(
        rootDirectoryProvider: () async => root,
      );

      final serviceOne = KosyncSyncService(
        preferences: prefs,
        bookStore: deviceOne,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      final serviceTwo = KosyncSyncService(
        preferences: prefs,
        bookStore: deviceTwo,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );

      final idOne = await serviceOne.documentIdFor(book.id);
      final idTwo = await serviceTwo.documentIdFor(book.id);

      expect(idOne, idTwo);
      expect(idOne, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('本地书的标识与网络书的标识不同', () async {
      final prefs = await buildPreferences();
      final store = ImportedBookStore(rootDirectoryProvider: () async => root);
      final book = await store.importBytes(
        fileName: 'sample.txt',
        bytes: Uint8List.fromList(utf8.encode(bookText)),
        decodedText: bookText,
        sourceByteLength: utf8.encode(bookText).length,
      );
      final service = KosyncSyncService(
        preferences: prefs,
        bookStore: store,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );

      expect(
        await service.documentIdFor(book.id),
        isNot(await service.documentIdFor('123456789')),
      );
    });
  });

  group('KosyncSyncService 推送', () {
    test('推送带上了章节、字符偏移与全书进度', () async {
      final prefs = await buildPreferences();
      final sent = <Map<String, dynamic>>[];
      final mock = MockClient((request) async {
        sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"document":"d","timestamp":1700000000}', 200);
      });
      addTearDown(mock.close);
      final service = KosyncSyncService(
        preferences: prefs,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: mock,
        ),
      );

      final ok = await service.pushProgress(
        bookId: '123456789',
        chapterIndex: 7,
        textOffset: 4321,
        percentage: 0.35,
      );

      expect(ok, isTrue);
      expect(sent, hasLength(1));
      expect(sent.single['progress'], 'y1:7:4321');
      expect(sent.single['percentage'], 0.35);
      expect(sent.single['device_id'], isNotEmpty);
    });

    test('短时间内的重复推送被节流', () async {
      final prefs = await buildPreferences();
      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        return http.Response('{"document":"d","timestamp":1}', 200);
      });
      addTearDown(mock.close);
      final service = KosyncSyncService(
        preferences: prefs,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: mock,
        ),
      );

      await service.pushProgress(
        bookId: '123456789',
        chapterIndex: 1,
        textOffset: 0,
        percentage: 0.1,
      );
      final second = await service.pushProgress(
        bookId: '123456789',
        chapterIndex: 1,
        textOffset: 10,
        percentage: 0.2,
      );

      expect(second, isFalse);
      expect(calls, 1);
    });

    test('force 会绕过节流', () async {
      final prefs = await buildPreferences();
      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        return http.Response('{"document":"d","timestamp":1}', 200);
      });
      addTearDown(mock.close);
      final service = KosyncSyncService(
        preferences: prefs,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: mock,
        ),
      );

      await service.pushProgress(
        bookId: '123456789',
        chapterIndex: 1,
        textOffset: 0,
        percentage: 0.1,
      );
      await service.pushProgress(
        bookId: '123456789',
        chapterIndex: 2,
        textOffset: 0,
        percentage: 0.2,
        force: true,
      );

      expect(calls, 2);
    });

    test('服务器出错时不抛出，交给下一次重试', () async {
      final prefs = await buildPreferences();
      final mock = MockClient(
        (_) async => http.Response('{"code":2001,"message":"Unauthorized"}', 401),
      );
      addTearDown(mock.close);
      final service = KosyncSyncService(
        preferences: prefs,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: mock,
        ),
      );

      final ok = await service.pushProgress(
        bookId: '123456789',
        chapterIndex: 1,
        textOffset: 0,
        percentage: 0.1,
      );

      expect(ok, isFalse);
    });

    test('没有配置时不发请求', () async {
      final prefs = KosyncPreferences(secureStorage: InMemorySecureKeyStorage());
      await prefs.load();
      var called = false;
      final mock = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      addTearDown(mock.close);
      final service = KosyncSyncService(
        preferences: prefs,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: mock,
        ),
      );

      final ok = await service.pushProgress(
        bookId: '123456789',
        chapterIndex: 1,
        textOffset: 0,
        percentage: 0.1,
      );

      expect(ok, isFalse);
      expect(called, isFalse);
    });
  });

  group('KosyncSyncService 拉取', () {
    test('拉回远端进度并解析出目标位置', () async {
      final prefs = await buildPreferences();
      final mock = MockClient(
        (_) async => http.Response(
          '{"progress":"y1:5:1200","percentage":0.5,"device":"Other",'
          '"document":"d","device_id":"other","timestamp":1700000000}',
          200,
        ),
      );
      addTearDown(mock.close);
      final service = KosyncSyncService(
        preferences: prefs,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: mock,
        ),
      );

      final remote = await service.pullProgress(
        '123456789',
        chapterCount: 10,
      );

      expect(remote, isNotNull);
      expect(remote!.position.exact, isTrue);
      expect(remote.position.chapterIndex, 5);
      expect(remote.position.textOffset, 1200);
      expect(remote.timestamp, 1700000000);
    });

    test('服务端没有记录时返回 null', () async {
      final prefs = await buildPreferences();
      final mock = MockClient((_) async => http.Response('{}', 200));
      addTearDown(mock.close);
      final service = KosyncSyncService(
        preferences: prefs,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: mock,
        ),
      );

      expect(await service.pullProgress('123456789', chapterCount: 10), isNull);
    });

    test('服务器不可用时返回 null 而不是抛错', () async {
      final prefs = await buildPreferences();
      final mock = MockClient(
        (_) async => http.Response('{"code":2001,"message":"Unauthorized"}', 401),
      );
      addTearDown(mock.close);
      final service = KosyncSyncService(
        preferences: prefs,
        client: KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'reader',
          authKey: prefs.authKey.value,
          client: mock,
        ),
      );

      expect(await service.pullProgress('123456789', chapterCount: 10), isNull);
    });
  });

  group('KosyncPreferences 口令处理', () {
    test('只保存 MD5，不保存明文', () async {
      final storage = InMemorySecureKeyStorage();
      final prefs = KosyncPreferences(secureStorage: storage);
      await prefs.load();
      await prefs.setPassword('明文口令');

      expect(prefs.authKey.value, kosyncAuthKey('明文口令'));
      expect(prefs.authKey.value, isNot('明文口令'));
      expect(prefs.authKey.value, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(
        await storage.read(KosyncPreferences.secureKeyName),
        kosyncAuthKey('明文口令'),
      );
    });

    test('配置齐全才算可用', () async {
      final prefs = KosyncPreferences(secureStorage: InMemorySecureKeyStorage());
      await prefs.load();
      expect(prefs.isConfigured, isFalse);

      await prefs.setEnabled(true);
      await prefs.setUsername('reader');
      expect(prefs.isConfigured, isFalse);

      await prefs.setPassword('pw');
      expect(prefs.isConfigured, isTrue);
    });

    test('清除配置会连口令一起清掉', () async {
      final storage = InMemorySecureKeyStorage();
      final prefs = KosyncPreferences(secureStorage: storage);
      await prefs.load();
      await prefs.setEnabled(true);
      await prefs.setUsername('reader');
      await prefs.setPassword('pw');

      await prefs.clear();

      expect(prefs.isConfigured, isFalse);
      expect(await storage.read(KosyncPreferences.secureKeyName), '');
    });
  });
}
