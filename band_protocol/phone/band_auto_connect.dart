import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'band_book_catalog.dart';
import 'band_book_remote.dart';
import 'band_book_transfer.dart';
import 'band_reading_sync.dart';

/// 启动后静默尝试连接手环，连上就做一轮全量阅读数据同步。
///
/// 设计约束：
/// - **无声**：失败不弹任何 UI（没戴手环是常态），只留 debug 日志；
/// - **可关**：[enabledKey] 开关由手环页设置，默认开；
/// - **复用链路**：走 [BandBookTransfer.shared]，用户随后打开手环页时
///   看到的就是同一条已连上的链路（`connect(reuse: true)` 幂等）；
/// - **只做同步**：不在后台传书——传输要展示进度，留给手环页显式触发。
class BandAutoConnect {
  BandAutoConnect._();

  static final BandAutoConnect instance = BandAutoConnect._();

  /// 启动时自动连接手环的开关（默认开）。
  static const String enabledKey = 'band_auto_connect_enabled';

  /// 连上手环后自动同步阅读数据（与手环页同一个开关）。
  static const String autoSyncKey = 'band_book_auto_sync';

  bool _scheduled = false;
  bool _running = false;

  /// 延迟启动用的定时器。壳层销毁时取消：widget 测试收尾会断言没有
  /// 悬挂的 Timer，真机上销毁即退出，留着也没意义。
  Timer? _timer;

  Future<bool> enabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(enabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(enabledKey, value);
  }

  /// App 启动时调用一次。延迟几秒让首屏先起来，不抢启动资源。
  void schedule() {
    if (_scheduled) return;
    _scheduled = true;
    _timer = Timer(const Duration(seconds: 4), () {
      _timer = null;
      unawaited(runOnce());
    });
  }

  /// 壳层销毁时调用：取消还没触发的静默连接。
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// 静默跑一轮「连接 + 同步」。幂等，可重复调用（重入直接返回）。
  Future<void> runOnce() async {
    if (_running) return;
    _running = true;
    try {
      if (!await enabled()) return;
      final transfer = BandBookTransfer.shared;
      if (!transfer.state.connected) {
        await transfer.connect(reuse: true);
      }
      if (!transfer.state.connected) {
        debugPrint('[BandAutoConnect] 手环未连接，静默跳过');
        return;
      }
      await syncAllSilently();
    } catch (error) {
      // 后台同步绝不打扰用户；失败原因只进日志。
      debugPrint('[BandAutoConnect] 静默同步失败：$error');
    } finally {
      _running = false;
    }
  }

  /// 连上后做一轮全量同步：全部可传书目、进度 + 时长、双向取并集。
  ///
  /// 与手环页「立即同步全部」同一条链路（[BandReadingSync.syncAll]），
  /// 只是没有 UI 回调。
  Future<void> syncAllSilently() async {
    final sp = await SharedPreferences.getInstance();
    if (!(sp.getBool(autoSyncKey) ?? true)) return;

    final books = await BandBookCatalog().load();
    if (books.isEmpty) return;
    final targets = [
      for (final entry in books)
        BandSyncTarget(
          title: entry.title,
          bookId: entry.id,
          chapterCount: entry.chapters.length,
          item: entry.toMediaItem(),
        ),
    ];
    final transfer = BandBookTransfer.shared;
    final sync = BandReadingSync(BandBookRemote(transfer));
    final results = await sync.syncAll(targets);
    final failed = results.where((r) => !r.ok).length;
    debugPrint(
      '[BandAutoConnect] 静默同步完成 ${results.length} 本'
      '${failed > 0 ? '（$failed 本失败）' : ''}',
    );
  }
}
