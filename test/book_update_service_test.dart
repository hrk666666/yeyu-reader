import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/services/book_update_service.dart';
import 'package:fqapp/services/chapter_cache_store.dart';
import 'package:fqapp/services/secure_key_provider.dart';

Chapter _chapter(String id) =>
    Chapter(itemId: id, title: '第$id章', volumeName: '卷一');

void main() {
  late Directory dir;
  late SecureKeyProvider keys;
  late ChapterCacheStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fqapp-book-update-');
    Hive.init(dir.path);
    keys = SecureKeyProvider(storage: InMemorySecureKeyStorage());
    store = ChapterCacheStore(keys: keys);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  BookUpdateService service(List<Chapter> network) => BookUpdateService(
    cache: store,
    directory: (_) async => network,
    loader: (chapter) async => '正文-${chapter.itemId}',
  );

  test('目录新增章节识别为更新，未下载的旧章节识别为缺章', () async {
    await store.saveBook(
      CachedBook(id: 'b1', title: '测试书', chapters: [_chapter('1'), _chapter('2')]),
    );
    await store.write(bookId: 'b1', chapterId: '1', title: '第1章', text: '正文-1');

    final info = await service([
      _chapter('1'),
      _chapter('2'),
      _chapter('3'),
      _chapter('4'),
    ]).check('b1');

    expect(info.hasUpdate, isTrue);
    expect(info.fresh.map((c) => c.itemId), ['3', '4']);
    expect(info.gaps.map((c) => c.itemId), ['2']);
    // pending 按网络目录顺序排：缺章 2 在新增 3、4 前面。
    expect(info.pending.map((c) => c.itemId), ['2', '3', '4']);
  });

  test('全部已缓存且无新章节时无更新', () async {
    await store.saveBook(
      CachedBook(id: 'b1', title: '测试书', chapters: [_chapter('1')]),
    );
    await store.write(bookId: 'b1', chapterId: '1', title: '第1章', text: '正文-1');

    final info = await service([_chapter('1')]).check('b1');
    expect(info.hasUpdate, isFalse);
    expect(info.hasPending, isFalse);
    expect(info.badge, isNull);
  });

  test('增量下载补齐待补章节并刷新目录', () async {
    await store.saveBook(
      CachedBook(id: 'b1', title: '测试书', chapters: [_chapter('1')]),
    );
    await store.write(bookId: 'b1', chapterId: '1', title: '第1章', text: '正文-1');

    final svc = service([_chapter('1'), _chapter('2'), _chapter('3')]);
    final info = await svc.check('b1');
    expect(info.pending, hasLength(2));

    await svc.downloadPending(info);

    final cached = await store.savedCatalogue('b1');
    expect(cached!.chapters, hasLength(3), reason: '目录要随下载刷新到最新');
    expect(
      await store.cachedChapterIds('b1'),
      containsAll(['1', '2', '3']),
    );
  });

  test('批量检测单本失败不影响其他书', () async {
    await store.saveBook(
      CachedBook(id: 'ok', title: '好的', chapters: [_chapter('1')]),
    );
    await store.write(bookId: 'ok', chapterId: '1', title: '第1章', text: '正文-1');

    final svc = BookUpdateService(
      cache: store,
      directory: (bookId) async {
        if (bookId == 'bad') throw StateError('接口挂了');
        return [_chapter('1'), _chapter('2')];
      },
      loader: (chapter) async => '正文-${chapter.itemId}',
    );

    final result = await svc.checkAll([
      (id: 'bad', title: '坏书', cover: ''),
      (id: 'ok', title: '好的', cover: ''),
    ]);

    expect(result.keys, ['ok']);
    expect(result['ok']!.fresh.map((c) => c.itemId), ['2']);
  });
}
