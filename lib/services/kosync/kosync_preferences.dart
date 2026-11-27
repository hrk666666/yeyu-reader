import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../secure_key_provider.dart';

/// 计算口令的小写十六进制 MD5，即 kosync 协议里的 `x-auth-key`。
///
/// 协议全程只用这份 MD5：注册时服务端保存它，鉴权时客户端提交它。明文
/// 口令既不需要上传，也不需要留在设备上。
String kosyncAuthKey(String password) =>
    md5.convert(utf8.encode(password)).toString();

/// kosync 同步的配置。
///
/// 服务器地址、账号名、开关放在 SharedPreferences；口令的 MD5 放在系统
/// 安全存储（Android Keystore / iOS Keychain），不进普通偏好文件。
class KosyncPreferences {
  KosyncPreferences({SecureKeyStorage? secureStorage})
    : _secureStorage =
          secureStorage ?? testStorage ?? const FlutterSecureKeyStorage();

  static final KosyncPreferences instance = KosyncPreferences();

  /// 测试用：替换安全存储的后端。
  ///
  /// 真机上的安全存储走平台通道，单元测试里没有通道；换成内存实现即可，
  /// 生产的读写路径完全不受影响。
  @visibleForTesting
  static SecureKeyStorage? testStorage;

  static const String keyEnabled = 'kosync_enabled';
  static const String keyServerUrl = 'kosync_server_url';
  static const String keyUsername = 'kosync_username';
  static const String keyDeviceName = 'kosync_device_name';
  static const String keyDeviceId = 'kosync_device_id';

  /// 口令 MD5 在安全存储里的键名。
  static const String secureKeyName = 'fqapp_kosync_auth_key_v1';

  /// 公共 kosync 服务器。
  static const String defaultServerUrl = 'https://sync.koreader.rocks';

  /// 把用户填的地址整理成可以直接发请求的形式。
  ///
  /// 输入框里常见的几种写法都要能救回来：
  /// - `sync.example.com`：没有 scheme，[Uri.parse] 会把整个域名当成路径；
  /// - `https://sync.example.com/`：尾斜杠会让拼出来的路径出现 `//`；
  /// - 从网页或聊天记录里粘来的串可能带零宽字符，肉眼看不出来但会污染 host。
  ///
  /// 端口**不在这里动**：自建服务常年在非标准端口上，替用户删端口只会把
  /// 能用的地址改坏。填错端口由 [KosyncClient] 的连接错误提示去指导。
  static String normalizeServerUrl(String raw) {
    var value = raw.replaceAll(_invisible, '').trim();
    if (value.isEmpty) return defaultServerUrl;
    if (!value.contains('://')) value = 'https://$value';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 零宽空格、零宽连接符、BOM 这类复制时混进来的字符。
  static final RegExp _invisible = RegExp('[\u200B-\u200D\uFEFF]');

  final SecureKeyStorage _secureStorage;

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<String> serverUrl = ValueNotifier<String>(
    defaultServerUrl,
  );
  final ValueNotifier<String> username = ValueNotifier<String>('');
  final ValueNotifier<String> deviceName = ValueNotifier<String>('');
  final ValueNotifier<String> deviceId = ValueNotifier<String>('');
  final ValueNotifier<String> authKey = ValueNotifier<String>('');

  bool _loaded = false;

  /// 读取配置。重复调用只生效一次。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      enabled.value = sp.getBool(keyEnabled) ?? false;
      // 旧版本可能存过不带 scheme 或带尾斜杠的地址，读出来时一并纠正。
      serverUrl.value = normalizeServerUrl(
        sp.getString(keyServerUrl) ?? defaultServerUrl,
      );
      username.value = sp.getString(keyUsername) ?? '';
      deviceName.value = sp.getString(keyDeviceName) ?? _defaultDeviceName();
      var id = sp.getString(keyDeviceId);
      if (id == null || id.isEmpty) {
        id = _newDeviceId();
        await sp.setString(keyDeviceId, id);
      }
      deviceId.value = id;
    } catch (_) {
      // A broken optional preference reads as its default.
    }
    try {
      final stored = await _secureStorage.read(secureKeyName);
      authKey.value = stored ?? '';
    } catch (_) {
      // Without secure storage there is no way to keep the credential; the
      // sync stays off until the user enters it again.
      authKey.value = '';
    }
  }

  /// 让下一次 [load] 重新读取。测试用。
  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    enabled.value = false;
    serverUrl.value = defaultServerUrl;
    username.value = '';
    deviceName.value = '';
    deviceId.value = '';
    authKey.value = '';
  }

  /// 凭据是否齐全（地址、账号、口令都有）。
  ///
  /// 与 [isConfigured] 分开：「测试连接」「注册账号」这些操作用的是凭据，
  /// 用户可能还没打开同步开关就想先验一下服务器通不通。
  bool get hasCredentials =>
      serverUrl.value.trim().isNotEmpty &&
      username.value.trim().isNotEmpty &&
      authKey.value.isNotEmpty;

  /// 是否已经具备可用的同步条件。
  bool get isConfigured => enabled.value && hasCredentials;

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _writeBool(keyEnabled, value);
  }

  Future<void> setServerUrl(String value) async {
    serverUrl.value = normalizeServerUrl(value);
    await _writeString(keyServerUrl, serverUrl.value);
  }

  Future<void> setUsername(String value) async {
    username.value = value.trim();
    await _writeString(keyUsername, username.value);
  }

  Future<void> setDeviceName(String value) async {
    final normalized = value.trim();
    deviceName.value = normalized.isEmpty ? _defaultDeviceName() : normalized;
    await _writeString(keyDeviceName, deviceName.value);
  }

  /// 保存口令的 MD5。
  Future<void> setPassword(String password) =>
      setAuthKey(kosyncAuthKey(password));

  /// 直接保存一份已经算好的 MD5。
  Future<void> setAuthKey(String key) async {
    final normalized = key.trim().toLowerCase();
    authKey.value = normalized;
    try {
      await _secureStorage.write(secureKeyName, normalized);
    } catch (_) {
      // The in-session value still applies; only persistence failed.
    }
  }

  /// 清空全部配置，包括安全存储里的口令。
  Future<void> clear() async {
    enabled.value = false;
    username.value = '';
    authKey.value = '';
    await _writeBool(keyEnabled, false);
    await _writeString(keyUsername, '');
    try {
      await _secureStorage.write(secureKeyName, '');
    } catch (_) {
      // Nothing else to do: the in-session value is already cleared.
    }
  }

  Future<void> _writeBool(String key, bool value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, value);
    } catch (_) {
      // The in-session value still applies; only persistence failed.
    }
  }

  Future<void> _writeString(String key, String value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, value);
    } catch (_) {
      // The in-session value still applies; only persistence failed.
    }
  }

  static String _defaultDeviceName() {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    } catch (_) {
      // Not every platform exposes a hostname.
    }
    return 'Yeyu Reader';
  }

  /// 生成本机标识。协议只要求同一台设备的标识稳定不变。
  static String _newDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'yeyu-$hex';
  }
}
