import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/kosync/kosync_client.dart';

/// 对**真实** kosync 服务端的联调测试。
///
/// 默认跳过：需要一个可用的服务端。用环境变量打开：
///
/// ```sh
/// KOSYNC_LIVE_URL=http://127.0.0.1:17210 flutter test test/kosync_live_server_test.dart
/// ```
///
/// 这类测试的价值在于它跑的是真实 HTTP 栈与真实的服务端实现，Mock 覆盖
/// 不到的地方（状态码、响应体形状、字段命名）只有它能发现。
void main() {
  final baseUrl = Platform.environment['KOSYNC_LIVE_URL'];
  final username = Platform.environment['KOSYNC_LIVE_USER'];
  final password = Platform.environment['KOSYNC_LIVE_PASSWORD'];
  final skip = baseUrl == null || username == null || password == null;

  group('kosync 真实服务端联调', () {
    late KosyncClient client;

    setUp(() {
      client = KosyncClient(
        baseUrl: baseUrl!,
        username: username!,
        // 服务端要求口令是小写十六进制 MD5。
        authKey: _md5(password!),
      );
    });

    tearDown(() => client.close());

    test('注册 → 鉴权 → 推送 → 拉取 全链路', () async {
      // 账号可能已经存在（重复跑测试），两种结果都算通过。
      try {
        await client.createUser();
      } on KosyncException catch (error) {
        expect(error.code, KosyncException.userExists);
      }

      expect(await client.authenticate(), isTrue);

      const document = '59d481d168cca6267322f150c5f6a2a3';
      const progress = 'y1:3:120';
      final stamp = await client.pushProgress(
        document: document,
        progress: progress,
        percentage: 0.42,
        device: 'Yeyu Reader',
        deviceId: 'yeyu-live-test',
      );
      expect(stamp, greaterThan(0));

      final record = await client.fetchProgress(document);
      expect(record, isNotNull);
      expect(record!.document, document);
      expect(record.progress, progress);
      expect(record.percentage, closeTo(0.42, 1e-9));
      expect(record.device, 'Yeyu Reader');
      expect(record.deviceId, 'yeyu-live-test');
      expect(record.timestamp, stamp);
    });

    test('未存过的文档返回 null', () async {
      expect(await client.fetchProgress('deadbeefdeadbeefdeadbeefdeadbeef'), isNull);
    });

    test('错误凭据被拒', () async {
      final wrong = KosyncClient(
        baseUrl: baseUrl!,
        username: username!,
        authKey: _md5('definitely-not-the-password'),
      );
      addTearDown(wrong.close);
      await expectLater(
        wrong.authenticate(),
        throwsA(
          isA<KosyncException>().having(
            (e) => e.code,
            'code',
            KosyncException.unauthorized,
          ),
        ),
      );
    });

    test('不可服务的 document 被服务端拒绝', () async {
      await expectLater(
        client.pushProgress(
          document: 'has-a-hyphen',
          progress: 'p',
          percentage: 0.5,
          device: 'd',
          deviceId: 'i',
        ),
        throwsA(
          isA<KosyncException>().having(
            (e) => e.code,
            'code',
            KosyncException.documentNotServable,
          ),
        ),
      );
    });
  }, skip: skip ? '需要 KOSYNC_LIVE_URL / KOSYNC_LIVE_USER / KOSYNC_LIVE_PASSWORD' : false);
}

/// 口令的小写十六进制 MD5，与服务端和页屿保持同一算法。
String _md5(String value) =>
    md5.convert(utf8.encode(value)).toString();
