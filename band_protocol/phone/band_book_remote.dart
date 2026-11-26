import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'band_book_link.dart';
import 'band_book_transfer.dart';

/// 手环上某本书的书签（与手环端 `progress.bookmarks[]` 同构）。
@immutable
class BandBookmark {
  const BandBookmark({
    required this.name,
    this.chapterIndex,
    this.offsetInChapter = 0,
    this.time = 0,
  });

  final String name;
  final int? chapterIndex;
  final int offsetInChapter;
  final int time;

  static BandBookmark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final chapter = raw['chapterIndex'];
    return BandBookmark(
      name: raw['name']?.toString() ?? '书签',
      chapterIndex: chapter is num ? chapter.toInt() : null,
      offsetInChapter: (raw['offsetInChapter'] as num?)?.toInt() ?? 0,
      time: (raw['time'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'chapterIndex': chapterIndex,
    'offsetInChapter': offsetInChapter,
    'time': time,
  };
}

/// 手环端一本书的阅读数据：进度 + 时长 + 书签。
@immutable
class BandReadingData {
  const BandReadingData({
    this.chapterIndex,
    this.offsetInChapter = 0,
    this.scrollOffset = 0,
    this.totalSeconds = 0,
    this.sessionCount = 0,
    this.dailySeconds = const <String, int>{},
    this.bookmarks = const <BandBookmark>[],
    this.lastReadDate,
    this.firstReadDate,
  });

  static const BandReadingData empty = BandReadingData();

  /// 手环端读到的章节索引；null 表示这本书在手环上还没读过。
  final int? chapterIndex;
  final int offsetInChapter;
  final double scrollOffset;

  /// 累计阅读秒数（手环端 `readingTime.totalSeconds`）。
  final int totalSeconds;
  final int sessionCount;

  /// 按天分桶的秒数，key 为 `yyyy-MM-dd`。
  final Map<String, int> dailySeconds;
  final List<BandBookmark> bookmarks;
  final String? lastReadDate;
  final String? firstReadDate;

  bool get hasProgress => chapterIndex != null;
  bool get hasTime => totalSeconds > 0;

  /// 最近 7 天的阅读秒数（按日期升序，缺失补 0）。
  List<int> recentDays([DateTime? now]) {
    final today = now ?? DateTime.now();
    return List<int>.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      final key =
          '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
      return dailySeconds[key] ?? 0;
    });
  }

  BandReadingData copyWith({
    int? chapterIndex,
    int? offsetInChapter,
    double? scrollOffset,
    int? totalSeconds,
    int? sessionCount,
    Map<String, int>? dailySeconds,
    List<BandBookmark>? bookmarks,
    String? lastReadDate,
    String? firstReadDate,
  }) {
    return BandReadingData(
      chapterIndex: chapterIndex ?? this.chapterIndex,
      offsetInChapter: offsetInChapter ?? this.offsetInChapter,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      sessionCount: sessionCount ?? this.sessionCount,
      dailySeconds: dailySeconds ?? this.dailySeconds,
      bookmarks: bookmarks ?? this.bookmarks,
      lastReadDate: lastReadDate ?? this.lastReadDate,
      firstReadDate: firstReadDate ?? this.firstReadDate,
    );
  }

  /// 解析手环端 `sync_reading_data` 回包。`progress` 与 `readingTime`
  /// 都是「JSON 字符串套在 JSON 里」，要二次解析。
  static BandReadingData fromMessage(Map<String, dynamic> message) {
    var chapterIndex = <String, dynamic>{};
    var time = <String, dynamic>{};

    final rawProgress = message['progress'];
    if (rawProgress is String && rawProgress.isNotEmpty) {
      final decoded = _tryDecode(rawProgress);
      if (decoded != null) chapterIndex = decoded;
    } else if (rawProgress is Map) {
      chapterIndex = Map<String, dynamic>.from(rawProgress);
    }

    final rawTime = message['readingTime'];
    if (rawTime is String && rawTime.isNotEmpty) {
      final decoded = _tryDecode(rawTime);
      if (decoded != null) time = decoded;
    } else if (rawTime is Map) {
      time = Map<String, dynamic>.from(rawTime);
    }

    final days = <String, int>{};
    final rawDays = time['dailySeconds'];
    if (rawDays is Map) {
      rawDays.forEach((key, value) {
        if (value is num) days[key.toString()] = value.toInt();
      });
    }

    final marks = <BandBookmark>[];
    final rawMarks = message['bookmarks'];
    if (rawMarks is List) {
      for (final item in rawMarks) {
        final mark = BandBookmark.fromJson(item);
        if (mark != null) marks.add(mark);
      }
    }

    final chapter = chapterIndex['chapterIndex'];
    return BandReadingData(
      chapterIndex: chapter is num ? chapter.toInt() : null,
      offsetInChapter: (chapterIndex['offsetInChapter'] as num?)?.toInt() ?? 0,
      scrollOffset: (chapterIndex['scrollOffset'] as num?)?.toDouble() ?? 0,
      totalSeconds: (time['totalSeconds'] as num?)?.toInt() ?? 0,
      sessionCount: (time['sessionCount'] as num?)?.toInt() ?? 0,
      dailySeconds: days,
      bookmarks: marks,
      lastReadDate: time['lastReadDate']?.toString(),
      firstReadDate: time['firstReadDate']?.toString(),
    );
  }

  /// 生成 `set_reading_data` 的 progress 载荷。
  String toProgressJson() => jsonEncode({
    'chapterIndex': chapterIndex,
    'offsetInChapter': offsetInChapter,
    'scrollOffset': scrollOffset,
  });

  /// 生成 `set_reading_data` 的 readingTime 载荷。
  String toReadingTimeJson() => jsonEncode({
    'totalSeconds': totalSeconds,
    'sessionCount': sessionCount,
    'sessions': const <Object>[],
    'dailySeconds': dailySeconds,
    'lastReadDate': lastReadDate,
    'firstReadDate': firstReadDate,
  });

  static Map<String, dynamic>? _tryDecode(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 手环端可能返回空串或半截 JSON，按「无数据」处理。
    }
    return null;
  }
}

/// 手环剩余空间。
@immutable
class BandStorageInfo {
  const BandStorageInfo({
    this.product,
    this.totalStorage = 0,
    this.availableStorage = 0,
    this.reservedStorage = 0,
    this.usedStorage = 0,
    this.actualAvailable = 0,
  });

  static const BandStorageInfo empty = BandStorageInfo();

  final String? product;
  final int totalStorage;
  final int availableStorage;
  final int reservedStorage;
  final int usedStorage;
  final int actualAvailable;

  double get usedFraction =>
      totalStorage <= 0 ? 0 : (1 - availableStorage / totalStorage).clamp(0, 1);

  static BandStorageInfo fromMessage(Map<String, dynamic> message) {
    int pick(String key) => (message[key] as num?)?.toInt() ?? 0;
    return BandStorageInfo(
      product: message['product']?.toString(),
      totalStorage: pick('totalStorage'),
      availableStorage: pick('availableStorage'),
      reservedStorage: pick('reservedStorage'),
      usedStorage: pick('usedStorage'),
      actualAvailable: pick('actualAvailable'),
    );
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 同步只依赖「读 / 写阅读数据」两条命令。抽成窄接口便于测试注入替身，
/// [BandReadingSync] 面向它编程而不是面向整条传输链。
abstract interface class BandReadingPort {
  Future<BandReadingData> readingData(String title, {bool soft = true});

  Future<bool> pushReadingData(String title, BandReadingData data);
}

/// 手环端一套命令。所有方法都建立在 [BandBookTransfer.command] 之上，
/// 复用传输层已有的握手 / 看门狗 / 保活，不另开一条链路。
class BandBookRemote implements BandReadingPort {
  BandBookRemote(this._transfer);

  final BandBookTransfer _transfer;

  /// 手环上这本书已落地的章节和封面状态。
  Future<BandBookStatus> status(String title) => _transfer.fetchStatus(title);

  /// 拉取阅读进度 + 时长 + 书签。
  @override
  Future<BandReadingData> readingData(String title, {bool soft = true}) async {
    try {
      final reply = await _transfer.command(
        {'stat': 'get_reading_data', 'filename': title},
        accepts: (message) =>
            message['type'] == 'sync_reading_data' ||
            (message['type'] == 'error'),
        timeout: const Duration(seconds: 10),
        tolerateTimeout: soft,
      );
      if (reply.isEmpty) return BandReadingData.empty;
      return BandReadingData.fromMessage(reply);
    } on BandBookException {
      if (soft) return BandReadingData.empty;
      rethrow;
    }
  }

  /// 把手环上的阅读数据回写到手环（进度 / 时长 / 书签任一）。
  @override
  Future<bool> pushReadingData(String title, BandReadingData data) async {
    try {
      await _transfer.command(
        {
          'stat': 'set_reading_data',
          'filename': title,
          'progress': data.toProgressJson(),
          'readingTime': data.toReadingTimeJson(),
          'bookmarks': data.bookmarks.map((b) => b.toJson()).toList(),
        },
        accepts: (message) => message['type'] == 'success',
        timeout: const Duration(seconds: 10),
      );
      return true;
    } on BandBookException {
      return false;
    }
  }

  /// 手环存储占用。
  Future<BandStorageInfo> storage({bool soft = true}) async {
    try {
      final reply = await _transfer.command(
        {'stat': 'get_storage_info'},
        accepts: (message) => message['type'] == 'storage_info',
        timeout: const Duration(seconds: 8),
        tolerateTimeout: soft,
      ).timeout(const Duration(seconds: 15));
      if (reply.isEmpty) return BandStorageInfo.empty;
      return BandStorageInfo.fromMessage(reply);
    } catch (_) {
      // 任何异常（含超时、解析失败）都不能外泄：上层 UI 靠它收「读取中」状态。
      if (soft) return BandStorageInfo.empty;
      rethrow;
    }
  }

  /// 删除手环上的整本书（含目录、封面、书架记录）。
  Future<bool> deleteBook(String title) async {
    try {
      await _transfer.command(
        {'stat': 'delete_book', 'filename': title},
        accepts: (message) => message['type'] == 'success',
        timeout: const Duration(seconds: 15),
      );
      return true;
    } on BandBookException {
      return false;
    }
  }

  /// 删除手环上指定章节（用于「只留前 N 章」这类清理）。
  Future<int> deleteChapters(String title, List<int> indices) async {
    if (indices.isEmpty) return 0;
    try {
      final reply = await _transfer.command(
        {
          'stat': 'delete_chapters',
          'filename': title,
          'chapterIndices': indices,
        },
        accepts: (message) => message['type'] == 'success',
        timeout: Duration(seconds: 10 + indices.length * 2),
      );
      return (reply['count'] as num?)?.toInt() ?? indices.length;
    } on BandBookException {
      return 0;
    }
  }

  /// 更新手环上这本书的元信息（作者、简介、分类、连载状态）。
  Future<bool> updateBookInfo(
    String title, {
    String? author,
    String? summary,
    String? category,
    String? localCategory,
    String? bookStatus,
  }) async {
    try {
      await _transfer.command(
        {
          'stat': 'update_book_info',
          'filename': title,
          'author': ?author,
          'summary': ?summary,
          'category': ?category,
          'localCategory': ?localCategory,
          'bookStatus': ?bookStatus,
        },
        accepts: (message) => message['type'] == 'book_info_updated',
        timeout: const Duration(seconds: 10),
      );
      return true;
    } on BandBookException {
      return false;
    }
  }

  /// 读手环端阅读器设置（字号、字体、边距、翻页方式、自动阅读…）。
  Future<Map<String, dynamic>> settings(List<String> keys) async {
    if (keys.isEmpty) return const <String, dynamic>{};
    try {
      final reply = await _transfer.command(
        {'stat': 'get_settings', 'keys': keys},
        accepts: (message) => message['type'] == 'settings_data',
        timeout: const Duration(seconds: 8),
      );
      final raw = reply['settings'];
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return const <String, dynamic>{};
    } on BandBookException {
      return const <String, dynamic>{};
    }
  }

  /// 写手环端阅读器设置。手环端会把值 `toString()` 后存字符串。
  Future<bool> applySettings(Map<String, dynamic> values) async {
    if (values.isEmpty) return false;
    try {
      await _transfer.command(
        {'stat': 'set_settings', 'settings': values},
        accepts: (message) => message['type'] == 'success',
        timeout: const Duration(seconds: 10),
      );
      return true;
    } on BandBookException {
      return false;
    }
  }
}
