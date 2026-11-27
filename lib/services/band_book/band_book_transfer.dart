import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'band_book_link.dart';

/// 传书会话所处阶段。
enum BandTransferPhase { idle, connecting, handshaking, ready, sending, finished, failed }

/// 手环上某本书的既有状态（增量同步的依据）。
@immutable
class BandBookStatus {
  const BandBookStatus({
    required this.syncedChapters,
    required this.hasCover,
  });

  /// 手环端 `indexes/*.txt` 里已落地章节的绝对索引。
  final Set<int> syncedChapters;

  final bool hasCover;

  static const BandBookStatus empty = BandBookStatus(
    syncedChapters: <int>{},
    hasCover: false,
  );

  /// 相对某本书的全量章节，返回还没同步的索引（升序）。
  List<int> missingFrom(int totalChapters) {
    final missing = <int>[];
    for (var i = 0; i < totalChapters; i++) {
      if (!syncedChapters.contains(i)) missing.add(i);
    }
    return missing;
  }
}

/// 页面直接渲染的状态快照。
@immutable
class BandTransferState {
  const BandTransferState({
    this.phase = BandTransferPhase.idle,
    this.device,
    this.bandVersion,
    this.fraction = 0,
    this.label = '',
    this.speed = '',
    this.error,
    this.totalChapters = 0,
    this.sentChapters = 0,
    this.downloading = false,
    this.retries = 0,
  });

  final BandTransferPhase phase;
  final BandDevice? device;
  final int? bandVersion;

  /// 本次任务的进度 0..1。
  final double fraction;

  /// 当前章节名 / 状态文案。
  final String label;

  /// 形如 `128 KB/s`，未知时为空。
  final String speed;

  final String? error;

  /// 本次任务要传的章节数。
  final int totalChapters;

  /// 已落地章节数。
  final int sentChapters;

  /// 流水线里是否正有章节在取正文（边下边传的直观反馈）。
  final bool downloading;

  /// 已自动重连续传次数。
  final int retries;

  bool get busy =>
      phase == BandTransferPhase.connecting ||
      phase == BandTransferPhase.handshaking ||
      phase == BandTransferPhase.sending;

  bool get connected =>
      phase == BandTransferPhase.ready ||
      phase == BandTransferPhase.sending ||
      phase == BandTransferPhase.finished;

  BandTransferState copyWith({
    BandTransferPhase? phase,
    BandDevice? device,
    int? bandVersion,
    double? fraction,
    String? label,
    String? speed,
    String? error,
    int? totalChapters,
    int? sentChapters,
    bool? downloading,
    int? retries,
  }) {
    return BandTransferState(
      phase: phase ?? this.phase,
      device: device ?? this.device,
      bandVersion: bandVersion ?? this.bandVersion,
      fraction: fraction ?? this.fraction,
      label: label ?? this.label,
      speed: speed ?? this.speed,
      error: error ?? this.error,
      totalChapters: totalChapters ?? this.totalChapters,
      sentChapters: sentChapters ?? this.sentChapters,
      downloading: downloading ?? this.downloading,
      retries: retries ?? this.retries,
    );
  }
}

/// 与手环端（弦电子书 Vela 客户端）的会话。
///
/// 协议逐条对齐开源两端（`youshen2/com.bandbbs.ebook` 的手环侧
/// `utils/handshake.js` + `utils/interconnfile.js`，以及手机侧
/// `InterHandshake.kt` + `InterconnetFile.kt`）：
///
/// **握手** tag `__hs__`，count 0→1→2，任一侧收到 `count > 0` 即视为连上，
/// 回包 `count + 1`，到 3 停。任何一次发送前都先确保握手完成（单飞
/// promise，并发调用共用同一次握手）。
///
/// **空闲看门狗** 收到任意一包就重置 10s 定时器（手环端 15s），超时即
/// 判定失联：清掉握手态，下一次发送自动重来一轮。
///
/// **传书** `startTransfer`（带 `chapterIndices` 子集与 `startFrom`）→ 手环回
/// `ready` → 正文按 1 万字符切片走 `stat: d`，每片等手环回 `next_chunk`
/// （末片回 `chapter_chunk_complete`）再发下一片 → 发 `chapter_complete`
/// → 等 `chapter_saved` → 下一章 → `transfer_complete` → `transfer_finished`。
///
/// **增量** 先 `get_book_status` 拿手环上已有的章节索引集合，只把缺的章节
/// 排进 `chapterIndices`；`startFrom` 取该子集首个索引（手环端只把它写进
/// `lindex.txt` 的进度行，真正的落地由 `chapter_complete` 的 `count` 决定）。
///
/// **断线续传** 传输中断线时 5s 后重连、从游标处重新 `startTransfer`，
/// 手环端 `rebuildSyncedIndices` 会重建已落地的索引，重复章节不会重写。
///
/// **流式** 取正文与发分片重叠：发第 N 章时后台已在取第 N+1 章，
/// 所以「手机边下载边推送」不需要先把整本下完。
class BandBookTransfer extends ChangeNotifier {
  BandBookTransfer({
    BandBookLink? link,
    this.retryDelay = const Duration(seconds: 5),
  }) : _link = link ?? BandBookLink() {
    _link.start();
    _subscription = _link.incoming.listen(_onMessage);
    _linkSubscription = _link.linkEvents.listen(_onLinkEvent);
  }

  /// 页面级复用：传输中切走再回来能接着看进度，不在页面 dispose 时中断。
  static final BandBookTransfer shared = BandBookTransfer();

  /// 手环端按「字符数」切片的同一上限：改大会让单片消息超过通道预算。
  static const int chunkSize = 10 * 1024;

  /// 手机端版本号：手环端口径（V26.4.3 = 126430），低于它会在手环上弹
  /// 「版本不兼容」。我们用 V26.6.0 的编号，兼容当前全部手环端。
  static const int phoneVersion = 260600;

  /// 兼容版本号（dotted a.b.c，可续段）：连接强制要求手机与手环的 a.b
  /// 一致，c 及以后（机型码、修订号等）不限——版本不匹配的问题由此收敛。
  /// 手机端固定为 26.6 系列（与手环端 V26.6.1.xxx 同系列）。
  static const String phoneVersionName = '26.6.1';

  /// 取 a.b（前两段）；用于版本兼容判定。
  static String majorMinor(String version) {
    final parts = version.replaceFirst(RegExp(r'^[Vv]'), '').split('.');
    return parts.take(2).join('.');
  }

  /// 手环端最低可协商版本，与手机侧 `MIN_BAND_VERSION_CODE` 一致。
  static const int minBandVersion = 251231;

  /// 手环端握手看门狗是 15s，手机侧取 10s，留出往复余量。
  static const Duration _handshakeTimeout = Duration(seconds: 10);
  static const Duration _idleTimeout = Duration(seconds: 10);
  static const Duration _readyTimeout = Duration(seconds: 30);
  static const Duration _chunkTimeout = Duration(seconds: 25);
  static const Duration _finishTimeout = Duration(seconds: 30);
  static const Duration _statusTimeout = Duration(seconds: 8);

  /// 手环端握手看门狗是 15s：静默超过这个时长两端都会判掉线。
  /// 边下边传时手机可能几十秒没有业务消息，靠轻量的 `get_storage_info`
  /// 续命（手环端只读设备信息，无副作用）。
  static const Duration _keepAliveTick = Duration(seconds: 3);

  /// 连续多少个 tick 没有出站消息就补一包（3 × 3s = 9s < 两端 10s/15s）。
  static const int _keepAliveTicks = 3;

  static const String _handshakeTag = '__hs__';
  static const String _fileTag = 'file';

  final BandBookLink _link;

  /// 断线到重连之间的等待，测试可注入为 0。
  final Duration retryDelay;

  late final StreamSubscription<Map<String, dynamic>> _subscription;
  late final StreamSubscription<BandLinkEvent> _linkSubscription;

  BandTransferState _state = const BandTransferState();
  BandTransferState get state => _state;

  bool _connected = false;
  bool _sending = false;
  bool _cancelled = false;
  int _bandVersion = 0;
  String? _bandVersionName;

  /// 手环端回报的 dotted 版本名（诊断用）。
  String? get bandVersionName => _bandVersionName;

  /// 单飞握手：并发发送共用同一次握手，避免两端互刷 count。
  Completer<void>? _handshake;
  Timer? _handshakeTimer;
  Timer? _idleTimer;

  Completer<void>? _readyWait;
  Completer<void>? _chunkWait;
  Completer<bool>? _chapterWait;
  Completer<void>? _finishWait;
  Completer<BandBookStatus>? _statusWait;

  /// 当前会话的待传队列（绝对章节索引，升序）与游标。
  List<int> _queue = const <int>[];
  int _cursor = 0;

  /// 自上次出站以来的 tick 数，保活据此判断是否需要补一包。
  int _idleTicks = 0;
  Timer? _keepAlive;

  /// 正文流水线：已取到 / 正在取。
  /// 通用命令（查进度 / 读数据 / 存储 / 设置 / 删除）的在途请求。
  /// 手环端这些命令的回包没有请求 id，按注册顺序 FIFO 匹配。
  final List<_PendingCommand> _pending = <_PendingCommand>[];

  /// 命令互斥：手环端回包没有请求 id，两条命令并发在途时回包无法归属。
  /// 所有 `command()` / `fetchStatus()` 经这条 future 链排队串行执行
  /// （对齐弦电子书手机端 `InterconnetFile` 的 `mutex.withLock`）。
  Future<void> _cmdChain = Future<void>.value();

  final Map<int, String> _bodies = <int, String>{};
  final Map<int, Future<String>> _inflight = <int, Future<String>>{};
  Future<String> Function(int index)? _loader;

  // 速度统计：只算正文，不含握手与元数据。
  int _bytesSent = 0;
  DateTime? _sentSince;

  void _set(BandTransferState next) {
    _state = next;
    notifyListeners();
  }

  void _fail(String message) {
    _completeAll(error: message);
    _set(_state.copyWith(phase: BandTransferPhase.failed, error: message));
  }

  void _completeAll({String? error}) {
    final exception = BandBookException(error ?? '会话已中断');
    void done(Completer<dynamic>? completer) {
      if (completer != null && !completer.isCompleted) {
        // ignore() 只抑制「无人 await 时的未捕获错误上报」，不吞掉
        // 正在 await 这一侧拿到的异常。
        completer.future.ignore();
        completer.completeError(exception);
      }
    }

    done(_readyWait);
    done(_chunkWait);
    done(_chapterWait);
    done(_finishWait);
    done(_statusWait);
    for (final pending in List<_PendingCommand>.from(_pending)) {
      pending.finish(error: exception);
    }
    _pending.clear();
    _readyWait = null;
    _chunkWait = null;
    _chapterWait = null;
    _finishWait = null;
    _statusWait = null;
  }

  // ---------------------------------------------------------------- 链路状态

  /// 收到任意一包就续命，超时即判失联（对齐手环端 `setTimeout` 看门狗）。
  void _touch() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _onIdle);
  }

  void _onIdle() {
    if (!_connected && _handshake == null) return;
    _connected = false;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    final pending = _handshake;
    _handshake = null;
    if (pending != null && !pending.isCompleted) {
      pending.future.ignore();
      pending.completeError(const BandBookException('握手超时，可尝试重启手机端'));
    }
    // 传输中失联要把在途等待打断，让重连循环接手（对齐手机侧
    // `setOnDisconnected { onError(...) }`）；空闲时不动 UI，下一次发送
    // 会自动再走一轮握手。
    if (_sending) _completeAll(error: '手环失联，正在重连');
  }

  void _onLinkEvent(BandLinkEvent event) {
    if (event != BandLinkEvent.broken) return;
    // 平台侧已经解绑，任何在途等待都必须立刻结束，否则会干等到分片超时。
    _connected = false;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    final pending = _handshake;
    _handshake = null;
    if (pending != null && !pending.isCompleted) {
      pending.future.ignore();
      pending.completeError(const BandBookException('手环连接已断开'));
    }
    // 传输中同样要打断在途等待，把控制权交回重连循环（对齐手环端
    // `setOnDisconnected { onError(...) }`）。
    _completeAll(error: '手环连接已断开');
    if (!_sending) {
      _set(_state.copyWith(phase: BandTransferPhase.idle, label: '连接已断开'));
    }
  }

  /// 确保已完成握手（手机侧 `InterHandshake.sendMessage` 的同一套逻辑）。
  Future<void> _ensureConnected() {
    if (_connected) return Future<void>.value();
    final existing = _handshake;
    if (existing != null) return existing.future;

    final completer = Completer<void>();
    _handshake = completer;
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(_handshakeTimeout, () {
      if (identical(_handshake, completer)) {
        _handshake = null;
        _connected = false;
      }
      if (!completer.isCompleted) {
        completer.future.ignore();
        completer.completeError(
          const BandBookException(
            '握手超时：请确认手环上已打开配套手环端、小米运动健康保持后台运行'
            '（若手环弹出「版本不兼容」，请安装与手机 a.b 一致的配套版本）',
          ),
        );
      }
    });

    unawaited(
      _transmit({
            'tag': _handshakeTag,
            'count': 0,
            'version': phoneVersion,
            'versionName': phoneVersionName,
          })
          .catchError((Object error) {
            if (identical(_handshake, completer)) _handshake = null;
            if (!completer.isCompleted) {
              completer.completeError(
                error is BandBookException ? error : BandBookException('$error'),
              );
            }
          }),
    );
    return completer.future;
  }

  void _markConnected() {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _connected = true;
    final pending = _handshake;
    _handshake = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// 出站底层：顺带重置保活计数。
  ///
  /// 套 10s 发送超时：xms-wearable 的 sendMessage Task 在链路异常时可能
  /// 永不回调，`await _transmit` 会把命令/分片全堵死（8s 命令超时只保护
  /// 回包等待，不保护发送本身）。
  Future<void> _transmit(Map<String, dynamic> message) {
    _idleTicks = 0;
    return _link.send(message).timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          throw const BandBookException('消息发送超时：手环可能已失联'),
    );
  }

  /// 所有业务出站消息的统一入口：先保证握手，再把平台异常翻译成链路失效。
  Future<void> _send(Map<String, dynamic> message) async {
    await _ensureConnected();
    try {
      await _transmit(message);
    } catch (error) {
      _connected = false;
      rethrow;
    }
  }

  /// 业务静默期间的保活：手环端 15s 收不到任何消息就会判定断开。
  void _startKeepAlive() {
    _keepAlive?.cancel();
    _idleTicks = 0;
    _keepAlive = Timer.periodic(_keepAliveTick, (_) {
      if (!_sending) {
        _stopKeepAlive();
        return;
      }
      _idleTicks += 1;
      if (_idleTicks < _keepAliveTicks) return;
      // 有在途业务命令时跳过保活，避免保活回包与业务回包在 FIFO 队列中错配。
      if (_pending.isNotEmpty) return;
      unawaited(
        _transmit({'tag': _fileTag, 'stat': 'get_storage_info'}).catchError((Object _) {}),
      );
    });
  }

  void _stopKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }

  // ---------------------------------------------------------------- 消息分发

  void _onMessage(Map<String, dynamic> message) {
    _touch();
    final tag = message['tag'];
    if (tag == _handshakeTag) {
      _onHandshake(message);
      return;
    }
    if (tag != _fileTag) return;

    final type = message['type'];

    // 通用命令优先匹配：这些回包（sync_reading_data / settings_data /
    // storage_info / success…）只属于命令，不会与传书流程消息撞车。
    if (_pending.isNotEmpty) {
      // 先按 accepts 精确匹配（error 也可能是某条命令的应答，例如
      // get_reading_data 的 accepts 显式接收 error）；只有没有任何命令
      // 认领该 error 时才按 FIFO 给队首——避免保活/杂音 error 错杀队首。
      for (var i = 0; i < _pending.length; i++) {
        if (_pending[i].accepts(message)) {
          final hit = _pending.removeAt(i);
          if (type == 'error') {
            hit.finish(
              error: BandBookException(
                message['message']?.toString() ?? '手环端执行失败',
              ),
            );
          } else {
            hit.finish(result: message);
          }
          return;
        }
      }
      if (type == 'error') {
        final failed = _pending.removeAt(0);
        failed.finish(
          error: BandBookException(
            message['message']?.toString() ?? '手环端执行失败',
          ),
        );
        return;
      }
    }
    switch (type) {
      case 'ready':
        final usage = (message['usage'] as num?)?.toInt() ?? 0;
        if (usage > 25 * 1024 * 1024) {
          _readyWait?.completeError(const BandBookException('手环存储空间不足'));
          _readyWait = null;
        } else {
          _readyWait?.complete();
          _readyWait = null;
        }
      case 'error':
        final text = message['message']?.toString() ?? '手环端报错';
        _fail(text);
      case 'next_chunk':
        _chunkWait?.complete();
        _chunkWait = null;
      case 'chapter_chunk_complete':
        _chunkWait?.complete();
        _chunkWait = null;
      case 'chapter_saved':
        _chapterWait?.complete(true);
        _chapterWait = null;
        _set(_state.copyWith(sentChapters: _cursor));
      case 'transfer_finished':
        _finishWait?.complete();
        _finishWait = null;
      case 'book_status':
        final raw = message['syncedChapters'];
        final synced = <int>{};
        if (raw is List) {
          for (final value in raw) {
            if (value is num) synced.add(value.toInt());
          }
        }
        _statusWait?.complete(
          BandBookStatus(
            syncedChapters: synced,
            hasCover: message['hasCover'] == true,
          ),
        );
        _statusWait = null;
      case 'cancel':
        _completeAll(error: '手环端已取消');
      case 'progress':
        final text = message['message']?.toString();
        if (text != null) _set(_state.copyWith(label: text));
      case 'success':
        final text = message['message']?.toString() ?? '完成';
        _set(_state.copyWith(label: text));
      case 'storage_info':
        // 保活回包，无业务含义；走到这里已经顺带刷新了看门狗。
        break;
    }
  }

  void _onHandshake(Map<String, dynamic> message) {
    final count = (message['count'] as num?)?.toInt() ?? 0;
    final version = (message['version'] as num?)?.toInt();
    final bandVersionName = message['versionName']?.toString();
    if (bandVersionName != null && bandVersionName.isNotEmpty) {
      _bandVersionName = bandVersionName;
    }
    if (version != null && version > 0) {
      _bandVersion = version;
    }

    // 版本规则：a.b.c（可续段），强制 a.b 一致，c 及以后不限。
    if (bandVersionName != null && bandVersionName.isNotEmpty) {
      if (majorMinor(bandVersionName) != majorMinor(phoneVersionName)) {
        final pending = _handshake;
        _handshake = null;
        _connected = false;
        if (pending != null && !pending.isCompleted) {
          pending.future.ignore();
          pending.completeError(
            BandBookException(
              '版本不兼容：手机 $phoneVersionName ↔ 手环 $bandVersionName'
              '（a.b 必须一致，请安装配套手环端）',
            ),
          );
        }
        return;
      }
    } else if (version != null && version > 0 && version < minBandVersion) {
      // 旧手环端（不回 versionName）：数值版本兜底检查。
      final pending = _handshake;
      _handshake = null;
      _connected = false;
      if (pending != null && !pending.isCompleted) {
        pending.future.ignore();
        pending.completeError(
          BandBookException('手环端版本过低（$version < $minBandVersion），请更新手环端'),
        );
      }
      return;
    }

    if (count > 0) {
      _markConnected();
      if (!_sending &&
          (_state.phase == BandTransferPhase.handshaking ||
              _state.phase == BandTransferPhase.connecting ||
              _state.phase == BandTransferPhase.idle)) {
        _set(
          _state.copyWith(
            phase: BandTransferPhase.ready,
            bandVersion: _bandVersion,
            label: '已连接',
          ),
        );
      }
    }
    // 与手环端同一套计数：0→1→2，最多回三次，防止两端互刷。
    final next = count + 1;
    if (next < 3) {
      unawaited(
        _transmit({
          'tag': _handshakeTag,
          'count': next,
          'version': phoneVersion,
          'versionName': phoneVersionName,
        }).catchError((Object _) {}),
      );
    }
  }

  /// 手环端版本是否满足最低要求（不满足会在手环侧弹「版本不兼容」）。
  bool get bandVersionCompatible =>
      _bandVersion == 0 || _bandVersion >= minBandVersion;

  // ---------------------------------------------------------------- 对外动作

  /// 建立链路并完成握手。[reuse] 为真时不重置 UI（重连场景）。
  Future<void> connect({bool reuse = false}) async {
    if (_sending) return;
    _handshakedReset();
    if (!reuse) {
      _set(
        const BandTransferState(
          phase: BandTransferPhase.connecting,
          label: '正在查找手环（请确保小米运动健康后台运行）…',
        ),
      );
    }
    try {
      final device = await _link.connect();
      if (!reuse) {
        _set(
          BandTransferState(
            phase: BandTransferPhase.handshaking,
            device: device,
            label: '${device.name}：正在打开手环端并握手…',
          ),
        );
      }
      await _ensureConnected();
      _set(
        _state.copyWith(
          phase: BandTransferPhase.ready,
          device: device,
          bandVersion: _bandVersion,
          label: '已连接',
          downloading: false,
        ),
      );
    } catch (error) {
      _fail(_describe(error));
    }
  }

  void _handshakedReset() {
    _connected = false;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _handshake = null;
  }

  /// 断开：清空监听与状态，UI 回到未连接。
  Future<void> disconnect() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _handshakedReset();
    await _link.disconnect();
    _set(const BandTransferState());
  }

  /// 取消正在进行的传输。
  Future<void> cancel() async {
    if (!_sending) return;
    _cancelled = true;
    try {
      await _transmit({'tag': _fileTag, 'stat': 'cancel'});
    } catch (_) {
      // 手环可能已经掉线：本地状态照样要收尾。
    }
    _completeAll(error: '已取消传输');
    _set(_state.copyWith(phase: BandTransferPhase.ready, label: '已取消'));
  }

  /// 查询手环上这本书的既有进度（增量同步的依据）。
  Future<BandBookStatus> fetchStatus(String title) {
    return _serialize(() async {
      if (_sending) return BandBookStatus.empty;
      try {
        await _ensureConnected();
        final wait = _statusWait = Completer<BandBookStatus>();
        await _send({'tag': _fileTag, 'stat': 'get_book_status', 'filename': title});
        return await wait.future.timeout(_statusTimeout);
      } on TimeoutException {
        return BandBookStatus.empty;
      } catch (_) {
        return BandBookStatus.empty;
      } finally {
        _statusWait = null;
      }
    });
  }

  /// 把一次命令放进串行队列（同一时刻只允许一条命令在途）。
  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _cmdChain.then((_) => action());
    // 链本身吞掉错误：上一条命令失败不该堵死后续命令。
    _cmdChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// 通用命令：发一条 `stat` 指令并等待手环回包。
  ///
  /// 手环端回包不带请求 id，所以命令必须串行；[accepts] 用来判断哪条
  /// 回包属于本次请求（按 type 精确匹配即可）。
  Future<Map<String, dynamic>> command(
    Map<String, dynamic> payload, {
    required bool Function(Map<String, dynamic> message) accepts,
    Duration timeout = const Duration(seconds: 10),
    bool tolerateTimeout = false,
  }) {
    return _serialize(() async {
      if (_sending) {
        throw const BandBookException('传输进行中，请稍后再试');
      }
      await _ensureConnected();
      final pending = _PendingCommand(accepts);
      _pending.add(pending);
      pending.timer = Timer(timeout, () {
        if (pending.completer.isCompleted) return;
        _pending.remove(pending);
        pending.completer.completeError(
          BandBookException('手环未响应：${payload['stat']}'),
        );
      });
      try {
        await _transmit({'tag': _fileTag, ...payload});
        return await pending.completer.future;
      } on BandBookException {
        if (tolerateTimeout) return const <String, dynamic>{};
        rethrow;
      } finally {
        pending.timer?.cancel();
        _pending.remove(pending);
      }
    });
  }

  /// 推书。[chapters] 为要传的绝对章节索引子集，null 表示整本。
  ///
  /// [loadChapter] 按章序号返回纯文本；传输与取正文重叠，所以传一本
  /// 没下完的书时，手环会边接收边等手机继续下载。
  Future<bool> sendBook({
    required String title,
    required List<String> chapterTitles,
    required Future<String> Function(int index) loadChapter,
    List<int>? chapters,
    int? totalChapters,
    String author = '',
    String summary = '',
    String category = '小说',
    int wordCount = 0,
    bool autoRetry = true,
    int maxRetries = 3,
  }) async {
    if (_sending) return false;
    final all = chapterTitles.length;
    if (all == 0) {
      _fail('这本书没有可传的章节');
      return false;
    }

    final queue = <int>{
      for (final index in chapters ?? List<int>.generate(all, (i) => i))
        if (index >= 0 && index < all) index,
    }.toList()..sort();
    if (queue.isEmpty) {
      _fail('没有需要同步的章节');
      return false;
    }

    _sending = true;
    _cancelled = false;
    _bytesSent = 0;
    _sentSince = DateTime.now();
    _queue = queue;
    _cursor = 0;
    _loader = loadChapter;
    _bodies.clear();
    _inflight.clear();
    _startKeepAlive();

    _set(
      BandTransferState(
        phase: BandTransferPhase.sending,
        device: _state.device,
        bandVersion: _state.bandVersion,
        totalChapters: queue.length,
        label: '准备传输',
      ),
    );

    var attempt = 0;
    try {
      while (true) {
        try {
          await _runSession(
            title: title,
            chapterTitles: chapterTitles,
            bookChapters: totalChapters ?? all,
            author: author,
            summary: summary,
            category: category,
            wordCount: wordCount,
          );
          break;
        } catch (error) {
          if (_cancelled) return false;
          final canRetry = autoRetry && attempt < maxRetries && _cursor < _queue.length;
          if (!canRetry) rethrow;
          attempt += 1;
          _set(
            _state.copyWith(
              label: '连接中断，${retryDelay.inSeconds}s 后从第 ${_cursor + 1} 章续传',
              retries: attempt,
              downloading: false,
            ),
          );
          await Future<void>.delayed(retryDelay);
          if (_cancelled) return false;
          _handshakedReset();
          try {
            await _link.connect();
          } catch (_) {
            // 连不上就再走一轮循环，由 maxRetries 兜底。
          }
        }
      }

      _set(
        _state.copyWith(
          phase: BandTransferPhase.finished,
          fraction: 1,
          label: '传输完成',
          speed: '',
          sentChapters: _queue.length,
          downloading: false,
        ),
      );
      return true;
    } on TimeoutException {
      _fail('手环响应超时：请确认手环未休眠、且与手机保持连接');
      return false;
    } catch (error) {
      if (_cancelled) return false;
      _fail(_describe(error));
      return false;
    } finally {
      _sending = false;
      _loader = null;
      _bodies.clear();
      _inflight.clear();
      _stopKeepAlive();
    }
  }

  /// 一次完整会话：startTransfer → 逐章 → transfer_complete。
  ///
  /// 断线后重新进入时会带着 `_cursor` 接着发，手环端 `startTransfer`
  /// 会重建已落地索引，所以重复发起是安全的。
  Future<void> _runSession({
    required String title,
    required List<String> chapterTitles,
    required int bookChapters,
    required String author,
    required String summary,
    required String category,
    required int wordCount,
  }) async {
    // 先挂等待再发消息：手环的 ready 有可能比 MethodChannel 回执还早到。
    final ready = _readyWait = Completer<void>();
    await _send({
      'tag': _fileTag,
      'stat': 'startTransfer',
      'filename': title,
      'total': bookChapters,
      'wordCount': wordCount,
      'startFrom': _queue[_cursor],
      'chapterIndices': _queue,
      'hasCover': false,
      'author': author,
      'summary': summary,
      'category': category,
    });
    await ready.future.timeout(_readyTimeout);

    while (_cursor < _queue.length) {
      if (_cancelled) throw const BandBookException('已取消传输');
      final index = _queue[_cursor];
      _warmup(_cursor + 1);

      final body = await _bodyOf(index);
      if (body.isEmpty) {
        await _sendChapter(
          index: index,
          name: chapterTitles[index],
          chunks: const <String>[''],
          wordCount: 0,
        );
      } else {
        await _sendChapter(
          index: index,
          name: chapterTitles[index],
          chunks: splitChunks(body),
          wordCount: body.length,
        );
      }

      _bodies.remove(index);
      _cursor += 1;
      _set(
        _state.copyWith(
          fraction: _cursor / _queue.length,
          sentChapters: _cursor,
          label: chapterTitles[index],
          speed: _speedLabel(),
          downloading: _inflight.isNotEmpty,
        ),
      );
    }

    final finish = _finishWait = Completer<void>();
    await _send({'tag': _fileTag, 'stat': 'transfer_complete'});
    await finish.future.timeout(_finishTimeout);
  }

  Future<String> _bodyOf(int index) async {
    final cached = _bodies[index];
    if (cached != null) return cached;
    final loader = _loader;
    if (loader == null) throw const BandBookException('正文来源已失效');
    var future = _inflight[index];
    if (future == null) {
      future = loader(index).then((value) {
        _bodies[index] = value;
        return value;
      });
      _inflight[index] = future;
    }
    try {
      return await future;
    } finally {
      _inflight.remove(index);
    }
  }

  /// 流式预热：发当前章的同时把下一章取下来，下载与传输重叠。
  void _warmup(int cursor) {
    if (cursor >= _queue.length) return;
    final index = _queue[cursor];
    if (_bodies.containsKey(index) || _inflight.containsKey(index)) return;
    final loader = _loader;
    if (loader == null) return;
    unawaited(
      _inflight
          .putIfAbsent(
            index,
            () => loader(index).then((value) {
              _bodies[index] = value;
              _inflight.remove(index);
              return value;
            }),
          )
          .then((_) {
            if (_state.downloading != _inflight.isNotEmpty) {
              _set(_state.copyWith(downloading: _inflight.isNotEmpty));
            }
          })
          .catchError((Object _) {
            // 预取失败不影响流程：真正轮到这一章时会再取一次并如实报错。
          }),
    );
  }

  Future<void> _sendChapter({
    required int index,
    required String name,
    required List<String> chunks,
    required int wordCount,
  }) async {
    for (var chunk = 0; chunk < chunks.length; chunk++) {
      if (_cancelled) throw const BandBookException('已取消传输');
      final wait = _chunkWait = Completer<void>();
      await _send({
        'tag': _fileTag,
        'stat': 'd',
        'count': index,
        'data': jsonEncode({
          'index': index,
          'name': name,
          'content': chunks[chunk],
          'wordCount': wordCount,
          'chunkNum': chunk,
          'totalChunks': chunks.length,
        }),
      });
      _bytesSent += utf8.encode(chunks[chunk]).length;
      final fraction = (_cursor + (chunk + 1) / chunks.length) / math.max(_queue.length, 1);
      _set(
        _state.copyWith(
          fraction: fraction.clamp(0, 1),
          label: '$name (${chunk + 1}/${chunks.length})',
          speed: _speedLabel(),
        ),
      );
      await wait.future.timeout(_chunkTimeout);
    }

    final saved = _chapterWait = Completer<bool>();
    await _send({'tag': _fileTag, 'stat': 'chapter_complete', 'count': index});
    await saved.future.timeout(_chunkTimeout);
  }

  /// 按 UTF-16 码元切片，避免把代理对（emoji）切成半个字符。
  static List<String> splitChunks(String text) {
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = start + chunkSize;
      if (end >= text.length) {
        chunks.add(text.substring(start));
        break;
      }
      final unit = text.codeUnitAt(end);
      if (unit >= 0xDC00 && unit <= 0xDFFF) {
        end -= 1;
      }
      chunks.add(text.substring(start, end));
      start = end;
    }
    return chunks;
  }

  static String normalize(String raw) {
    var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    // 手环端逐行排版，连续空行只会浪费屏幕与传输量。
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  String _speedLabel() {
    final since = _sentSince;
    if (since == null) return '';
    final seconds = DateTime.now().difference(since).inMilliseconds / 1000;
    if (seconds < 1) return '';
    final rate = _bytesSent / seconds;
    if (rate < 1024) return '${rate.toStringAsFixed(0)} B/s';
    if (rate < 1024 * 1024) return '${(rate / 1024).toStringAsFixed(0)} KB/s';
    return '${(rate / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  static String _describe(Object error) {
    if (error is BandBookException) return error.message;
    return '传输失败：$error';
  }

  @override
  void dispose() {
    for (final pending in List<_PendingCommand>.from(_pending)) {
      pending.finish(error: const BandBookException('传输层已释放'));
    }
    _pending.clear();
    _idleTimer?.cancel();
    _handshakeTimer?.cancel();
    _keepAlive?.cancel();
    unawaited(_subscription.cancel());
    unawaited(_linkSubscription.cancel());
    unawaited(_link.dispose());
    super.dispose();
  }
}

/// 一条在途命令：`accepts` 判断哪条回包属于它。
class _PendingCommand {
  _PendingCommand(this.accepts);

  final bool Function(Map<String, dynamic> message) accepts;
  final Completer<Map<String, dynamic>> completer =
      Completer<Map<String, dynamic>>();
  Timer? timer;

  void finish({Map<String, dynamic>? result, Object? error}) {
    timer?.cancel();
    if (completer.isCompleted) return;
    if (error != null) {
      completer.completeError(error);
    } else {
      completer.complete(result ?? const <String, dynamic>{});
    }
  }
}
