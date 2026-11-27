import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';

import '../imported_book_store.dart';
import 'kosync_client.dart';
import 'kosync_preferences.dart';
import 'kosync_progress.dart';

/// 远端进度及其解析结果。
class KosyncRemoteProgress {
  const KosyncRemoteProgress({required this.record, required this.position});

  /// 服务端存的原始记录。
  final KosyncProgressRecord record;

  /// 解析出来的目标位置。
  final KosyncRemotePosition position;

  /// 服务端记录的时间（秒）。
  int get timestamp => record.timestamp;
}

/// kosync 同步的编排层。
///
/// 负责三件事：
/// 1. 给每本书算一个**跨设备稳定**的 `document` 标识；
/// 2. 把页屿的阅读进度翻译成协议里的 `progress` / `percentage` 并推送；
/// 3. 拉回远端进度并翻译成页屿能用的目标位置。
///
/// 协议本身不做冲突合并（服务端是纯 last-write-wins），所以「远端还是本地
/// 更新」由调用方拿本地记录的保存时间与远端 `timestamp` 比较后决定。
class KosyncSyncService {
  KosyncSyncService({
    KosyncClient? client,
    KosyncPreferences? preferences,
    ImportedBookStore? bookStore,
  }) : _preferences = preferences ?? KosyncPreferences.instance,
       _bookStore = bookStore ?? ImportedBookStore.instance {
    _client = client;
  }

  /// 全局实例。阅读器与设置页共用一份配置。
  static final KosyncSyncService instance = KosyncSyncService();

  /// 测试用：替换客户端的构造方式。
  ///
  /// 阅读器走的是全局实例，测试要断言它发出的请求只能从这里换掉传输层，
  /// 不用改生产的调用路径。
  @visibleForTesting
  static KosyncClient Function()? clientFactory;

  final KosyncPreferences _preferences;
  final ImportedBookStore _bookStore;
  KosyncClient? _client;

  /// 书籍标识缓存：算一次内容指纹要读文件，没必要每次同步都重算。
  static final Map<String, String> _documentIds = <String, String>{};

  /// 推送节流间隔。翻页很频繁，不必每一页都打一次网络。
  static const Duration pushInterval = Duration(seconds: 20);

  final Map<String, DateTime> _lastPushAt = <String, DateTime>{};

  /// 同步是否可用（已启用且凭据齐全）。
  bool get isEnabled => _preferences.isConfigured;

  /// 当前使用的客户端。
  ///
  /// [requireEnabled] 区分两类调用：「同步读写」必须先打开开关；而「测试
  /// 连接」「注册账号」只是拿凭据去验一下服务器，用户完全可能还没启用就
  /// 想先试试通不通，用 [KosyncPreferences.hasCredentials] 判断即可。
  KosyncClient? client({bool requireEnabled = true}) {
    if (_client != null) return _client;
    final ready = requireEnabled
        ? _preferences.isConfigured
        : _preferences.hasCredentials;
    if (!ready) return null;
    final factory = clientFactory;
    if (factory != null) return _client = factory();
    return _client = KosyncClient(
      baseUrl: _preferences.serverUrl.value,
      username: _preferences.username.value,
      authKey: _preferences.authKey.value,
    );
  }

  /// 丢掉缓存的客户端（改配置后调用）。
  void invalidate() {
    _client?.close();
    _client = null;
    _documentIds.clear();
    _lastPushAt.clear();
  }

  /// 计算一本书的 `document` 标识。
  ///
  /// 服务端只接受 `[A-Za-z0-9_]`，所以这里一律给 32 位十六进制的 MD5。
  ///
  /// 标识必须**跨设备一致**：同一本书在两台设备上要算出同一个值，否则两端
  /// 会把进度记到两条不同的记录里，永远同步不上。
  ///
  /// - 本地导入的书：页屿的本地 id 含随机盐（每台设备导入同一本书得到的
  ///   id 也不同），不能直接用。改为按「书名 + 作者 + 若干章节的正文摘要」
  ///   算指纹——正文相同则指纹相同，换设备导入同一本 EPUB 结果一致。
  /// - 网络小说：直接用书籍 id 派生，页屿的书架就是以 id 为键的。
  Future<String> documentIdFor(String bookId) async {
    final cached = _documentIds[bookId];
    if (cached != null) return cached;
    final id = await _computeDocumentId(bookId);
    _documentIds[bookId] = id;
    return id;
  }

  Future<String> _computeDocumentId(String bookId) async {
    if (ImportedBookStore.isLocalBookId(bookId)) {
      final fingerprint = await _localBookFingerprint(bookId);
      if (fingerprint != null) return fingerprint;
      // 读不出正文时退回 id 派生：同一台设备内仍然稳定，跨设备可能不一致，
      // 但好过整条同步链路停摆。
    }
    return _md5('yeyu:book:$bookId');
  }

  Future<String?> _localBookFingerprint(String bookId) async {
    final book = await _bookStore.book(bookId);
    if (book == null) return null;
    final chapters = book.chapters;
    if (chapters.isEmpty) {
      return _md5('yeyu:local:${book.title}|${book.author}');
    }
    // 取首、中、尾三章：只看正文足以把同名同作者的不同版本区分开，同时
    // 不必读完整本书。
    final indexes = <int>{
      0,
      chapters.length ~/ 2,
      chapters.length - 1,
    };
    final parts = <String>[];
    for (final index in indexes) {
      if (index < 0 || index >= chapters.length) continue;
      try {
        final text = await _bookStore.chapterText(bookId, chapters[index].itemId);
        parts.add(_md5(text));
      } catch (_) {
        // A missing chapter file must not break the fingerprint; the title and
        // author still separate different books.
      }
    }
    if (parts.isEmpty) {
      return _md5('yeyu:local:${book.title}|${book.author}');
    }
    return _md5('yeyu:local:${book.title}|${book.author}|${parts.join('|')}');
  }

  static String _md5(String value) =>
      md5.convert(utf8.encode(value)).toString();

  /// 推送当前进度。
  ///
  /// [chapterIndex] 是章节序号，[textOffset] 是章节内的字符偏移，
  /// [percentage] 是全书进度（0 到 1）。
  ///
  /// 返回 true 表示真的发出去了；返回 false 表示被节流跳过或未启用。
  Future<bool> pushProgress({
    required String bookId,
    required int chapterIndex,
    required int textOffset,
    required double percentage,
    bool force = false,
  }) async {
    // 同步总闸：没打开开关就不发请求，哪怕客户端已经就绪。
    if (!_preferences.isConfigured) return false;
    final kosyncClient = client();
    if (kosyncClient == null) return false;
    if (!force) {
      final last = _lastPushAt[bookId];
      final now = DateTime.now();
      if (last != null && now.difference(last) < pushInterval) return false;
      _lastPushAt[bookId] = now;
    }
    try {
      await kosyncClient.pushProgress(
        document: await documentIdFor(bookId),
        progress: KosyncProgress.encode(
          chapterIndex: chapterIndex,
          textOffset: textOffset,
        ),
        percentage: percentage,
        device: _preferences.deviceName.value,
        deviceId: _preferences.deviceId.value,
      );
      return true;
    } on KosyncException {
      // A failed push must never interrupt reading; the next one retries.
      _lastPushAt.remove(bookId);
      return false;
    }
  }

  /// 拉取远端进度。
  ///
  /// [chapterCount] 是本地章节总数，用来在无法精确解析远端定位串时按百分比
  /// 折算章节。
  Future<KosyncRemoteProgress?> pullProgress(
    String bookId, {
    required int chapterCount,
  }) async {
    if (!_preferences.isConfigured) return null;
    final kosyncClient = client();
    if (kosyncClient == null) return null;
    try {
      final doc = await documentIdFor(bookId);
      final record = await kosyncClient.fetchProgress(doc);
      if (record == null) return null;
      final position = KosyncProgress.decode(
        record.progress,
        chapterCount: chapterCount,
        percentage: record.percentage,
      );
      if (position == null) return null;
      return KosyncRemoteProgress(record: record, position: position);
    } on KosyncException {
      // Offline or unauthorized: the reader keeps its local position.
      return null;
    }
  }

  /// 校验凭据。成功返回 true；失败抛出 [KosyncException]。
  Future<bool> verifyCredentials() async {
    if (!_preferences.hasCredentials) {
      throw const KosyncException(0, '请先填写服务器地址、账号与口令');
    }
    final kosyncClient = client(requireEnabled: false);
    if (kosyncClient == null) {
      throw const KosyncException(0, '请先填写服务器地址、账号与口令');
    }
    return kosyncClient.authenticate();
  }

  /// 在服务器上注册当前账号。已存在同名账号时抛出 code 2002。
  Future<void> registerAccount() async {
    if (!_preferences.hasCredentials) {
      throw const KosyncException(0, '请先填写服务器地址、账号与口令');
    }
    final kosyncClient = client(requireEnabled: false);
    if (kosyncClient == null) {
      throw const KosyncException(0, '请先填写服务器地址、账号与口令');
    }
    await kosyncClient.createUser();
  }
}
