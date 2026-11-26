import '../../models/media_item.dart';
import '../api_client.dart';
import '../chapter_cache_store.dart';
import '../chapter_text_formatter.dart';
import '../imported_book_store.dart';

/// 一本可以推到手环上的书。
///
/// 离线缓存书与本地导入书在传书页上是同一张卡片，差异只留在
/// [sourceLabel] 与 [loadChapter] 里，传输协议不必知道书从哪来。
class BandBookEntry {
  const BandBookEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.sourceLabel,
    required this.chapters,
    required this.bytes,
    required this.loadChapter,
  });

  final String id;
  final String title;
  final String author;
  final String sourceLabel;
  final List<Chapter> chapters;

  /// 已知的正文体量（UTF-8 字节）；0 表示未知。
  final int bytes;

  /// 取第 [index] 章纯文本（不含标题行）。
  final Future<String> Function(int index) loadChapter;

  List<String> get chapterTitles => [for (final c in chapters) c.title];

  /// 手环端书架显示的字数：按中文 UTF-8 三字节估算。
  int get wordCount => bytes ~/ 3;

  /// 同步/传书成功后补进手机书架用（「同步的书双端都必须添加到书架」）。
  MediaItem toMediaItem() => MediaItem(
    id: id,
    title: title,
    cover: '',
    author: author,
    badge: sourceLabel,
    ep: chapters.length.toString(),
    kind: 'book',
  );
}

/// 扫描本机可传的书：先离线缓存（番茄书架），再本地导入（TXT/EPUB）。
class BandBookCatalog {
  BandBookCatalog({
    ChapterCacheStore? cacheStore,
    ImportedBookStore? importedStore,
    ApiClient? api,
  }) : _cache = cacheStore ?? ChapterCacheStore.instance,
       _imported = importedStore ?? ImportedBookStore.instance,
       _api = api ?? ApiClient.instance;

  final ChapterCacheStore _cache;
  final ImportedBookStore _imported;
  final ApiClient _api;

  Future<List<BandBookEntry>> load() async {
    final entries = <BandBookEntry>[];

    try {
      for (final summary in await _cache.books()) {
        final book = summary.book;
        if (book.chapters.isEmpty) continue;
        entries.add(
          BandBookEntry(
            id: book.id,
            title: book.title,
            author: '',
            sourceLabel: '离线缓存',
            chapters: book.chapters,
            bytes: summary.stats.byteCount,
            loadChapter: (index) => _chapterText(book.id, book.chapters[index]),
          ),
        );
      }
    } catch (_) {
      // 缓存库打不开不该连带本地书也看不见，继续往下扫。
    }

    try {
      for (final book in await _imported.books()) {
        if (book.chapters.isEmpty) continue;
        entries.add(
          BandBookEntry(
            id: book.id,
            title: book.title,
            author: book.author,
            sourceLabel: '本地导入',
            chapters: book.chapters,
            bytes: 0,
            loadChapter: (index) async {
              final chapter = book.chapters[index];
              return _plainText(await _imported.chapterText(book.id, chapter.itemId), chapter.title);
            },
          ),
        );
      }
    } catch (_) {
      // 同上：一侧失败不阻塞另一侧。
    }

    entries.sort((a, b) => a.title.compareTo(b.title));
    return entries;
  }

  /// 详情页「一键传书」：不依赖本地已缓存，直接把当前目录包成一个可传条目。
  ///
  /// 正文优先取缓存，缺失再走网络——与书架的传书行为一致，所以详情页
  /// 里对没下载过的书也能边下边传。
  BandBookEntry entryFor({
    required String id,
    required String title,
    String author = '',
    required List<Chapter> chapters,
    int bytes = 0,
    String sourceLabel = '在线阅读',
  }) {
    return BandBookEntry(
      id: id,
      title: title,
      author: author,
      sourceLabel: sourceLabel,
      chapters: chapters,
      bytes: bytes,
      loadChapter: (index) => _chapterText(id, chapters[index]),
    );
  }

  Future<String> _chapterText(String bookId, Chapter chapter) async {
    try {
      final cached = await _cache.read(bookId: bookId, chapterId: chapter.itemId);
      if (cached != null && cached.isNotEmpty) {
        final text = _plainText(cached, chapter.title);
        if (text.isNotEmpty) return text;
      }
    } catch (_) {
      // 缓存损坏就回落网络，官方阅读器也是同一条兜底。
    }
    final content = await _api.chapterContent(chapter.itemId);
    return _plainTextContent(content, chapter.title);
  }
}

/// 缓存文本自带插图标记，传书只取段落文字——手环端没有图片查看器的排版能力。
String _plainText(String cached, String title) {
  try {
    return _plainTextContent(ChapterContent.fromCacheText(cached), title);
  } on FormatException {
    return cached;
  }
}

String _plainTextContent(ChapterContent content, String title) => content
    .withoutLeadingTitle(title)
    .blocks
    .whereType<ChapterParagraph>()
    .map((paragraph) => paragraph.text)
    .join('\n');
