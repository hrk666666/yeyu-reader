import 'package:flutter/foundation.dart';

import '../models/media_item.dart';
import 'api_client.dart';
import 'book_updates.dart';
import 'chapter_cache_store.dart';
import 'chapter_download.dart';

/// 一本缓存书相对网络目录的更新检测结果。
///
/// 「更新」与「缺章」分开计：目录新增的章节是更新；目录里早就有、但
/// 从来没下载过的是缺章。两者都要补齐，只是文案上分开说，用户才知道
/// 是作者更了新还是自己缓存没下完。
@immutable
class BookUpdateInfo {
  const BookUpdateInfo({
    required this.bookId,
    required this.title,
    required this.cover,
    required this.cachedChapterList,
    required this.downloadedCount,
    required this.networkChapters,
    required this.fresh,
    required this.gaps,
  });

  final String bookId;
  final String title;
  final String cover;

  /// 缓存目录里已知的章节数（不是已下载数）。
  final int cachedChapterList;

  /// 已经落盘的正文章节数。
  final int downloadedCount;

  /// 网络目录的完整章节列表（增量下载按它的下标走）。
  final List<Chapter> networkChapters;

  /// 网络目录新增、缓存目录里还没有的章节。
  final List<Chapter> fresh;

  /// 缓存目录里有、但正文没下过的历史缺章。
  final List<Chapter> gaps;

  /// 待补齐 = 更新 + 缺章，顺序与网络目录一致。
  List<Chapter> get pending => [...fresh, ...gaps]..sort(
    (a, b) => networkChapters
        .indexWhere((c) => c.itemId == a.itemId)
        .compareTo(networkChapters.indexWhere((c) => c.itemId == b.itemId)),
  );

  bool get hasUpdate => fresh.isNotEmpty;
  bool get hasPending => fresh.isNotEmpty || gaps.isNotEmpty;

  /// 状态行短文案：无事不打扰，有事一句话说清。
  String? get badge {
    if (fresh.isEmpty && gaps.isEmpty) return null;
    final parts = <String>[
      if (fresh.isNotEmpty) '${fresh.length} 章更新',
      if (gaps.isNotEmpty) '${gaps.length} 章缺缓存',
    ];
    return parts.join(' · ');
  }
}

/// 小说更新检测 + 增量下载。
///
/// 复用 [ChapterDownload] 管线（批量取文、断点续传、目录刷新），所以
/// 「下载更新」与详情页「整本下载」同一套落盘规则：正文 pin 住不被 LRU
/// 清掉，目录 `saveBook` 刷新后书架 / 手环传书页立刻看到新章节数。
class BookUpdateService {
  BookUpdateService({
    ChapterCacheStore? cache,
    BookDirectoryLoader? directory,
    Future<String> Function(Chapter chapter)? loader,
    Future<Map<String, String>> Function(String bookId, List<String> itemIds)?
    batchLoader,
  }) : _cache = cache ?? ChapterCacheStore.instance,
       _directory = directory ?? loadBookDirectory,
       _loader =
           loader ?? ((chapter) => ApiClient.instance.contentText(chapter.itemId)),
       _batchLoader =
           batchLoader ??
           ((bookId, ids) => ApiClient.instance.contentBatch(bookId, ids));

  final ChapterCacheStore _cache;
  final BookDirectoryLoader _directory;
  final Future<String> Function(Chapter chapter) _loader;
  final Future<Map<String, String>> Function(String bookId, List<String> itemIds)
  _batchLoader;

  /// 检测一本书有没有更新。单本失败抛给调用方（批量检查自己吞）。
  Future<BookUpdateInfo> check(
    String bookId, {
    String? title,
    String? cover,
  }) async {
    final cached = await _cache.savedCatalogue(bookId);
    final network = await _directory(bookId);
    final known = <String>{
      if (cached != null) for (final c in cached.chapters) c.itemId,
    };
    final downloaded = await _cache.cachedChapterIds(bookId);
    final fresh = <Chapter>[
      for (final c in network)
        if (!known.contains(c.itemId)) c,
    ];
    final gaps = <Chapter>[
      for (final c in network)
        if (known.contains(c.itemId) && !downloaded.contains(c.itemId)) c,
    ];
    return BookUpdateInfo(
      bookId: bookId,
      title: title ?? cached?.title ?? bookId,
      cover: cover ?? cached?.cover ?? '',
      cachedChapterList: cached?.chapters.length ?? 0,
      downloadedCount: downloaded.length,
      networkChapters: network,
      fresh: fresh,
      gaps: gaps,
    );
  }

  /// 批量检测：单本失败跳过（断网 / 单本接口挂不拖垮整轮）。
  Future<Map<String, BookUpdateInfo>> checkAll(
    List<({String id, String title, String cover})> books, {
    void Function(int done, int total)? onProgress,
  }) async {
    final out = <String, BookUpdateInfo>{};
    for (var i = 0; i < books.length; i++) {
      final book = books[i];
      try {
        final info = await check(book.id, title: book.title, cover: book.cover);
        if (info.hasPending) out[book.id] = info;
      } catch (_) {
        // 单本检测失败视为「暂不可知」，不当作有更新。
      }
      onProgress?.call(i + 1, books.length);
    }
    return out;
  }

  /// 增量下载 [info.pending] 里的章节并把目录刷新到最新。跑完返回。
  ///
  /// 起点取网络目录中第一个待补章节的下标——[ChapterDownload] 自带
  /// 「已落盘的复用」，所以范围里夹着已缓存章节也不用重下。
  Future<void> downloadPending(
    BookUpdateInfo info, {
    void Function(int done, int total)? onProgress,
  }) async {
    final pending = info.pending;
    if (pending.isEmpty) return;
    final firstItemId = pending.first.itemId;
    final startIndex = info.networkChapters.indexWhere(
      (c) => c.itemId == firstItemId,
    );
    if (startIndex < 0) return;
    final download = ChapterDownload(
      cache: _cache,
      book: CachedBook(
        id: info.bookId,
        title: info.title,
        cover: info.cover,
        chapters: info.networkChapters,
      ),
      loader: _loader,
      batchLoader: (ids) => _batchLoader(info.bookId, ids),
    );
    if (onProgress != null) {
      download.addListener(() {
        final state = download.value;
        onProgress(state.completed, state.total);
      });
    }
    await download.start(
      startIndex: startIndex,
      count: pending.length,
      // 整本下载同规格：用户的书不进 LRU 预算，避免下完就被清。
      pin: true,
    );
  }
}
