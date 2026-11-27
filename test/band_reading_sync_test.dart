import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fqapp/services/band_book/band_book_remote.dart';
import 'package:fqapp/services/band_book/band_reading_sync.dart';
import 'package:fqapp/services/library_store.dart';
import 'package:fqapp/services/shelf_store.dart';
import 'package:fqapp/models/media_item.dart';

/// 替身远端：按预置数据应答 get_reading_data，记录所有 set_reading_data。
class _FakeRemote implements BandReadingPort {
  _FakeRemote(this.data);

  BandReadingData data;
  final List<(String, BandReadingData)> pushed = [];

  @override
  Future<BandReadingData> readingData(String title, {bool soft = true}) async =>
      data;

  @override
  Future<bool> pushReadingData(String title, BandReadingData value) async {
    pushed.add((title, value));
    data = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = LibraryStore.instance;
  late Directory directory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('fqapp-band-sync-test-');
    Hive.init(directory.path);
    await store.init();
    await ShelfStore.instance.init();
  });

  tearDown(() async {
    await ShelfStore.instance.clear();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  /// 「手环进度到手机的阅读进度到底去哪了」的根因回归：
  /// 手机从没读过这本书时历史记录不存在，旧链路走 updateProgress 会把
  /// 写入静默丢弃——同步报告「进度取手环」，书架却毫无变化。
  test('手机没读过时手环进度创建手机历史（不再静默丢弃）', () async {
    final remote = _FakeRemote(
      const BandReadingData(
        chapterIndex: 3,
        offsetInChapter: 500,
        scrollOffset: 1234.5,
      ),
    );
    final sync = BandReadingSync(remote);

    final outcome = await sync.syncBook(
      title: '测试书',
      bookId: 'book-1',
      chapterCount: 10,
    );

    expect(outcome.ok, isTrue);
    expect(outcome.progressSource, 'band');
    expect(outcome.chapterIndex, 3);

    final saved = await store.historyEntry('book-1');
    expect(saved, isNotNull, reason: '手环进度必须落成手机可见的历史记录');
    expect(saved!['episode'], 3);
    expect(saved['progress'], 0.4);
    expect(saved['chapterCount'], 10);
    // offsetInChapter 映射为 textOffset，续读位置不再丢。
    expect(saved['textOffset'], 500);
    expect(saved['position'], 1234.5);
  });

  test('已有历史时按手环进度更新并保留来源字段', () async {
    await store.addHistory({
      'id': 'book-1',
      'kind': 'book',
      'title': '测试书',
      'episode': 1,
      'progress': 0.2,
      'chapterCount': 10,
      'cover': 'https://example/cover.jpg',
      'time': 1000,
    });
    final remote = _FakeRemote(
      const BandReadingData(chapterIndex: 5, offsetInChapter: 80),
    );
    final sync = BandReadingSync(remote);

    final outcome = await sync.syncBook(
      title: '测试书',
      bookId: 'book-1',
      chapterCount: 10,
    );

    expect(outcome.progressSource, 'band');
    final saved = await store.historyEntry('book-1');
    expect(saved!['episode'], 5);
    expect(saved['cover'], 'https://example/cover.jpg',
        reason: '原有字段不能被同步冲掉');
  });

  test('auto 模式同章但手机滚动更远也推回手环', () async {
    await store.addHistory({
      'id': 'book-1',
      'kind': 'book',
      'title': '测试书',
      'episode': 5,
      'progress': 0.55,
      'textOffset': 800,
      'position': 2048.0,
      'time': 1000,
    });
    final remote = _FakeRemote(
      const BandReadingData(chapterIndex: 5, offsetInChapter: 200),
    );
    final sync = BandReadingSync(remote);

    final outcome = await sync.syncBook(
      title: '测试书',
      bookId: 'book-1',
      chapterCount: 10,
    );

    expect(outcome.ok, isTrue);
    expect(remote.pushed, hasLength(1),
        reason: '同章 offset 不同也算差异，旧条件 bandChapter != phoneChapter 会漏推');
    expect(remote.pushed.single.$2.chapterIndex, 5);
    expect(remote.pushed.single.$2.offsetInChapter, 800);
  });

  test('auto 模式手机读得更远时推手环且不回写手机', () async {
    await store.addHistory({
      'id': 'book-1',
      'kind': 'book',
      'title': '测试书',
      'episode': 8,
      'progress': 0.9,
      'textOffset': 10,
      'time': 1000,
    });
    final remote = _FakeRemote(const BandReadingData(chapterIndex: 3));
    final sync = BandReadingSync(remote);

    final outcome = await sync.syncBook(
      title: '测试书',
      bookId: 'book-1',
      chapterCount: 10,
    );

    expect(outcome.progressSource, 'phone');
    expect(remote.pushed, hasLength(1));
    expect(remote.pushed.single.$2.chapterIndex, 8);
    final saved = await store.historyEntry('book-1');
    expect(saved!['episode'], 8);
  });

  test('手环落后时 bandToPhone 不覆盖手机进度', () async {
    await store.addHistory({
      'id': 'book-1',
      'kind': 'book',
      'title': '测试书',
      'episode': 5,
      'progress': 0.6,
      'time': 1000,
    });
    final remote = _FakeRemote(const BandReadingData(chapterIndex: 2));
    final sync = BandReadingSync(remote);

    await sync.syncBook(
      title: '测试书',
      bookId: 'book-1',
      chapterCount: 10,
      progressMode: BandSyncMode.bandToPhone,
    );

    final saved = await store.historyEntry('book-1');
    expect(saved!['episode'], 5);
  });

  test('时长按天取较大值且幂等', () async {
    await store.accumulateReadTime(
      'book-1',
      'book',
      600,
      at: DateTime(2026, 11, 13, 12),
    );
    final remote = _FakeRemote(
      BandReadingData(
        totalSeconds: 1200,
        dailySeconds: {'2026-11-13': 1200},
      ),
    );
    final sync = BandReadingSync(remote);

    var outcome = await sync.syncBook(
      title: '测试书',
      bookId: 'book-1',
      chapterCount: 3,
    );
    expect(outcome.secondsMerged, 600);
    expect(store.readTimeSnapshot()['book-1']?['2026-11-13'], 1200);

    // 再跑一遍不应翻倍。
    outcome = await sync.syncBook(
      title: '测试书',
      bookId: 'book-1',
      chapterCount: 3,
    );
    expect(outcome.secondsMerged, 0);
    expect(store.readTimeSnapshot()['book-1']?['2026-11-13'], 1200);
  });

  test('时长推送不得把刚写的进度覆盖回旧值', () async {
    await store.addHistory({
      'id': 'book-1',
      'kind': 'book',
      'title': '测试书',
      'episode': 8,
      'progress': 0.9,
      'textOffset': 100,
      'time': 1000,
    });
    await store.accumulateReadTime(
      'book-1',
      'book',
      500,
      at: DateTime(2026, 11, 13, 12),
    );
    // 手环进度落后、时长也落后：一次同步里进度推送与时长推送都会触发。
    final remote = _FakeRemote(
      BandReadingData(
        chapterIndex: 3,
        totalSeconds: 100,
        dailySeconds: {'2026-11-13': 100},
      ),
    );
    final sync = BandReadingSync(remote);

    await sync.syncBook(title: '测试书', bookId: 'book-1', chapterCount: 10);

    expect(remote.pushed, hasLength(2), reason: '进度与时长各推一次');
    // 两次推送都必须带着最新进度；旧实现第二次用原始 band 快照把进度回退成 3。
    for (final (_, data) in remote.pushed) {
      expect(data.chapterIndex, 8);
      expect(data.offsetInChapter, 100);
    }
    expect(remote.pushed.last.$2.dailySeconds['2026-11-13'], 500);
  });

  test('手环无任何数据且手机也没读过时不同步也不报错', () async {
    final remote = _FakeRemote(BandReadingData.empty);
    final sync = BandReadingSync(remote);

    final outcome = await sync.syncBook(
      title: '测试书',
      bookId: 'book-1',
      chapterCount: 3,
    );

    expect(outcome.ok, isTrue);
    expect(remote.pushed, isEmpty);
    expect(await store.historyEntry('book-1'), isNull);
  });

  /// 「双端进度同步完全不可用」的根因回归：旧实现在手环无记录时直接早退，
  /// 手机→手环方向的推送永远走不到。
  test('手环无记录但手机有进度时推送手环（不再早退）', () async {
    await store.addHistory({
      'id': 'book-1',
      'kind': 'book',
      'title': '测试书',
      'episode': 4,
      'progress': 0.45,
      'textOffset': 300,
      'time': 1000,
    });
    final remote = _FakeRemote(BandReadingData.empty);
    final sync = BandReadingSync(remote);

    final outcome = await sync.syncBook(
      title: '测试书',
      bookId: 'book-1',
      chapterCount: 10,
    );

    expect(outcome.ok, isTrue);
    expect(remote.pushed, isNotEmpty,
        reason: '手机读过、手环没读过时必须把进度推到手环');
    expect(remote.pushed.first.$2.chapterIndex, 4);
    expect(remote.pushed.first.$2.offsetInChapter, 300);
  });

  /// 「同步的书双端都必须添加到书架」：任一方向同步成功后手机书架必须有这本书。
  test('同步后同步过的书补进手机书架', () async {
    final item = MediaItem(
      id: 'book-1',
      title: '测试书',
      cover: 'https://example/cover.jpg',
      author: '作者',
      badge: '',
      ep: '10',
      kind: 'book',
    );
    final remote = _FakeRemote(
      const BandReadingData(chapterIndex: 2, offsetInChapter: 40),
    );
    final sync = BandReadingSync(remote);

    await sync.syncBook(
      title: '测试书',
      bookId: 'book-1',
      chapterCount: 10,
      item: item,
    );

    expect(ShelfStore.instance.contains('book', 'book-1'), isTrue,
        reason: '同步过的书必须在手机书架上');
  });
}
