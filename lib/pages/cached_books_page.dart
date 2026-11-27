// Upstream source: Wenku8_Flutter rev ebcd7f1
//   lib/offline_widgets.dart (OfflineCachePage: ArchiveFeaturePage shell,
//     ArchiveSection '本地存储', cached-byte caption, ContentPanel book rows,
//     empty-copy placement, GlassIconButton clear action)
//   lib/local_maintenance_page.dart (ContentPanel row rhythm and typography)
// Mechanical substitutions:
// - fqapp's ChapterCacheStore / BookTxtExport / openCachedBook stay untouched;
//   only the presentation scaffold changes.
// - The upstream OfflineBookMenu (GlassMenuAnchor) is not part of the shared
//   slice; the two explicit row actions (export TXT, delete cache) keep their
//   keys and tooltips.
// - `formatCacheBytes`, `AppText`, `ContentPanel`, `ArchiveFeaturePage`,
//   `ArchiveSection` and `GlassIconButton` are re-used as-is. E-ink delete
//   colour still follows `HomePalette.eink`.
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../models/media_item.dart';
import '../services/api_client.dart';
import '../services/book_epub_export.dart';
import '../services/book_txt_export.dart';
import '../services/book_update_service.dart';
import '../services/chapter_cache_store.dart';
import '../services/library_store.dart';
import '../theme/md3.dart';
import '../widgets/home/home_design.dart';
import '../widgets/settings/settings_widgets.dart';
import '../widgets/wenku/wenku_ui.dart';
import 'cached_book_reader.dart';

class CachedBooksPage extends StatefulWidget {
  final ChapterCacheStore? cacheStore;
  final ReaderStore? readerStore;

  /// 导出时重取的目录与正文加载器、以及落点；都缺省走实时实现，
  /// 注入后测试可完全离线（与详情页的 loader 注入同一套路）。
  final Future<List<Chapter>> Function(String bookId)? exportDirectoryLoader;
  final Future<String> Function(Chapter chapter)? exportChapterLoader;
  final TxtSink? exportSink;

  const CachedBooksPage({
    super.key,
    this.cacheStore,
    this.readerStore,
    this.exportDirectoryLoader,
    this.exportChapterLoader,
    this.exportSink,
  });

  @override
  State<CachedBooksPage> createState() => _CachedBooksPageState();
}

class _CachedBooksPageState extends State<CachedBooksPage> {
  late final ChapterCacheStore _store =
      widget.cacheStore ?? ChapterCacheStore.instance;
  List<CachedBookSummary> _books = [];
  bool _loading = true;
  bool _openingBook = false;
  String? _error;
  int _generation = 0;
  BookTxtExport? _export;
  String? _exportBookId;
  BookEpubExport? _epubExport;
  String? _epubBookId;

  /// 更新检测结果：bookId → 待补章节信息。空表 = 还没检查过 / 都是最新。
  Map<String, BookUpdateInfo> _updates = const {};
  bool _checkingUpdates = false;

  /// 正在增量下载更新的书及其进度文案（同一时间只下一本，串行稳妥）。
  String? _updatingBookId;
  String? _updateHint;

  /// 多选删除态：进入后点行只勾选，导出/单删按钮换成勾选框。
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _store.changes.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _store.changes.removeListener(_reload);
    // 离开页面就不该再有后台导出：没有界面报告结果的成功等于骗人。
    _export?.removeListener(_onExportChanged);
    _export?.dispose();
    _export = null;
    _epubExport?.removeListener(_onEpubChanged);
    _epubExport?.dispose();
    _epubExport = null;
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final books = await _store.books();
      if (!mounted || generation != _generation) return;
      setState(() {
        _books = books;
        // 选中集合随数据回真：别处删掉的书不该继续占着「已选 N 本」。
        _selected.removeWhere(
          (id) => !books.any((item) => item.book.id == id),
        );
        if (books.isEmpty) _selecting = false;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = '无法读取缓存';
        });
      }
    }
  }

  /// 检查全部缓存书的更新：网络目录 vs 缓存目录，有新增或缺章才亮出来。
  Future<void> _checkUpdates() async {
    if (_checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    try {
      final service = BookUpdateService();
      final infos = await service.checkAll([
        for (final item in _books)
          (
            id: item.book.id,
            title: item.book.title,
            cover: item.book.cover,
          ),
      ]);
      if (!mounted) return;
      setState(() => _updates = infos);
      final freshTotal = infos.values.fold<int>(0, (n, i) => n + i.fresh.length);
      final gapTotal = infos.values.fold<int>(0, (n, i) => n + i.gaps.length);
      md3ShowSnackBar(
        context,
        infos.isEmpty
            ? '全部是最新，没有待补章节'
            : '${infos.length} 本待补：$freshTotal 章更新，$gapTotal 章缺缓存',
      );
    } catch (_) {
      if (mounted) md3ShowSnackBar(context, '更新检查失败，请联网后重试');
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  /// 增量下载一本书的待补章节（更新 + 缺章），跑完刷新列表。
  Future<void> _downloadUpdate(CachedBook book) async {
    final info = _updates[book.id];
    if (info == null || _updatingBookId != null) return;
    setState(() {
      _updatingBookId = book.id;
      _updateHint = '准备下载…';
    });
    try {
      await BookUpdateService().downloadPending(
        info,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() => _updateHint = '下载中 $done/$total');
        },
      );
      if (!mounted) return;
      final count = info.pending.length;
      setState(() {
        _updatingBookId = null;
        _updateHint = null;
        _updates = Map.of(_updates)..remove(book.id);
      });
      md3ShowSnackBar(context, '《${book.title}》已补齐 $count 章');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _updatingBookId = null;
        _updateHint = null;
      });
      md3ShowSnackBar(context, '《${book.title}》下载失败，请重试');
    }
  }

  /// 逐本补齐全部待补章节。
  Future<void> _downloadAllUpdates() async {
    if (_updatingBookId != null) return;
    final ids = _updates.keys.toList();
    for (final id in ids) {
      if (!mounted) return;
      final book = _books.where((item) => item.book.id == id).firstOrNull?.book;
      if (book == null) continue;
      await _downloadUpdate(book);
    }
  }

  Future<void> _clear([CachedBook? book]) async {
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: book == null ? '清空全部章节缓存' : '删除这本书的缓存',
      message: '只清理缓存正文与目录，阅读历史和排版设置会保留。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _store.clear(bookId: book?.id);
      } catch (_) {
        if (mounted) {
          md3ShowSnackBar(context, '清理失败，请重试');
        }
      }
  }

  /// 多选删除：一次确认后逐本清理。语义与单删一致（只删缓存、保留历史），
  /// 走 store 的 clear(bookId:)，每本都过同一把锁与 changes 通知。
  Future<void> _deleteSelected() async {
    final ids = [for (final id in _selected) id];
    if (ids.isEmpty) return;
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '删除选中的 ${ids.length} 本缓存',
      message: '只清理缓存正文与目录，阅读历史和排版设置会保留。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      for (final id in ids) {
        await _store.clear(bookId: id);
      }
      if (mounted) _exitSelect();
    } catch (_) {
      if (mounted) {
        md3ShowSnackBar(context, '删除失败，请重试');
        await _reload();
      }
    }
  }

  bool get _allSelected =>
      _books.isNotEmpty &&
      _books.every((item) => _selected.contains(item.book.id));

  void _toggleSelected(String bookId) {
    setState(() {
      if (!_selected.remove(bookId)) _selected.add(bookId);
    });
  }

  void _toggleSelectAll() {
    setState(() {
      // 取消全选同样只作用于当前列表（与书架编辑态同一语义）。
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll([for (final item in _books) item.book.id]);
      }
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _open(CachedBook book) async {
    if (_openingBook) return;
    _openingBook = true;
    try {
      final opened = await openCachedBook(
        context,
        book: book,
        cache: _store,
        readerStore: widget.readerStore,
      );
      // 目录与章节对不上（章节已被逐出）时刷新列表，别让一行点不动又没反馈。
      if (!opened && mounted) await _reload();
    } catch (_) {
      if (mounted) {
        md3ShowSnackBar(context, '无法打开缓存，请重试');
      }
    } finally {
      _openingBook = false;
    }
  }

  Future<List<Chapter>> _loadExportDirectory(String bookId) async {
    final volumes = await ApiClient.instance.directoryChapters(bookId);
    return [for (final volume in volumes) ...volume];
  }

  /// Starts the whole-book export of one cached book. Only one runs at a time,
  /// and a second tap on any row cancels it instead of starting a second file.
  void _startExport(CachedBook book) {
    if (_export != null) return;
    final export = BookTxtExport(
      directoryLoader: widget.exportDirectoryLoader ?? _loadExportDirectory,
      // 取文只经 ApiClient：CRIT-005 要求业务请求都过它的 _get 漏斗。
      chapterLoader:
          widget.exportChapterLoader ??
          (chapter) => ApiClient.instance.contentText(chapter.itemId),
      sink: widget.exportSink ?? const PlatformTxtSink(),
    );
    export.addListener(_onExportChanged);
    _export = export;
    _exportBookId = book.id;
    setState(() {});
    export.start(bookId: book.id, title: book.title);
  }

  void _cancelExport() => _export?.cancel();

  /// Starts the whole-book EPUB export: cover, full metadata and every chapter
  /// re-fetched from the network, written to Downloads as a single package.
  void _startEpub(CachedBook book) {
    if (_epubExport != null) return;
    final export = BookEpubExport(
      directoryLoader: widget.exportDirectoryLoader ?? _loadExportDirectory,
      // Batch first: the `full` endpoint decrypts a whole book in one round
      // trip, and the per-chapter loader covers anything it leaves out.
      batchLoader: (ids) => ApiClient.instance.contentBatch(book.id, ids),
      chapterLoader:
          widget.exportChapterLoader ??
          (chapter) => ApiClient.instance.contentText(chapter.itemId),
      detailLoader: (id) => ApiClient.instance.fanqieBookMetadata(id),
      coverLoader: (url) => fetchCoverBytes(url),
      sink: const PlatformEpubSink(),
    );
    export.addListener(_onEpubChanged);
    _epubExport = export;
    _epubBookId = book.id;
    setState(() {});
    export.start(bookId: book.id, title: book.title);
  }

  void _cancelEpub() => _epubExport?.cancel();

  void _onEpubChanged() {
    final export = _epubExport;
    if (export == null) return;
    final state = export.value;
    if (!state.running) {
      export.removeListener(_onEpubChanged);
      _epubExport = null;
      _epubBookId = null;
      // 不能在自己的 notifyListeners 调用栈里 dispose：那一刻通知列表正在被遍历。
      final message = state.message;
      Future<void>.microtask(export.dispose);
      if (message != null) _snack(message);
    }
    if (mounted) setState(() {});
  }

  void _onExportChanged() {
    final export = _export;
    if (export == null) return;
    final state = export.value;
    if (!state.running) {
      export.removeListener(_onExportChanged);
      _export = null;
      _exportBookId = null;
      // 不能在自己的 notifyListeners 调用栈里 dispose：那一刻通知列表正在被遍历。
      final message = state.message;
      Future<void>.microtask(export.dispose);
      if (message != null) _snack(message);
    }
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    md3ShowSnackBar(context, message);
  }

  Color _deleteColor(BuildContext context) => HomePalette.of(context).eink
      ? Colors.black
      : Theme.of(context).colorScheme.error;

  /// 状态行：全本 / 缺章一眼可辨，占用空间随后。
  ///
  /// 章数以「已缓存正文数 / 保存的目录章数」为准：目录之外的新增章节离线
  /// 无从得知，这里不假装知道「是否更新」，只诚实报告缓存相对目录的缺口。
  String _summaryLine(CachedBookSummary item) {
    final cachedCount = item.stats.chapterCount;
    final total = item.book.chapters.length;
    final missing = total - cachedCount;
    final chapters = missing > 0
        ? '已缓存 $cachedCount/$total 章 · 缺 $missing 章'
        : '全本 $cachedCount 章';
    return '$chapters · ${formatCacheBytes(item.stats.byteCount)}';
  }

  /// One cached book row: tap opens the reader, the trailing actions export and
  /// clear. A running export turns its own button into progress and cancel.
  Widget _bookCard(
    CachedBookSummary item,
    ColorScheme scheme,
    Color deleteColor,
  ) {
    final bookId = item.book.id;
    // _onExportChanged clears _exportBookId as soon as the export stops, so a
    // row can only see a state here while that export is still running.
    final progress = _exportBookId == bookId ? _export?.value : null;
    final epubProgress = _epubBookId == bookId ? _epubExport?.value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ContentPanel(
        onTap: () => _selecting
            ? _toggleSelected(bookId)
            : _open(item.book),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ArchiveIcon(LucideIcons.book_open, size: 21),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        item.book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 7),
                      // 状态行一眼分清「全本」还是「缺章」：缺章时点明还缺几章，
                      // 不再让用户自己心算两个数字的差。
                      AppText(
                        _summaryLine(item),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      // 更新检测结果直接钉在状态行下：有更新 / 缺章一眼可见。
                      if (_updates[bookId] case final info?) ...[
                        const SizedBox(height: 3),
                        AppText(
                          '待补 ${info.badge}',
                          key: Key('cached_book_update_badge_$bookId'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                      if (_relativeTime(item.cachedAt) case final cached?) ...[
                        const SizedBox(height: 3),
                        AppText(
                          '最近缓存 $cached',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 多选态：动作按钮换成勾选框，点行即可勾选/取消。
                if (_selecting)
                  Checkbox(
                    key: Key('cached_book_check_$bookId'),
                    value: _selected.contains(bookId),
                    onChanged: (_) => _toggleSelected(bookId),
                  )
                else ...[
                if (epubProgress != null)
                  IconButton(
                    key: Key('cached_book_epub_$bookId'),
                    tooltip: '取消 EPUB 导出',
                    onPressed: _cancelEpub,
                    icon: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        value: epubProgress.total == 0
                            ? null
                            : epubProgress.fraction,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else
                  IconButton(
                    key: Key('cached_book_epub_$bookId'),
                    tooltip: '导出 EPUB 到系统「下载」（含封面与完整元数据）',
                    onPressed: _export == null && _epubExport == null
                        ? () => _startEpub(item.book)
                        : null,
                    icon: Icon(
                      LucideIcons.book_open,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (progress != null)
                  IconButton(
                    key: Key('cached_book_export_$bookId'),
                    tooltip: '取消导出',
                    onPressed: _cancelExport,
                    icon: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        value: progress.total == 0 ? null : progress.fraction,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else
                  IconButton(
                    key: Key('cached_book_export_$bookId'),
                    tooltip: '导出 TXT 到系统「下载」',
                    onPressed: _export == null && _epubExport == null
                        ? () => _startExport(item.book)
                        : null,
                    icon: Icon(
                      LucideIcons.download,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (_updates[bookId] != null)
                  IconButton(
                    key: Key('cached_book_update_$bookId'),
                    tooltip: _updatingBookId == bookId
                        ? (_updateHint ?? '下载中')
                        : '下载待补章节（更新 + 缺章）',
                    onPressed: _updatingBookId == null
                        ? () => _downloadUpdate(item.book)
                        : null,
                    icon: _updatingBookId == bookId
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.cloud_download_outlined,
                            size: 20,
                            color: scheme.primary,
                          ),
                  ),
                IconButton(
                  tooltip: '删除《${item.book.title}》缓存',
                  onPressed: () => _clear(item.book),
                  icon: Icon(LucideIcons.trash, size: 20, color: deleteColor),
                ),
                ],
              ],
            ),
            if (epubProgress != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppText(
                    epubProgress.total == 0
                        ? '正在准备 EPUB…'
                        : 'EPUB ${epubProgress.completed}/${epubProgress.total} 章',
                    key: Key('cached_book_epub_progress_$bookId'),
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  ),
                ),
              ),
            if (progress != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppText(
                    progress.total == 0
                        ? '导出中…'
                        : '导出 ${progress.completed}/${progress.total} 章',
                    key: Key('cached_book_export_progress_$bookId'),
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error case final error?) {
      return ListView(
        padding: featurePadding(context),
        children: [
          FeatureError(error),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _reload,
              child: const AppText('重试'),
            ),
          ),
        ],
      );
    }
    final count = _books.fold(0, (sum, item) => sum + item.stats.chapterCount);
    final bytes = _books.fold(0, (sum, item) => sum + item.stats.byteCount);
    final deleteColor = _deleteColor(context);
    return ListView(
      key: const ValueKey('cached-books-scroll'),
      padding: featurePadding(context),
      children: [
        ArchiveSection(
          title: '本地存储',
          code: 'ARCHIVE / LOCAL STORAGE',
          subtitle: _books.isEmpty
              ? ''
              : '已缓存 ${_books.length} 本 · 共 $count 章 · '
                    '${formatCacheBytes(bytes)}',
        ),
        const SizedBox(height: 14),
        AppText(
          '已缓存正文与插图可离线阅读。清理缓存不会移出书架，也不会删除阅读进度。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        if (_books.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppText(
              '暂无缓存章节',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          )
        else
          for (final item in _books) _bookCard(item, scheme, deleteColor),
        if (_books.isEmpty) ...[
          const SizedBox(height: 10),
          AppText(
            '阅读小说后会自动保存，详情页「下载」会保存整本；下载的章节不会被自动清理。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ArchiveFeaturePage(
      title: '小说离线缓存',
      code: 'ARCHIVE / LOCAL STORAGE',
      actions: [
        if (_selecting) ...[
          IconButton(
            key: const Key('cached-books-select-all'),
            tooltip: _allSelected ? '取消全选' : '全选',
            icon: Icon(_allSelected ? Icons.deselect : Icons.select_all),
            onPressed: _books.isEmpty ? null : _toggleSelectAll,
          ),
          IconButton(
            key: const Key('cached-books-delete-selected'),
            tooltip: '删除选中的缓存（${_selected.length}）',
            onPressed: _selected.isEmpty ? null : _deleteSelected,
            icon: Icon(Icons.delete, color: _deleteColor(context)),
          ),
          IconButton(
            key: const Key('cached-books-select-done'),
            tooltip: '完成',
            icon: const Icon(Icons.check),
            onPressed: _exitSelect,
          ),
        ] else ...[
          IconButton(
            key: const Key('cached-books-check-updates'),
            tooltip: '检查更新（对照网络目录补齐新章节）',
            icon: _checkingUpdates
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt),
            onPressed: _books.isEmpty || _checkingUpdates ? null : _checkUpdates,
          ),
          if (_updates.isNotEmpty)
            IconButton(
              key: const Key('cached-books-update-all'),
              tooltip: '下载全部待补章节（${_updates.length} 本）',
              onPressed: _updatingBookId == null ? _downloadAllUpdates : null,
              icon: const Icon(Icons.download_for_offline_outlined),
            ),
          IconButton(
            key: const Key('cached-books-select'),
            tooltip: '多选删除',
            icon: const Icon(Icons.checklist),
            onPressed: _books.isEmpty
                ? null
                : () => setState(() => _selecting = true),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: '清空全部缓存',
            onPressed: _books.isEmpty ? null : () => _clear(),
          ),
        ],
      ],
      child: _body(scheme),
    );
  }
}

/// 缓存时间的相对展示，与书架条目的时间文案同一套粒度。
String? _relativeTime(int? time) {
  if (time == null) return null;
  final date = DateTime.fromMillisecondsSinceEpoch(time);
  final difference = DateTime.now().difference(date);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes}分钟前';
  if (difference.inDays < 1) return '${difference.inHours}小时前';
  if (difference.inDays < 7) return '${difference.inDays}天前';
  return '${date.month}月${date.day}日';
}
