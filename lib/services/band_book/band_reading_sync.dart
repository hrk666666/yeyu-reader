import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../library_store.dart';
import '../shelf_store.dart';
import '../../models/media_item.dart';
import 'band_book_remote.dart';

/// 同步方向。与弦电子书手机端的三种模式同名同义：
/// - [auto]：进度取两端更靠后的一个，时长按天取较大值（等价于双向取并集）
/// - [bandToPhone]：手环单向写回手机
/// - [phoneToBand]：手机单向写入手环
enum BandSyncMode { auto, bandToPhone, phoneToBand }

/// 一本书同步完的结果，页面直接拿来拼文案。
@immutable
class BandSyncOutcome {
  const BandSyncOutcome({
    required this.title,
    this.ok = true,
    this.error,
    this.progressSource,
    this.chapterIndex,
    this.secondsMerged = 0,
    this.secondsPushed = 0,
    this.bookmarkCount = 0,
  });

  final String title;
  final bool ok;
  final String? error;

  /// 进度最终来自哪一端：`phone` / `band` / null（都没读过）。
  final String? progressSource;
  final int? chapterIndex;

  /// 从手环补进手机的秒数。
  final int secondsMerged;

  /// 从手机推到手环的秒数。
  final int secondsPushed;
  final int bookmarkCount;

  String get summary {
    if (!ok) return '$title：${error ?? '同步失败'}';
    final parts = <String>[];
    if (chapterIndex != null) {
      final from = progressSource == 'band' ? '手环' : '手机';
      parts.add('进度取$from第 ${chapterIndex! + 1} 章');
    }
    if (secondsMerged > 0) parts.add('补入 ${_minutes(secondsMerged)}');
    if (secondsPushed > 0) parts.add('推送 ${_minutes(secondsPushed)}');
    if (bookmarkCount > 0) parts.add('$bookmarkCount 个书签');
    return parts.isEmpty ? '$title：两端数据一致' : '$title：${parts.join('，')}';
  }

  static String _minutes(int seconds) =>
      seconds < 60 ? '$seconds 秒' : '${(seconds / 60).round()} 分钟';
}

/// 把「手环阅读数据」与「手机本地阅读数据」对齐。
///
/// 手环端没有时间戳（进度只有 `chapterIndex/offsetInChapter`），所以
/// [BandSyncMode.auto] 的进度判定只能按「读得更远」——这与弦电子书手机端
/// 的默认策略一致（它比对的是同一套字段）。
class BandReadingSync {
  BandReadingSync(this.remote);

  final BandReadingPort remote;

  LibraryStore get _store => LibraryStore.instance;

  /// 按 id 找本地历史条目；没有则返回 null（视为「手机没读过」）。
  ///
  /// 命中后返回的表里带 `id` 字段（= 历史 box 的键），回写时必须用这个键，
  /// 不能想当然用 bookId——本地导入书等场景两者可能不同。
  Map<String, dynamic>? _historyFor(String bookId) {
    for (final entry in _store.historySnapshot()) {
      if (entry['id'] == bookId || entry['contentId'] == bookId) return entry;
    }
    return null;
  }

  /// 同步一本书。[title] 是手环上的书名（= 传书时用的 filename），
  /// [bookId] 是手机端书目 id。[item] 用于把同步过的书补进手机书架
  /// （「同步的书双端都必须添加到书架」）。
  Future<BandSyncOutcome> syncBook({
    required String title,
    required String bookId,
    required int chapterCount,
    MediaItem? item,
    BandSyncMode progressMode = BandSyncMode.auto,
    BandSyncMode timeMode = BandSyncMode.auto,
  }) async {
    if (chapterCount <= 0) {
      return BandSyncOutcome(title: title, ok: false, error: '目录为空');
    }

    final band = await remote.readingData(title);

    final history = _historyFor(bookId);
    final phoneChapter = (history?['episode'] as num?)?.toInt();
    final phoneOffset = (history?['textOffset'] as num?)?.toInt() ?? 0;
    final phoneDays = _store.readTimeSnapshot()[bookId] ?? const <String, double>{};

    // 两端什么都没有才是「没得同步」。旧实现在手环无记录时直接早退，
    // 手机→手环方向的推送永远走不到——「双端进度同步完全不可用」的根因。
    final bandEmpty =
        !band.hasProgress &&
        !band.hasTime &&
        band.dailySeconds.isEmpty &&
        band.bookmarks.isEmpty;
    final phoneEmpty = phoneChapter == null && phoneDays.isEmpty;
    if (bandEmpty && phoneEmpty) {
      return BandSyncOutcome(title: title);
    }

    var outcome = BandSyncOutcome(
      title: title,
      bookmarkCount: band.bookmarks.length,
    );

    // ---- 进度 ----
    final bandChapter = band.chapterIndex;
    String? source;
    var targetChapter = phoneChapter;
    var applyToPhone = false;
    var pushToBand = false;

    if (bandChapter != null || phoneChapter != null) {
      final bandAhead = _isAhead(
        bandChapter: bandChapter,
        bandOffset: band.offsetInChapter,
        phoneChapter: phoneChapter,
        phoneOffset: phoneOffset,
      );
      // 两端读过但位置不同才算「有差异」；完全一致时跳过回写。
      final differs =
          bandChapter != phoneChapter || band.offsetInChapter != phoneOffset;
      switch (progressMode) {
        case BandSyncMode.bandToPhone:
          applyToPhone = bandChapter != null && bandAhead;
        case BandSyncMode.phoneToBand:
          // 单向强推：只要手环与手机不一致就以手机为准。
          pushToBand = phoneChapter != null && differs;
        case BandSyncMode.auto:
          applyToPhone = bandChapter != null && bandAhead;
          // 手机读得更远时也要推回手环——同章但滚动更远同样算更远。
          pushToBand = phoneChapter != null && !bandAhead && differs;
      }
    }

    if (applyToPhone && bandChapter != null) {
      final clamped = bandChapter.clamp(0, chapterCount - 1);
      final fraction = ((clamped + 1) / chapterCount).clamp(0.0, 1.0);
      await _writePhoneProgress(
        history: history,
        bookId: bookId,
        title: title,
        episode: clamped,
        fraction: fraction,
        chapterCount: chapterCount,
        textOffset: band.offsetInChapter,
        position: band.scrollOffset,
        item: item,
      );
      targetChapter = clamped;
      source = 'band';
    } else if (phoneChapter != null) {
      targetChapter = phoneChapter;
      source = 'phone';
    }

    // 手环侧待写快照：进度与时长是两次推送，必须在同一条累计快照上
    // 递进，否则后一次会把前一次的字段覆盖回旧值（进度被时长推送回退）。
    var remoteData = band;

    if (pushToBand && phoneChapter != null) {
      remoteData = remoteData.copyWith(
        chapterIndex: phoneChapter,
        offsetInChapter: phoneOffset,
        scrollOffset: (history?['position'] as num?)?.toDouble() ??
            remoteData.scrollOffset,
      );
      final ok = await remote.pushReadingData(title, remoteData);
      if (!ok) {
        return BandSyncOutcome(
          title: title,
          ok: false,
          error: '写入手环进度失败',
        );
      }
      // 同步的书双端都必须添加到书架：手机侧补架（手环侧由传输/同步
      // 命令在手环端写入 bookshelf.json，双端并集）。
      await _ensureShelf(item, bookId: bookId, title: title);
    }

    // ---- 阅读时长（按天取较大值）----
    var mergedSeconds = 0;
    var pushedSeconds = 0;

    if (band.hasTime || phoneDays.isNotEmpty) {
      final bandDays = band.dailySeconds;
      final allDays = <String>{...bandDays.keys, ...phoneDays.keys};

      if (timeMode != BandSyncMode.phoneToBand) {
        // 手环 → 手机：只补「手环比手机多」的差额，逐日累加保证幂等。
        for (final day in allDays) {
          final bandSeconds = bandDays[day] ?? 0;
          final phoneSeconds = (phoneDays[day] ?? 0).round();
          final delta = bandSeconds - phoneSeconds;
          if (delta <= 0) continue;
          await _store.accumulateReadTime(
            bookId,
            'book',
            delta.toDouble(),
            at: _parseDay(day),
          );
          mergedSeconds += delta;
        }
      }

      if (timeMode != BandSyncMode.bandToPhone) {
        final merged = Map<String, int>.from(bandDays);
        var changed = false;
        for (final entry in phoneDays.entries) {
          final phoneSeconds = entry.value.round();
          if (phoneSeconds > (merged[entry.key] ?? 0)) {
            merged[entry.key] = phoneSeconds;
            changed = true;
          }
        }
        if (changed) {
          final total = merged.values.fold<int>(0, (sum, value) => sum + value);
          remoteData = remoteData.copyWith(
            totalSeconds: total,
            dailySeconds: merged,
            sessionCount: math.max(remoteData.sessionCount, merged.length),
          );
          final ok = await remote.pushReadingData(title, remoteData);
          if (ok) {
            pushedSeconds = total - band.totalSeconds;
            if (pushedSeconds < 0) pushedSeconds = 0;
          }
        }
      }
    }

    outcome = BandSyncOutcome(
      title: title,
      progressSource: source,
      chapterIndex: targetChapter,
      secondsMerged: mergedSeconds,
      secondsPushed: pushedSeconds,
      bookmarkCount: band.bookmarks.length,
    );
    return outcome;
  }

  /// 批量同步。[onProgress] 每完成一本回调一次（当前序号从 0 起）。
  Future<List<BandSyncOutcome>> syncAll(
    List<BandSyncTarget> targets, {
    BandSyncMode progressMode = BandSyncMode.auto,
    BandSyncMode timeMode = BandSyncMode.auto,
    void Function(int done, int total, BandSyncOutcome outcome)? onProgress,
    bool Function()? cancelled,
  }) async {
    final results = <BandSyncOutcome>[];
    for (var i = 0; i < targets.length; i++) {
      if (cancelled?.call() ?? false) break;
      final target = targets[i];
      final outcome = await syncBook(
        title: target.title,
        bookId: target.bookId,
        chapterCount: target.chapterCount,
        item: target.item,
        progressMode: progressMode,
        timeMode: timeMode,
      );
      results.add(outcome);
      onProgress?.call(i + 1, targets.length, outcome);
    }
    return results;
  }

  /// 把手环进度落进手机历史。
  ///
  /// 关键修复：`LibraryStore.updateProgress` 在记录不存在时会静默丢弃写入，
  /// 而「手机从没读过这本书」恰恰是手环进度最常见的归宿——进度就这样
  /// 消失了。这里改为「合并整条快照 + addHistory upsert」：
  /// - 记录存在：保留原字段（封面 / 来源标记），按手环进度更新；
  /// - 记录不存在：直接创建一条完整历史，书架立刻可见。
  /// 顺带把 `offsetInChapter` 映射为 `textOffset`，续读位置不再丢。
  Future<void> _writePhoneProgress({
    required Map<String, dynamic>? history,
    required String bookId,
    required String title,
    required int episode,
    required double fraction,
    required int chapterCount,
    required int textOffset,
    required double position,
    MediaItem? item,
  }) async {
    // 回写必须用历史 box 的真实键（_historyFor 命中时可能与 bookId 不同）。
    final id = history?['id']?.toString() ?? bookId;
    final merged = <String, dynamic>{
      ...?history,
      'id': id,
      'kind': history?['kind'] ?? 'book',
      'title': title,
      'bookId': bookId,
      'episode': episode,
      'progress': fraction,
      'chapterCount': chapterCount,
      'textOffset': textOffset,
      'position': position,
      'time': DateTime.now().millisecondsSinceEpoch,
    };
    await _store.addHistory(merged);
    // 同步的书双端都必须添加到书架：手环进度落进手机时同步补架。
    await _ensureShelf(item, bookId: bookId, title: title);
  }

  /// 同步过的书必须出现在手机书架上（幂等：已在架则不动）。
  Future<void> _ensureShelf(MediaItem? item, {required String bookId, required String title}) async {
    final target = item ??
        MediaItem(
          id: bookId,
          title: title,
          cover: '',
          author: '',
          badge: '',
          ep: '',
          kind: 'book',
        );
    if (ShelfStore.instance.containsItem(target)) return;
    await ShelfStore.instance.add(target);
  }

  static bool _isAhead({
    required int? bandChapter,
    required int bandOffset,
    required int? phoneChapter,
    required int phoneOffset,
  }) {
    if (bandChapter == null) return false;
    if (phoneChapter == null) return true;
    if (bandChapter != phoneChapter) return bandChapter > phoneChapter;
    return bandOffset > phoneOffset;
  }

  static DateTime _parseDay(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return DateTime.now();
    final year = int.tryParse(parts[0]) ?? 1970;
    final month = int.tryParse(parts[1]) ?? 1;
    final day = int.tryParse(parts[2]) ?? 1;
    return DateTime(year, month, day, 12);
  }
}

/// 一本书在同步批次里的定位信息。
@immutable
class BandSyncTarget {
  const BandSyncTarget({
    required this.title,
    required this.bookId,
    required this.chapterCount,
    this.item,
  });

  /// 手环上的书名。
  final String title;

  /// 手机端书目 id（阅读进度 / 时长按这个键存）。
  final String bookId;
  final int chapterCount;

  /// 对应的书架条目；同步过的书补进手机书架时用。
  final MediaItem? item;
}
