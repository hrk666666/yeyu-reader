import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 一个 kosync 服务端返回的协议级错误。
///
/// 服务端用 `{"code": <int>, "message": "<text>"}` 表达错误，code 是稳定
/// 的机器可读标识，message 是给人看的英文说明（官方服务器不翻译）。
class KosyncException implements Exception {
  const KosyncException(this.code, this.message, {this.status});

  /// 服务端错误码，例如 2001 表示鉴权失败。
  final int code;

  /// 服务端给出的英文说明。
  final String message;

  /// HTTP 状态码；网络层错误时为 null。
  final int? status;

  /// 错误码 2001：凭据不对。
  static const int unauthorized = 2001;

  /// 错误码 2002：用户名已被占用。
  static const int userExists = 2002;

  /// 错误码 2003：请求字段无效。
  static const int invalidFields = 2003;

  /// 错误码 2005：服务器禁止注册新用户。
  static const int registrationDisabled = 2005;

  /// 错误码 2006：账号不存在。
  static const int accountNotFound = 2006;

  /// 错误码 2007：document 含有服务端无法服务的字符。
  static const int documentNotServable = 2007;

  /// 错误码 101：Accept 头缺失或格式不对。
  static const int badAccept = 101;

  /// 错误码 102：Accept 头指向了服务端不支持的协议版本。
  static const int unsupportedVersion = 102;

  /// 面向用户的中文提示。
  String get localizedMessage {
    switch (code) {
      case unauthorized:
        return '账号或密码不正确';
      case userExists:
        return '该用户名已被占用';
      case invalidFields:
        return '服务器认为请求内容无效';
      case registrationDisabled:
        return '该服务器已关闭注册';
      case accountNotFound:
        return '账号不存在';
      case documentNotServable:
        return '书籍标识不符合服务器要求';
      case badAccept:
        return '服务器不接受当前协议版本';
      case unsupportedVersion:
        return '服务器不支持当前协议版本';
      default:
        return message.isEmpty ? '同步服务返回错误（$code）' : message;
    }
  }

  @override
  String toString() => 'KosyncException($code, $message, status: $status)';
}

/// 服务端记录的一条阅读进度。
class KosyncProgressRecord {
  const KosyncProgressRecord({
    required this.document,
    required this.progress,
    required this.percentage,
    required this.device,
    required this.deviceId,
    required this.timestamp,
  });

  /// 书籍标识。
  final String document;

  /// 位置标识串。格式由两端约定，页屿用 [KosyncProgress] 的自有格式。
  final String progress;

  /// 全书进度，0 到 1。
  final double percentage;

  /// 上次写入的设备名。
  final String device;

  /// 上次写入的设备 id。
  final String deviceId;

  /// 服务端记录的写入时间，**单位是秒**。
  final int timestamp;

  /// 服务端没有这条记录时返回的响应体是空对象，对应 null。
  static KosyncProgressRecord? fromJson(Map<String, dynamic> json) {
    final document = json['document']?.toString();
    final progress = json['progress']?.toString();
    if (document == null || document.isEmpty || progress == null) return null;
    return KosyncProgressRecord(
      document: document,
      progress: progress,
      percentage: _toDouble(json['percentage']),
      device: json['device']?.toString() ?? '',
      deviceId: json['device_id']?.toString() ?? '',
      timestamp: _toInt(json['timestamp']),
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _toInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// kosync 协议客户端。
///
/// 协议本身极简：用户名 + 口令的 MD5 当作固定凭据，服务端按 `document`
/// 存一条「上次读到哪」的记录，写入覆盖写入（last-write-wins），冲突判定
/// 全部由客户端自己做。
///
/// 参考实现是 KOReader 的 `plugins/kosync.koplugin`，服务端是
/// `koreader/koreader-sync-server`。
class KosyncClient {
  KosyncClient({
    required this.baseUrl,
    required this.username,
    required this.authKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// 服务器地址，例如 `https://sync.koreader.rocks`。
  final String baseUrl;

  /// 账号名。
  final String username;

  /// 口令的**小写十六进制 MD5**，即协议里的 `x-auth-key`。
  ///
  /// 明文口令不落盘：注册时由服务端保存这份 MD5，鉴权时也只需这份 MD5。
  final String authKey;

  /// 单次请求超时。
  final Duration timeout;

  final http.Client _client;
  final bool _ownsClient;

  /// 协议要求携带的 Accept 头。
  static const String acceptHeader = 'application/vnd.koreader.v1+json';

  /// 服务端只接受这个字符集的 `document`（HEAD 版服务端新增的校验）。
  static final RegExp servableDocument = RegExp(r'^[A-Za-z0-9_]+$');

  /// 判断一个 `document` 是否满足服务端的字符集要求。
  static bool isServableDocument(String document) =>
      document.isNotEmpty && servableDocument.hasMatch(document);

  Uri _uri(String path) {
    final base = baseUrl.trim();
    // 没写 scheme 时按 https 处理：`Uri.parse('sync.example.com')` 会把整个
    // 域名当成路径，host 为空，请求根本发不出去。
    final candidate = base.contains('://') ? base : 'https://$base';
    // 有空白字符的一定不是地址：`Uri.parse('https://not a url')` 会把空格
    // 编码进 host 而不报错，请求发出去只会得到 DNS 失败。
    if (RegExp(r'\s').hasMatch(candidate)) {
      throw KosyncException(0, '服务器地址无效：$baseUrl');
    }
    final normalized = candidate.endsWith('/')
        ? candidate.substring(0, candidate.length - 1)
        : candidate;
    final parsed = Uri.tryParse(normalized);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw KosyncException(0, '服务器地址无效：$baseUrl');
    }
    return parsed.replace(path: '${parsed.path}$path');
  }

  /// 本次请求实际要连的 `host:port`，用于把网络错误说清楚。
  ///
  /// 用户看到「Connection refused」时最需要知道的就是这两个值——绝大多数
  /// 情况是地址里多带了端口，或者少写了端口。
  String get connectionTarget {
    final base = baseUrl.trim();
    final candidate = base.contains('://') ? base : 'https://$base';
    final parsed = Uri.tryParse(candidate);
    if (parsed == null || parsed.host.isEmpty) return baseUrl.trim();
    return '${parsed.host}:${parsed.port}';
  }

  /// 把底层网络异常翻译成能指导用户改配置的中文说明。
  String _connectionMessage(Object error) {
    final text = error.toString();
    final target = connectionTarget;
    if (text.contains('Failed host lookup') ||
        text.contains('nodename nor servname')) {
      return '无法解析服务器地址（$target）：请检查地址是否写错';
    }
    if (text.contains('Connection refused')) {
      return '服务器拒绝连接（$target）：地址若带了端口，请确认端口号；不需要端口就删掉冒号后的部分';
    }
    if (text.contains('timed out') || text.contains('TimeoutException')) {
      return '连接服务器超时（$target）：服务器没有响应，可能不可达或被网络拦截';
    }
    if (text.contains('HandshakeException') ||
        text.contains('CertificateException')) {
      return 'HTTPS 握手失败（$target）：服务器证书不被信任；局域网自建服务请用 http:// 开头';
    }
    return '无法连接同步服务器（$target）：$text';
  }

  Map<String, String> _headers({bool auth = true}) {
    return <String, String>{
      'Accept': acceptHeader,
      if (auth) 'x-auth-user': username,
      if (auth) 'x-auth-key': authKey,
    };
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final uri = _uri(path);
    late http.Response response;
    try {
      final request = http.Request(method, uri)
        ..headers.addAll(_headers(auth: auth));
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw KosyncException(0, '连接同步服务器超时（$connectionTarget）');
    } catch (error) {
      throw KosyncException(0, _connectionMessage(error));
    }

    Map<String, dynamic> json = const <String, dynamic>{};
    final text = response.body;
    if (text.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) json = decoded.cast<String, dynamic>();
      } catch (_) {
        // A proxy or gateway answered with HTML; report the status instead of
        // pretending the body was a protocol answer.
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw KosyncException(0, '服务器返回的不是合法响应', status: response.statusCode);
        }
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return json;

    final code = json['code'] is num ? (json['code'] as num).toInt() : 0;
    final message = json['message']?.toString() ?? 'HTTP ${response.statusCode}';
    throw KosyncException(code, message, status: response.statusCode);
  }

  /// 注册账号。服务器已存在同名账号时抛 [KosyncException]（code 2002）。
  Future<void> createUser() async {
    await _send(
      'POST',
      '/users/create',
      body: <String, dynamic>{'username': username, 'password': authKey},
      auth: false,
    );
  }

  /// 校验凭据。成功返回 true，凭据不对时抛 [KosyncException]（code 2001）。
  Future<bool> authenticate() async {
    final json = await _send('GET', '/users/auth');
    return json['authorized']?.toString() == 'OK';
  }

  /// 拉取一条进度。服务端没有这条记录时返回 null。
  Future<KosyncProgressRecord?> fetchProgress(String document) async {
    if (!isServableDocument(document)) {
      throw const KosyncException(
        KosyncException.documentNotServable,
        'document contains characters the read route cannot serve',
      );
    }
    final json = await _send('GET', '/syncs/progress/$document');
    return KosyncProgressRecord.fromJson(json);
  }

  /// 推送一条进度，返回服务端写入的时间戳（秒）。
  Future<int> pushProgress({
    required String document,
    required String progress,
    required double percentage,
    required String device,
    required String deviceId,
    Map<String, dynamic>? metadata,
  }) async {
    if (!isServableDocument(document)) {
      throw const KosyncException(
        KosyncException.documentNotServable,
        'document contains characters the read route cannot serve',
      );
    }
    final json = await _send(
      'PUT',
      '/syncs/progress',
      body: <String, dynamic>{
        'document': document,
        'progress': progress,
        'percentage': percentage.clamp(0.0, 1.0).toDouble(),
        'device': device,
        'device_id': deviceId,
        'metadata': ?metadata,
      },
    );
    final timestamp = json['timestamp'];
    if (timestamp is num) return timestamp.toInt();
    return 0;
  }

  /// 修改口令。[newAuthKey] 是新口令的 MD5。
  Future<void> changePassword(String newAuthKey) async {
    await _send(
      'PUT',
      '/users/password',
      body: <String, dynamic>{'password': newAuthKey},
    );
  }

  /// 删除当前账号及其全部进度。
  Future<void> deleteAccount() async {
    await _send('DELETE', '/users/me');
  }

  /// 释放自建的 HTTP 连接。
  void close() {
    if (_ownsClient) _client.close();
  }
}
