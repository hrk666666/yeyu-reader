import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_version.dart';
import 'update_prompt_state.dart';

/// 更新检查 + 公告。
///
/// 数据源是公开仓里的**单独一个文件** `update.json`
/// （github.com/hrk666666/yeyu-reader），App 启动时默认拉取（设置可关）。
/// 有新版时**不从 GitHub 下载 APK**，而是引导用户跳转 `latest.url`
/// ——该链接在 update.json 里自定义（网盘 / 落地页皆可）。
/// 公告同样来自该文件，按 `announcement.id` 幂等展示。
///
/// 拉取走 GitHub 镜像：默认并发探测全部镜像、**先回先赢**（测速优选），
/// 设置里可手动钉死某一镜像。
class AppUpdateService {
  AppUpdateService({Future<String?> Function(String url)? fetcher})
      : _fetcher = fetcher ?? _defaultFetch;

  final Future<String?> Function(String url) _fetcher;

  // ── 配置 ────────────────────────────────────────────────────────────

  /// update.json 所在公开仓。
  static const String repoOwner = 'hrk666666';
  static const String repoName = 'yeyu-reader';
  static const String repoRef = 'main';
  static const String filePath = 'update.json';

  /// 镜像表：并发探测，最快返回合法内容者胜出。
  static const List<UpdateMirror> mirrors = [
    UpdateMirror(
      id: 'raw',
      label: 'GitHub 官方',
      build:
          'https://raw.githubusercontent.com/$repoOwner/$repoName/$repoRef/$filePath',
    ),
    UpdateMirror(
      id: 'jsdelivr',
      label: 'jsDelivr CDN',
      build:
          'https://cdn.jsdelivr.net/gh/$repoOwner/$repoName@$repoRef/$filePath',
    ),
    UpdateMirror(
      id: 'ghproxy',
      label: 'ghproxy.net',
      build:
          'https://ghproxy.net/https://raw.githubusercontent.com/$repoOwner/$repoName/$repoRef/$filePath',
    ),
    UpdateMirror(
      id: 'ghproxy-com',
      label: 'gh-proxy.com',
      build:
          'https://gh-proxy.com/https://raw.githubusercontent.com/$repoOwner/$repoName/$repoRef/$filePath',
    ),
    UpdateMirror(
      id: 'gitmirror',
      label: 'GitMirror',
      build:
          'https://raw.gitmirror.com/$repoOwner/$repoName/$repoRef/$filePath',
    ),
    UpdateMirror(
      id: 'moeyy',
      label: 'Moeyy 加速',
      build:
          'https://github.moeyy.xyz/https://raw.githubusercontent.com/$repoOwner/$repoName/$repoRef/$filePath',
    ),
  ];

  static const String _kEnabled = 'update_check_enabled';
  static const String _kMirror = 'update_mirror'; // 'auto' 或镜像 id

  // ── 设置读写 ────────────────────────────────────────────────────────

  /// 启动时自动检查（默认开）。
  static Future<bool> autoCheckEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kEnabled) ?? true;
  }

  static Future<void> setAutoCheckEnabled(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kEnabled, value);
  }

  /// 镜像选择：`auto`（测速优选）或 [mirrors] 里的 id。
  static Future<String> mirrorMode() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kMirror) ?? 'auto';
  }

  static Future<void> setMirrorMode(String mode) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kMirror, mode);
  }

  // ── 检查 ────────────────────────────────────────────────────────────

  /// 拉取 update.json 并判定是否需要更新/展示公告。
  Future<UpdateCheckResult> check() async {
    final mode = await mirrorMode();
    final String? body;
    final String mirrorLabel;
    if (mode == 'auto') {
      final probed = await _raceAll();
      body = probed?.$1;
      mirrorLabel = probed?.$2.label ?? 'auto';
    } else {
      final mirror =
          mirrors.where((m) => m.id == mode).firstOrNull ?? mirrors.first;
      body = await _fetcher(mirror.build);
      mirrorLabel = mirror.label;
    }
    if (body == null) return UpdateCheckResult(error: '全部镜像均不可达', mirror: mirrorLabel);

    final manifest = UpdateManifest.tryParse(body);
    if (manifest == null) {
      return UpdateCheckResult(error: 'update.json 解析失败', mirror: mirrorLabel);
    }
    return UpdateCheckResult(
      manifest: manifest,
      hasUpdate: manifest.latest.versionCode > kVersionCode,
      mirror: mirrorLabel,
    );
  }

  /// 公告是否需要展示。
  ///
  /// 三个条件缺一不可：公告启用、**公告讲的不是本机已经装上的版本**、
  /// 且 id 比已看过的新。中间那条是「升级后不再重弹上个版本的更新通知」的
  /// 依据——公告可以显式带 `versionCode`；没带时按 id 幂等，兼容旧数据。
  static Future<bool> shouldShowAnnouncement(Announcement a) async {
    if (!a.enabled) return false;
    final about = a.versionCode;
    if (about != null && about > 0 && about <= kVersionCode) return false;
    return a.id > await UpdatePromptState.seenAnnouncementId();
  }

  static Future<void> markAnnouncementSeen(Announcement a) =>
      UpdatePromptState.markAnnouncementSeen(a.id);

  /// 同一版本只自动弹一次更新提示（手动检查不受限）。
  ///
  /// 记录同时落 SharedPreferences 与文件，见 [UpdatePromptState]：只写一处时
  /// 部分机型的冷启动会读回旧值，于是每次打开都重弹。
  static Future<bool> shouldAutoPrompt(int versionCode) async =>
      versionCode > await UpdatePromptState.promptedVersionCode();

  static Future<void> markAutoPrompted(int versionCode) =>
      UpdatePromptState.markPromptedVersion(versionCode);

  // ── 镜像探测 ────────────────────────────────────────────────────────

  /// 并发请求全部镜像，**先回先赢**（即测速优选最快镜像）。
  /// 全部失败返回 null。先完成的请求结果即用，其余静默结束。
  Future<(String, UpdateMirror)?> _raceAll() {
    final completer = Completer<(String, UpdateMirror)?>();
    var pending = mirrors.length;
    for (final m in mirrors) {
      _fetcher(m.build).then((body) {
        if (body != null && !completer.isCompleted) {
          completer.complete((body, m));
        }
        pending--;
        if (pending == 0 && !completer.isCompleted) completer.complete(null);
      }).catchError((Object _) {
        pending--;
        if (pending == 0 && !completer.isCompleted) completer.complete(null);
      });
    }
    return completer.future;
  }

  static Future<String?> _defaultFetch(String url) async {
    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) return res.body;
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// 单个镜像端点。
class UpdateMirror {
  const UpdateMirror({
    required this.id,
    required this.label,
    required this.build,
  });

  final String id;
  final String label;
  final String build;
}

/// update.json 里的最新版本条目。
class UpdateInfo {
  const UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.minVersionCode,
    required this.url,
    required this.notes,
  });

  final String versionName;
  final int versionCode;

  /// 低于此版本建议强制更新（0 = 不强制）。
  final int minVersionCode;

  /// **自定义跳转链接**：有新版时引导用户前往（非 GitHub 直接下载）。
  final String url;
  final String notes;
}

/// 公告（同文件携带，按 id 幂等展示）。
class Announcement {
  const Announcement({
    required this.id,
    required this.enabled,
    required this.title,
    required this.body,
    this.url,
    this.versionCode,
  });

  final int id;
  final bool enabled;
  final String title;
  final String body;
  final String? url;

  /// 公告讲述的版本号（可选）。填了且不高于本机版本时不再提示——公告讲的是
  /// 用户已经装上的版本，再弹一次就是「上个版本的更新通知」。
  final int? versionCode;
}

class UpdateManifest {
  const UpdateManifest({required this.latest, this.announcement});

  final UpdateInfo latest;
  final Announcement? announcement;

  static UpdateManifest? tryParse(String body) {
    try {
      final map = _jsonMap(_decode(body));
      if (map == null) return null;
      final latest = _jsonMap(map['latest']);
      if (latest == null) return null;
      final ann = _jsonMap(map['announcement']);
      return UpdateManifest(
        latest: UpdateInfo(
          versionName: latest['versionName'] as String? ?? '',
          versionCode: (latest['versionCode'] as num?)?.toInt() ?? 0,
          minVersionCode: (latest['minVersionCode'] as num?)?.toInt() ?? 0,
          url: latest['url'] as String? ?? '',
          notes: latest['notes'] as String? ?? '',
        ),
        announcement: ann == null
            ? null
            : Announcement(
                id: (ann['id'] as num?)?.toInt() ?? 0,
                enabled: ann['enabled'] as bool? ?? true,
                title: ann['title'] as String? ?? '',
                body: ann['body'] as String? ?? '',
                url: ann['url'] as String?,
                versionCode: (ann['versionCode'] as num?)?.toInt(),
              ),
      );
    } catch (_) {
      return null;
    }
  }

  static Object? _decode(String body) => jsonDecode(body);

  static Map<String, dynamic>? _jsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    return null;
  }
}

/// 一次检查的结果。
class UpdateCheckResult {
  const UpdateCheckResult({
    this.manifest,
    this.hasUpdate = false,
    this.error,
    this.mirror,
  });

  final UpdateManifest? manifest;
  final bool hasUpdate;
  final String? error;
  final String? mirror;

  bool get ok => error == null && manifest != null;

  /// 低于 minVersionCode，建议强制更新。
  bool get mustUpdate =>
      manifest != null && manifest!.latest.minVersionCode > kVersionCode;
}

/// 启动时静默检查的调度器：可取消的延时定时器，壳层 dispose 时取消
/// ——悬空 Timer 会污染测试收尾（pending timer 断言）。
class AppUpdateScheduler {
  AppUpdateScheduler();

  static const Duration delay = Duration(seconds: 6);

  Timer? _timer;

  /// [onResult] 在检查完成后回调（含失败结果）；未开启自动检查则不回调。
  void schedule(void Function(UpdateCheckResult result) onResult) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      if (!await AppUpdateService.autoCheckEnabled()) return;
      final result = await AppUpdateService().check();
      onResult(result);
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
