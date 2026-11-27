import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「更新提示 / 公告已看过」的持久化。
///
/// 这类状态写在 [SharedPreferences] 里本该够用，但它在部分机型上会失效：
/// 冷启动时读回旧值（ROM 清理、换机恢复、写入还没落盘就被杀进程），于是每次
/// 打开都把同一份公告当成新的重弹一遍——用户看到的正是「每次第一次打开都弹
/// 上个版本的更新通知」。
///
/// 所以这里双写：SharedPreferences 保留（兼容旧数据），另外落一份 JSON 文件；
/// 读取时取两边最大值。单边丢写、回滚、被清缓存，都不会让提示退回「没看过」。
class UpdatePromptState {
  UpdatePromptState._();

  /// 与 [AppUpdateService] 历史的键名保持一致，升级用户不用重新看一遍公告。
  static const String _kSeenAnnouncement = 'update_seen_announcement_id';
  static const String _kPromptedVersion = 'update_prompted_version_code';
  static const String _fileName = 'update_prompt_state.json';

  static Map<String, dynamic>? _cached;

  /// 测试注入：状态文件所在目录。为 null 时用应用支持目录。
  static Future<Directory?> Function()? debugDirectoryResolver;

  static Future<File?> _file() async {
    try {
      final resolver = debugDirectoryResolver;
      final dir = resolver != null
          ? await resolver()
          : await getApplicationSupportDirectory();
      if (dir == null) return null;
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    } catch (_) {
      // 测试环境没有 path_provider 插件，退化成只用 SharedPreferences。
      return null;
    }
  }

  static Future<Map<String, dynamic>> _readFile() async {
    final cached = _cached;
    if (cached != null) return cached;
    final file = await _file();
    Map<String, dynamic> data = const {};
    if (file != null) {
      try {
        if (await file.exists()) {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, dynamic>) data = decoded;
        }
      } catch (_) {
        data = const {};
      }
    }
    _cached = data;
    return data;
  }

  /// 取两处记录的最大值；都没有时返回 [fallback]。
  static Future<int> _read(String key, {int fallback = -1}) async {
    var value = fallback;
    try {
      final sp = await SharedPreferences.getInstance();
      final fromPrefs = sp.getInt(key);
      if (fromPrefs != null && fromPrefs > value) value = fromPrefs;
    } catch (_) {
      // 读不到就只信文件，别让一次插件异常挡住启动流程。
    }
    final data = await _readFile();
    final fromFile = data[key];
    if (fromFile is num && fromFile.toInt() > value) value = fromFile.toInt();
    return value;
  }

  static Future<void> _write(String key, int value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(key, value);
    } catch (_) {
      // 写失败不影响文件那份。
    }
    final file = await _file();
    if (file == null) return;
    final data = Map<String, dynamic>.from(await _readFile());
    data[key] = value;
    _cached = data;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // 文件写不进去时还有 SharedPreferences，不抛给调用方。
    }
  }

  static Future<int> seenAnnouncementId() => _read(_kSeenAnnouncement);

  static Future<void> markAnnouncementSeen(int id) =>
      _write(_kSeenAnnouncement, id);

  static Future<int> promptedVersionCode() => _read(_kPromptedVersion);

  static Future<void> markPromptedVersion(int versionCode) =>
      _write(_kPromptedVersion, versionCode);

  /// 仅用于测试：丢掉进程内文件缓存。
  static void debugResetCache() => _cached = null;
}
