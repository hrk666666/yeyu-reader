import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/band_book/band_book_remote.dart';

void main() {
  group('BandReadingData.fromMessage', () {
    test('parses the double-encoded progress and reading time', () {
      final message = <String, dynamic>{
        'type': 'sync_reading_data',
        'filename': '测试书',
        'progress': jsonEncode({
          'chapterIndex': 12,
          'offsetInChapter': 480,
          'scrollOffset': 2048.5,
        }),
        'readingTime': jsonEncode({
          'totalSeconds': 3720,
          'sessionCount': 6,
          'dailySeconds': {'2026-11-12': 600, '2026-11-13': 1200},
          'lastReadDate': '2026-11-13',
          'firstReadDate': '2026-10-01',
        }),
        'bookmarks': [
          {
            'name': '第12章 开头',
            'chapterIndex': 12,
            'offsetInChapter': 0,
            'time': 1763000000000,
          },
        ],
      };

      final data = BandReadingData.fromMessage(message);

      expect(data.chapterIndex, 12);
      expect(data.offsetInChapter, 480);
      expect(data.scrollOffset, 2048.5);
      expect(data.totalSeconds, 3720);
      expect(data.sessionCount, 6);
      expect(data.dailySeconds['2026-11-13'], 1200);
      expect(data.lastReadDate, '2026-11-13');
      expect(data.bookmarks, hasLength(1));
      expect(data.bookmarks.first.chapterIndex, 12);
      expect(data.hasProgress, isTrue);
      expect(data.hasTime, isTrue);
    });

    test('treats null and empty payloads as no data', () {
      final data = BandReadingData.fromMessage({
        'type': 'sync_reading_data',
        'progress': null,
        'readingTime': null,
        'bookmarks': <Object>[],
      });

      expect(data.hasProgress, isFalse);
      expect(data.hasTime, isFalse);
      expect(data.chapterIndex, isNull);
      expect(data.totalSeconds, 0);
      expect(data.bookmarks, isEmpty);
    });

    test('survives a truncated json string from the band', () {
      final data = BandReadingData.fromMessage({
        'progress': '{"chapterIndex": 3, "offsetInCh',
        'readingTime': '',
      });

      expect(data.hasProgress, isFalse);
      expect(data.totalSeconds, 0);
    });

    test('recentDays fills missing days with zero and keeps order', () {
      final data = BandReadingData(
        dailySeconds: {
          '2026-11-08': 60,
          '2026-11-13': 300,
        },
      );

      final days = data.recentDays(DateTime(2026, 11, 13));

      expect(days, hasLength(7));
      // 窗口是 today-6 .. today，即 11-07 .. 11-13。
      expect(days.first, 0);
      expect(days[1], 60);
      expect(days.last, 300);
    });

    test('round-trips through the set_reading_data payloads', () {
      final data = BandReadingData(
        chapterIndex: 7,
        offsetInChapter: 128,
        scrollOffset: 900,
        totalSeconds: 600,
        sessionCount: 2,
        dailySeconds: {'2026-11-13': 600},
        lastReadDate: '2026-11-13',
      );

      final progress = jsonDecode(data.toProgressJson()) as Map<String, dynamic>;
      final time = jsonDecode(data.toReadingTimeJson()) as Map<String, dynamic>;

      expect(progress['chapterIndex'], 7);
      expect(progress['offsetInChapter'], 128);
      expect(progress['scrollOffset'], 900);
      expect(time['totalSeconds'], 600);
      expect((time['dailySeconds'] as Map)['2026-11-13'], 600);
    });
  });

  group('BandStorageInfo', () {
    test('reads the storage_info reply and computes used fraction', () {
      final info = BandStorageInfo.fromMessage({
        'type': 'storage_info',
        'product': 'xiaomi_watch',
        'totalStorage': 1000,
        'availableStorage': 250,
        'usedStorage': 750,
        'reservedStorage': 0,
        'actualAvailable': 250,
      });

      expect(info.product, 'xiaomi_watch');
      expect(info.totalStorage, 1000);
      expect(info.usedFraction, closeTo(0.75, 1e-9));
      expect(BandStorageInfo.formatBytes(1536), '2 KB');
      expect(BandStorageInfo.formatBytes(1536 * 1024), '1.5 MB');
      expect(BandStorageInfo.formatBytes(0), '0 B');
    });
  });
}
