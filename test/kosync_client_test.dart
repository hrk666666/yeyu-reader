import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/kosync/kosync_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const authKey = '5e8667c0e3b3e1e6d3f2a1b0c9d8e7f6';

  KosyncClient clientWith(MockClient mock) => KosyncClient(
    baseUrl: 'https://sync.example.com',
    username: 'reader',
    authKey: authKey,
    client: mock,
  );

  group('KosyncClient 请求格式', () {
    test('鉴权带 x-auth-user / x-auth-key 与协议要求的 Accept 头', () async {
      late http.Request seen;
      final mock = MockClient((request) async {
        seen = request;
        return http.Response('{"authorized":"OK"}', 200);
      });
      addTearDown(mock.close);

      await clientWith(mock).authenticate();

      expect(seen.method, 'GET');
      expect(seen.url.path, '/users/auth');
      expect(seen.headers['Accept'], 'application/vnd.koreader.v1+json');
      expect(seen.headers['x-auth-user'], 'reader');
      expect(seen.headers['x-auth-key'], authKey);
    });

    test('注册提交 username 与 password 两个字段', () async {
      late http.Request seen;
      final mock = MockClient((request) async {
        seen = request;
        return http.Response('{"username":"reader"}', 201);
      });
      addTearDown(mock.close);

      await clientWith(mock).createUser();

      expect(seen.method, 'POST');
      expect(seen.url.path, '/users/create');
      expect(jsonDecode(seen.body), <String, dynamic>{
        'username': 'reader',
        'password': authKey,
      });
      // 注册请求不带凭据头：服务端用请求体里的密码建账号。
      expect(seen.headers.containsKey('x-auth-user'), isFalse);
    });

    test('推送进度带上协议要求的全部字段', () async {
      late http.Request seen;
      final mock = MockClient((request) async {
        seen = request;
        return http.Response('{"document":"abc","timestamp":1700000000}', 200);
      });
      addTearDown(mock.close);

      final stamp = await clientWith(mock).pushProgress(
        document: 'abc',
        progress: 'y1:3:120',
        percentage: 0.42,
        device: 'Pixel',
        deviceId: 'dev-1',
      );

      expect(stamp, 1700000000);
      expect(seen.method, 'PUT');
      expect(seen.url.path, '/syncs/progress');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['document'], 'abc');
      expect(body['progress'], 'y1:3:120');
      expect(body['percentage'], 0.42);
      expect(body['device'], 'Pixel');
      expect(body['device_id'], 'dev-1');
    });

    test('百分比被夹在 0 到 1 之间', () async {
      late http.Request seen;
      final mock = MockClient((request) async {
        seen = request;
        return http.Response('{"document":"abc","timestamp":1}', 200);
      });
      addTearDown(mock.close);

      await clientWith(mock).pushProgress(
        document: 'abc',
        progress: 'p',
        percentage: 1.8,
        device: 'd',
        deviceId: 'i',
      );

      expect((jsonDecode(seen.body) as Map)['percentage'], 1.0);
    });

    test('拉取进度解析服务端返回的字段', () async {
      final mock = MockClient(
        (_) async => http.Response(
          '{"progress":"y1:3:120","percentage":0.42,"device":"Pixel",'
          '"document":"abc","device_id":"dev-1","timestamp":1700000000}',
          200,
        ),
      );
      addTearDown(mock.close);

      final record = await clientWith(mock).fetchProgress('abc');

      expect(record, isNotNull);
      expect(record!.progress, 'y1:3:120');
      expect(record.percentage, 0.42);
      expect(record.device, 'Pixel');
      expect(record.deviceId, 'dev-1');
      expect(record.timestamp, 1700000000);
    });

    test('服务端没有记录时返回 null（响应体是空对象）', () async {
      final mock = MockClient((_) async => http.Response('{}', 200));
      addTearDown(mock.close);

      expect(await clientWith(mock).fetchProgress('abc'), isNull);
    });
  });

  group('KosyncClient 错误处理', () {
    test('401 映射成 code 2001 并给出中文提示', () async {
      final mock = MockClient(
        (_) async => http.Response('{"code":2001,"message":"Unauthorized"}', 401),
      );
      addTearDown(mock.close);

      await expectLater(
        clientWith(mock).authenticate(),
        throwsA(
          isA<KosyncException>()
              .having((e) => e.code, 'code', 2001)
              .having((e) => e.status, 'status', 401)
              .having((e) => e.localizedMessage, 'message', '账号或密码不正确'),
        ),
      );
    });

    test('用户名已占用是 402 / code 2002', () async {
      final mock = MockClient(
        (_) async => http.Response(
          '{"code":2002,"message":"Username is already registered."}',
          402,
        ),
      );
      addTearDown(mock.close);

      await expectLater(
        clientWith(mock).createUser(),
        throwsA(
          isA<KosyncException>()
              .having((e) => e.code, 'code', KosyncException.userExists)
              .having((e) => e.status, 'status', 402),
        ),
      );
    });

    test('Accept 不被接受是 412 / code 101', () async {
      final mock = MockClient(
        (_) async => http.Response(
          '{"code":101,"message":"Invalid Accept header format."}',
          412,
        ),
      );
      addTearDown(mock.close);

      await expectLater(
        clientWith(mock).authenticate(),
        throwsA(
          isA<KosyncException>()
              .having((e) => e.code, 'code', KosyncException.badAccept)
              .having((e) => e.status, 'status', 412),
        ),
      );
    });

    test('不可服务的 document 在本地就被拦下，不发请求', () async {
      var called = false;
      final mock = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      addTearDown(mock.close);

      await expectLater(
        clientWith(mock).fetchProgress('has-a-hyphen'),
        throwsA(
          isA<KosyncException>().having(
            (e) => e.code,
            'code',
            KosyncException.documentNotServable,
          ),
        ),
      );
      expect(called, isFalse);
    });

    test('document 字符集规则与服务端一致', () {
      expect(KosyncClient.isServableDocument('59d481d168cca6267322f150c5f6a2a3'), isTrue);
      expect(KosyncClient.isServableDocument('under_score'), isTrue);
      expect(KosyncClient.isServableDocument('MiXeD123'), isTrue);
      expect(KosyncClient.isServableDocument('has-a-hyphen'), isFalse);
      expect(KosyncClient.isServableDocument('has.a.dot'), isFalse);
      expect(KosyncClient.isServableDocument('has:colon'), isFalse);
      expect(KosyncClient.isServableDocument(''), isFalse);
    });

    test('服务器地址无效时给出明确错误', () async {
      final mock = MockClient((_) async => http.Response('{}', 200));
      addTearDown(mock.close);
      final client = KosyncClient(
        baseUrl: 'not a url',
        username: 'reader',
        authKey: authKey,
        client: mock,
      );

      await expectLater(
        client.authenticate(),
        throwsA(
          isA<KosyncException>().having(
            (e) => e.message,
            'message',
            contains('服务器地址无效'),
          ),
        ),
      );
    });

    test('网关返回 HTML 时不会把正文当成协议响应', () async {
      final mock = MockClient(
        (_) async => http.Response('<html>502 Bad Gateway</html>', 502),
      );
      addTearDown(mock.close);

      await expectLater(
        clientWith(mock).authenticate(),
        throwsA(isA<KosyncException>()),
      );
    });
  });
}
