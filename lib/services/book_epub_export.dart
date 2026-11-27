import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/book_detail.dart';
import '../models/media_item.dart';
import 'book_txt_export.dart' show ExportTarget, ExportWriteException;
import 'epub/epub_builder.dart';
import 'epub/epub_document.dart';
import 'epub/epub_metadata.dart';
import 'platform_channel.dart';

/// Stores a finished EPUB where the user can reach it.
abstract class EpubSink {
  Future<ExportTarget> saveBytes({
    required String fileName,
    required Uint8List bytes,
  });
}

/// The system Downloads collection through the same `fqapp/downloads` channel
/// the TXT exporter uses; the platform side decides between `MediaStore` and
/// app-private storage.
class PlatformEpubSink implements EpubSink {
  const PlatformEpubSink();

  static const _channel = AppMethodChannel('fqapp/downloads');

  @override
  Future<ExportTarget> saveBytes({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final Map<String, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<String, Object?>('saveBytes', {
        'fileName': fileName,
        'bytes': bytes,
        'mime': 'application/epub+zip',
      });
    } on PlatformException catch (error) {
      throw ExportWriteException(error.message ?? '写入失败');
    } on MissingPluginException {
      throw const ExportWriteException('当前平台不支持导出到 Downloads');
    }
    final path = result?['path'];
    if (path is! String || path.isEmpty) {
      throw const ExportWriteException('系统未返回导出路径');
    }
    return ExportTarget(path: path, isPublic: result?['public'] == true);
  }
}

/// Progress of one whole-book EPUB export.
@immutable
class EpubExportState {
  const EpubExportState({
    this.running = false,
    this.completed = 0,
    this.total = 0,
    this.failed = 0,
    this.target,
    this.message,
  });

  final bool running;
  final int completed;
  final int total;

  /// Chapters whose body could not be fetched. They are written as empty pages
  /// so the table of contents still matches the book, and the final message
  /// reports the count instead of quietly shipping a shorter book.
  final int failed;
  final ExportTarget? target;
  final String? message;

  double get fraction => total == 0 ? 0 : completed / total;
}

/// Whole-book EPUB 3 export.
///
/// The package is assembled in memory and written in one shot: a cancelled or
/// failed export must not leave a truncated `.epub` in Downloads that a reader
/// will report as corrupt. Chapter bodies come from [chapterLoader] (production
/// wires it to the batch endpoint through `ChapterDownload`), and a chapter
/// that fails is recorded, not fatal — one dead chapter must not cost the other
/// nine hundred.
class BookEpubExport extends ValueNotifier<EpubExportState> {
  BookEpubExport({
    required this.directoryLoader,
    required this.chapterLoader,
    required this.detailLoader,
    required this.sink,
    this.batchLoader,
    this.coverLoader,
    this.timeout = const Duration(seconds: 30),
  }) : super(const EpubExportState());

  final Future<List<Chapter>> Function(String bookId) directoryLoader;
  final Future<String> Function(Chapter chapter) chapterLoader;

  /// Fetches many chapters at once, keyed by itemId. An export of a 400-chapter
  /// book is 400 round trips without it, so this is the difference between a
  /// minute and a few seconds.
  final Future<Map<String, String>> Function(List<String> itemIds)? batchLoader;

  final Future<Map<String, dynamic>> Function(String bookId) detailLoader;
  final EpubSink sink;

  /// Chapters per batch request.
  static const batchSize = 80;

  /// Cover bytes, or null when the book has no usable artwork. Never fatal: an
  /// EPUB without a cover is still a valid EPUB.
  final Future<Uint8List?> Function(String coverUrl)? coverLoader;
  final Duration timeout;

  int _job = 0;
  bool _disposed = false;

  Future<void> start({
    required String bookId,
    required String title,
  }) async {
    if (_disposed || value.running) return;
    final job = ++_job;
    value = const EpubExportState(running: true);

    final List<Chapter> chapters;
    try {
      chapters = await directoryLoader(bookId).timeout(timeout);
    } catch (_) {
      if (_alive(job)) {
        value = const EpubExportState(message: '导出失败：目录获取失败，请检查网络后重试');
      }
      return;
    }
    if (!_alive(job)) return;
    if (chapters.isEmpty) {
      value = const EpubExportState(message: '导出失败：这本书没有可导出的章节');
      return;
    }

    value = EpubExportState(running: true, total: chapters.length);
    final body = <EpubChapter>[];
    var failed = 0;
    var prefetched = const <String, String>{};
    var prefetchFrom = -1;
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      if (!_alive(job)) return;
      var paragraphs = const <String>[];
      try {
        final fetcher = batchLoader;
        if (fetcher != null &&
            !prefetched.containsKey(chapter.itemId) &&
            (prefetchFrom < 0 || i >= prefetchFrom + batchSize)) {
          prefetchFrom = i;
          prefetched = await _prefetch(fetcher, chapters, i);
          if (!_alive(job)) return;
        }
        final text =
            (prefetched[chapter.itemId] ??
                    await chapterLoader(chapter).timeout(timeout))
                .trim();
        if (!_alive(job)) return;
        paragraphs = _paragraphs(text);
      } catch (_) {
        if (!_alive(job)) return;
        failed++;
      }
      body.add(EpubChapter(title: chapter.title, paragraphs: paragraphs));
      value = EpubExportState(
        running: true,
        completed: body.length,
        total: chapters.length,
        failed: failed,
      );
    }
    if (!_alive(job)) return;

    EpubMetadata meta;
    var coverUrl = '';
    try {
      final payload = await detailLoader(bookId).timeout(timeout);
      meta = metadataFromPayload(payload);
      coverUrl = BookDetail.fromPayload(payload).cover;
    } catch (_) {
      // The catalogue is already in hand; a failed detail request must not cost
      // the user the whole export, it only thins the title page.
      meta = metadataFromCached(
        bookId: bookId,
        title: title,
        author: '',
        chapterCount: chapters.length,
      );
    }
    if (meta.title.trim().isEmpty) {
      meta = metadataFromCached(
        bookId: bookId,
        title: title,
        author: meta.author,
        category: meta.category,
        tags: meta.tags,
        abstract: meta.abstract,
        chapterCount: chapters.length,
      );
    }
    if (!_alive(job)) return;

    Uint8List? cover;
    if (coverLoader != null && coverUrl.isNotEmpty) {
      try {
        cover = await coverLoader!(coverUrl).timeout(timeout);
      } catch (_) {
        cover = null;
      }
    }
    if (!_alive(job)) return;

    final EpubPackage package;
    try {
      package = buildEpubPackage(meta: meta, chapters: body, cover: cover);
    } catch (_) {
      if (_alive(job)) {
        value = EpubExportState(
          completed: body.length,
          total: chapters.length,
          failed: failed,
          message: '导出失败：EPUB 打包出错',
        );
      }
      return;
    }
    if (!_alive(job)) return;

    final ExportTarget target;
    try {
      target = await sink.saveBytes(
        fileName: epubFileName(meta.title),
        bytes: package.bytes,
      );
    } catch (_) {
      if (_alive(job)) {
        value = EpubExportState(
          completed: body.length,
          total: chapters.length,
          failed: failed,
          message: '导出失败：写入 Downloads 失败，请重试',
        );
      }
      return;
    }
    if (!_alive(job)) return;

    final where = target.isPublic ? target.path : '${target.path}（应用私有目录）';
    final missing = failed == 0 ? '' : '，$failed 章取文失败，已留空页';
    final size = (package.bytes.length / 1048576).toStringAsFixed(1);
    value = EpubExportState(
      completed: body.length,
      total: chapters.length,
      failed: failed,
      target: target,
      message: '已导出《${meta.title}》$size MB，${package.chapterCount} 章'
          '${package.hasCover ? '，含封面' : ''}$missing\n$where',
    );
  }

  void cancel() {
    ++_job;
    final state = value;
    value = EpubExportState(
      completed: state.completed,
      total: state.total,
      failed: state.failed,
      message: '已取消导出，未写入文件',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    ++_job;
    super.dispose();
  }

  bool _alive(int job) => !_disposed && job == _job;

  /// One batch request with a bisecting retry: a batch fails as a whole when a
  /// single chapter is gone upstream, so halving the range recovers the rest
  /// instead of dropping all eighty.
  Future<Map<String, String>> _prefetch(
    Future<Map<String, String>> Function(List<String> itemIds) fetcher,
    List<Chapter> chapters,
    int from,
  ) {
    final slice = chapters.skip(from).take(batchSize).toList(growable: false);
    return _fetchBisect(fetcher, [for (final chapter in slice) chapter.itemId]);
  }

  Future<Map<String, String>> _fetchBisect(
    Future<Map<String, String>> Function(List<String> itemIds) fetcher,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    try {
      return await fetcher(ids).timeout(const Duration(seconds: 90));
    } catch (_) {
      if (ids.length <= 1) return const {};
      final mid = ids.length ~/ 2;
      final left = await _fetchBisect(fetcher, ids.sublist(0, mid));
      final right = await _fetchBisect(fetcher, ids.sublist(mid));
      return {...left, ...right};
    }
  }
}

/// `<书名>.epub`, folded into a name a Downloads entry accepts.
String epubFileName(String title) {
  var name = title
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  name = name.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  if (name.isEmpty) name = 'book';
  final runes = name.runes.toList();
  if (runes.length > 80) {
    name = String.fromCharCodes(runes.take(80)).trimRight();
  }
  return '$name.epub';
}

/// Splits fetched chapter text into paragraphs. The upstream separates
/// paragraphs with `\n` and sometimes pads them with full-width spaces.
List<String> _paragraphs(String text) => [
  for (final line in text.split(RegExp(r'\r?\n')))
    if (line.replaceAll('\u3000', ' ').trim().isNotEmpty)
      line.replaceAll('\u3000', ' ').trim(),
];

/// Default cover fetcher: plain HTTP with a size cap, because a mis-sized
/// response should degrade to "no cover" rather than stall the export.
Future<Uint8List?> fetchCoverBytes(
  String url, {
  Duration timeout = const Duration(seconds: 20),
  int maxBytes = 8 * 1024 * 1024,
}) async {
  if (url.isEmpty) return null;
  try {
    final response = await http
        .get(Uri.parse(url), headers: const {'user-agent': 'fqapp-epub'})
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    if (response.bodyBytes.length > maxBytes) return null;
    return response.bodyBytes;
  } catch (_) {
    return null;
  }
}
