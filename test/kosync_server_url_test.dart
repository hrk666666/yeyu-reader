import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/kosync/kosync_client.dart';
import 'package:fqapp/services/kosync/kosync_preferences.dart';
import 'package:fqapp/services/kosync/kosync_sync_service.dart';
import 'package:fqapp/services/secure_key_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 服务器地址的容错与连接失败时的提示。
///
/// 真机上最常见的两类「连不上」都不是服务器的问题：地址少写 `https://`，
/// 或者把文档里的 `host:port` 整串抄了进来。这里把两种情况都钉住，避免
/// 以后改回「原样传给 Uri.parse」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    KosyncSyncService.clientFactory = null;
  });

  group('normalizeServerUrl', () {
    test('没有 scheme 时补 https', () {
      expect(
        KosyncPreferences.normalizeServerUrl('sync.example.com'),
        'https://sync.example.com',
      );
    });

    test('保留用户显式写的 http 与端口', () {
      expect(
        KosyncPreferences.normalizeServerUrl('http://192.168.1.10:7200'),
        'http://192.168.1.10:7200',
      );
    });

    test('去掉尾部斜杠', () {
      expect(
        KosyncPreferences.normalizeServerUrl('https://sync.example.com/'),
        'https://sync.example.com',
      );
    });

    test('去掉首尾空白与零宽字符', () {
      expect(
        KosyncPreferences.normalizeServerUrl('  https://sync.example.com\u200B '),
        'https://sync.example.com',
      );
    });

    test('空串回到默认服务器', () {
      expect(
        KosyncPreferences.normalizeServerUrl('   '),
        KosyncPreferences.defaultServerUrl,
      );
    });

    test('不清洗端口：自建服务可能就在非标准端口上', () {
      expect(
        KosyncPreferences.normalizeServerUrl('https://sync.example.com:7200'),
        'https://sync.example.com:7200',
      );
    });
  });

  group('KosyncClient 地址处理', () {
    test('没有 scheme 也能把请求发到正确的 host', () async {
      Uri? seen;
      final client = KosyncClient(
        baseUrl: 'sync.example.com',
        username: 'reader',
        authKey: 'a' * 32,
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode(<String, String>{}), 200);
        }),
      );
      await client.authenticate();
      expect(seen, isNotNull);
      expect(seen!.host, 'sync.example.com');
      expect(seen!.port, 443);
      expect(seen!.path, '/users/auth');
    });

    test('尾部斜杠不会拼出双斜杠', () async {
      Uri? seen;
      final client = KosyncClient(
        baseUrl: 'https://sync.example.com/',
        username: 'reader',
        authKey: 'a' * 32,
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode(<String, String>{}), 200);
        }),
      );
      await client.authenticate();
      expect(seen!.path, '/users/auth');
    });

    test('connectionTarget 反映实际端口', () {
      expect(
        KosyncClient(
          baseUrl: 'https://sync.example.com',
          username: 'u',
          authKey: 'k',
        ).connectionTarget,
        'sync.example.com:443',
      );
      expect(
        KosyncClient(
          baseUrl: 'https://sync.example.com:54902',
          username: 'u',
          authKey: 'k',
        ).connectionTarget,
        'sync.example.com:54902',
      );
    });

    test('端口被拒时提示里带上实际 host:port 并指出端口可疑', () async {
      final client = KosyncClient(
        baseUrl: 'https://sync.example.com:54902',
        username: 'reader',
        authKey: 'a' * 32,
        client: MockClient(
          (request) async => throw http.ClientException(
            'Connection refused',
            request.url,
          ),
        ),
      );
      await expectLater(
        client.authenticate(),
        throwsA(
          isA<KosyncException>()
              .having((e) => e.message, 'message', contains('sync.example.com:54902'))
              .having((e) => e.message, 'message', contains('拒绝连接'))
              .having((e) => e.message, 'message', contains('端口')),
        ),
      );
    });

    test('域名解析失败时提示检查地址拼写', () async {
      final client = KosyncClient(
        baseUrl: 'https://sync.example.com',
        username: 'reader',
        authKey: 'a' * 32,
        client: MockClient(
          (request) async => throw http.ClientException(
            'Failed host lookup: sync.example.com',
            request.url,
          ),
        ),
      );
      await expectLater(
        client.authenticate(),
        throwsA(
          isA<KosyncException>()
              .having((e) => e.message, 'message', contains('无法解析服务器地址')),
        ),
      );
    });
  });

  group('测试连接不要求先启用同步', () {
    Future<KosyncPreferences> credentialsOnly() async {
      final prefs = KosyncPreferences(
        secureStorage: InMemorySecureKeyStorage(),
      );
      await prefs.load();
      await prefs.setServerUrl('sync.example.com');
      await prefs.setUsername('reader');
      await prefs.setPassword('secret');
      return prefs;
    }

    test('未打开开关时仍能向服务器验身份', () async {
      final prefs = await credentialsOnly();
      expect(prefs.isConfigured, isFalse);
      expect(prefs.hasCredentials, isTrue);

      KosyncSyncService.clientFactory = () => KosyncClient(
        baseUrl: prefs.serverUrl.value,
        username: prefs.username.value,
        authKey: prefs.authKey.value,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, String>{'authorized': 'OK'}),
            200,
          ),
        ),
      );

      final service = KosyncSyncService(preferences: prefs);
      expect(await service.verifyCredentials(), isTrue);
    });

    test('未填账号时给出缺字段提示，而不是「同步未启用」', () async {
      final prefs = KosyncPreferences(
        secureStorage: InMemorySecureKeyStorage(),
      );
      await prefs.load();
      await prefs.setServerUrl('sync.example.com');
      final service = KosyncSyncService(preferences: prefs);
      await expectLater(
        service.verifyCredentials(),
        throwsA(
          isA<KosyncException>()
              .having((e) => e.message, 'message', contains('请先填写')),
        ),
      );
    });
  });
}
