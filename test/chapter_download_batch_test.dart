import 'package:flutter_test/flutter_test.dart';

import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/services/chapter_cache_store.dart';
import 'package:fqapp/services/chapter_download.dart';

/// 批量取文路径：一次请求拿回整批、缺章回退单章、整批失败二分重试。
class _FakeChapterCache implements ChapterCache {
  final writes = <String>[];

  @override
  int get chapterCapacity => 500;

  @override
  Future<String?> read({
    required String bookId,
    required String chapterId,
  }) async => null;

  @override
  Future<void> write({
    required String bookId,
    required String chapterId,
    required String title,
    required String text,
    bool pinned = false,
  }) async {
    writes.add(chapterId);
  }

  @override
  Future<void> saveBook(CachedBook book) async {}

  @override
  Future<Set<String>> cachedChapterIds(String bookId) async => {};

  @override
  Future<CachedBook?> cachedBook(String bookId) async => null;

  @override
  Future<CachedBook?> savedCatalogue(String bookId) async => null;
}

CachedBook _book(int count) => CachedBook(
  id: 'book-1',
  title: '书',
  chapters: [
    for (var i = 1; i <= count; i++)
      Chapter(itemId: 'c$i', title: '第$i章', volumeName: ''),
  ],
);

void main() {
  test('整批一次取回：只发一次批量请求，不碰单章接口', () async {
    final cache = _FakeChapterCache();
    final batchCalls = <List<String>>[];
    final singleCalls = <String>[];
    final download = ChapterDownload(
      cache: cache,
      book: _book(5),
      loader: (chapter) async {
        singleCalls.add(chapter.itemId);
        return '单章 ${chapter.itemId}';
      },
      batchLoader: (ids) async {
        batchCalls.add(ids);
        return {for (final id in ids) id: '批量 $id'};
      },
    );
    addTearDown(download.dispose);

    await download.start(startIndex: 0, count: 5);

    expect(batchCalls, hasLength(1));
    expect(batchCalls.single, ['c1', 'c2', 'c3', 'c4', 'c5']);
    expect(singleCalls, isEmpty);
    expect(cache.writes, ['c1', 'c2', 'c3', 'c4', 'c5']);
    expect(download.value.completed, 5);
  });

  test('批量里缺章：缺的那章回退单章接口，其余不重复请求', () async {
    final cache = _FakeChapterCache();
    final singleCalls = <String>[];
    final download = ChapterDownload(
      cache: cache,
      book: _book(4),
      loader: (chapter) async {
        singleCalls.add(chapter.itemId);
        return '单章 ${chapter.itemId}';
      },
      batchLoader: (ids) async => {
        for (final id in ids)
          if (id != 'c3') id: '批量 $id',
      },
    );
    addTearDown(download.dispose);

    await download.start(startIndex: 0, count: 4);

    expect(singleCalls, ['c3']);
    expect(cache.writes, ['c1', 'c2', 'c3', 'c4']);
    expect(download.value.completed, 4);
    expect(download.value.message, isNotNull);
  });

  test('整批失败：二分重试后整本仍然落盘', () async {
    final cache = _FakeChapterCache();
    var attempts = 0;
    final download = ChapterDownload(
      cache: cache,
      book: _book(4),
      loader: (chapter) async => '单章 ${chapter.itemId}',
      batchLoader: (ids) async {
        attempts++;
        // 第一次整批失败；之后单章的小批成功。
        if (attempts == 1) throw StateError('上游 500');
        return {for (final id in ids) id: '批量 $id'};
      },
    );
    addTearDown(download.dispose);

    await download.start(startIndex: 0, count: 4);

    // 1 次整批 + 2 次半批 = 3 次。
    expect(attempts, 3);
    expect(cache.writes, ['c1', 'c2', 'c3', 'c4']);
    expect(download.value.completed, 4);
    expect(download.value.running, isFalse);
  });
}
