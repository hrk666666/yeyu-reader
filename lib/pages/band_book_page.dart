import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/band_book/band_auto_connect.dart';
import '../services/band_book/band_book_catalog.dart';
import '../services/band_book/band_book_remote.dart';
import '../services/band_book/band_book_transfer.dart';
import '../services/band_book/band_reading_sync.dart';
import '../services/book_update_service.dart';
import '../theme/md3.dart';
import 'band_rpk_tool_page.dart';
import 'band_transfer_page.dart';

/// 设置项键：连上手环后是否自动同步一次阅读数据。
const String _autoSyncKey = 'band_book_auto_sync';

/// 手环传书：设备、存储、书单、传书、阅读数据双向同步。
class BandBookPage extends StatefulWidget {
  const BandBookPage({super.key, this.focus});

  /// 从书籍详情页「一键传书」进来时带上的条目：页面打开后自动连接并开始传。
  final BandBookEntry? focus;

  @override
  State<BandBookPage> createState() => _BandBookPageState();
}

class _BandBookPageState extends State<BandBookPage> {
  final BandBookTransfer _transfer = BandBookTransfer.shared;
  late final BandBookRemote _remote = BandBookRemote(_transfer);
  late final BandReadingSync _sync = BandReadingSync(_remote);

  final Map<String, BandBookStatus> _bandStatus = <String, BandBookStatus>{};
  final Map<String, BandReadingData> _bandReading = <String, BandReadingData>{};

  List<BandBookEntry> _books = const <BandBookEntry>[];
  BandStorageInfo _storage = BandStorageInfo.empty;

  bool _loading = true;
  bool _autoStarted = false;
  bool _connecting = false;
  bool _autoSync = true;
  bool _autoConnect = true;
  bool _syncing = false;
  bool _probingAll = false;
  bool _storageLoading = false;
  String? _pushing;
  String? _probing;
  String? _syncHint;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadPrefs());
    _transfer.addListener(_onTransferChanged);
  }

  @override
  void dispose() {
    _transfer.removeListener(_onTransferChanged);
    super.dispose();
  }

  void _onTransferChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoSync = sp.getBool(_autoSyncKey) ?? true;
    });
    _autoConnect = await BandAutoConnect.instance.enabled();
    if (mounted) setState(() {});
  }

  Future<void> _setAutoSync(bool value) async {
    setState(() => _autoSync = value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_autoSyncKey, value);
  }

  Future<void> _setAutoConnect(bool value) async {
    setState(() => _autoConnect = value);
    await BandAutoConnect.instance.setEnabled(value);
  }

  Future<void> _load() async {
    try {
      final catalog = BandBookCatalog();
      final books = await catalog.load();
      if (!mounted) return;
      final focus = widget.focus;
      setState(() {
        _books = focus != null && !books.any((b) => b.id == focus.id)
            ? [focus, ...books]
            : books;
        _loading = false;
      });
      if (focus != null) unawaited(_autoStart());
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      md3ShowSnackBar(context, '读取书目失败：$error');
    }
  }

  bool get _connected => _transfer.state.connected;

  /// 详情页一键传书：连上就传，不额外跑阅读数据同步，避免抢时间。
  Future<void> _autoStart() async {
    final entry = widget.focus;
    if (entry == null || _autoStarted) return;
    _autoStarted = true;
    if (!_connected) await _connect(syncAfter: false);
    if (!mounted || !_connected) return;
    await _refreshDevice();
    if (!mounted || !_connected) return;
    await _push(entry);
  }

  Future<void> _connect({bool syncAfter = true}) async {
    setState(() => _connecting = true);
    await _transfer.connect(reuse: true);
    if (!mounted) return;
    setState(() => _connecting = false);

    final state = _transfer.state;
    if (!state.connected) {
      if (state.error != null) md3ShowSnackBar(context, state.error!);
      return;
    }
    await _refreshDevice();
    if (syncAfter && _autoSync) await _syncAll(silent: true);
  }

  Future<void> _disconnect() async {
    await _transfer.disconnect();
    if (!mounted) return;
    setState(() {
      _bandStatus.clear();
      _bandReading.clear();
      _storage = BandStorageInfo.empty;
    });
  }

  /// 连接后拉一次设备侧全量状态：存储 + 每本书的章节/进度/时长。
  Future<void> _refreshDevice() async {
    setState(() => _storageLoading = true);
    BandStorageInfo storage = BandStorageInfo.empty;
    try {
      // 外层 15s 硬超时 + catch-all：任何异常都不允许把「读取中」永久挂住。
      storage = await _remote
          .storage()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      storage = BandStorageInfo.empty;
    }
    if (!mounted) return;
    setState(() {
      _storage = storage;
      _storageLoading = false;
    });
    await _probeAll();
  }

  Future<void> _probeAll() async {
    if (_probingAll || !_connected) return;
    setState(() => _probingAll = true);
    for (final entry in _books) {
      if (!mounted || !_connected) break;
      await _probe(entry, silent: true);
    }
    if (mounted) setState(() => _probingAll = false);
  }

  Future<void> _probe(BandBookEntry entry, {bool silent = false}) async {
    if (!_connected) return;
    setState(() => _probing = entry.id);
    try {
      final status = await _remote.status(entry.title);
      final reading = await _remote.readingData(entry.title);
      if (!mounted) return;
      setState(() {
        _bandStatus[entry.id] = status;
        _bandReading[entry.id] = reading;
      });
    } finally {
      if (mounted) setState(() => _probing = null);
    }
    if (!silent && mounted) {
      md3ShowSnackBar(context, '${entry.title}：手环状态已刷新');
    }
  }

  /// 传书入口：先看手环上已有多少章，再决定增量还是整本。
  Future<void> _push(BandBookEntry entry) async {
    if (!_connected) {
      md3ShowSnackBar(context, '请先连接手环');
      return;
    }
    if (_pushing != null || _transfer.state.busy) return;

    // 「更新部分」先落到手机：网络目录比缓存目录新时先把新章节补进本地
    // （目录随之刷新），再走缺章增量传书，手环才能拿到更新的章节。
    // 更新检查失败（离线）不阻塞传书——局域网连手环不需要互联网。
    try {
      final info = await BookUpdateService().check(
        entry.id,
        title: entry.title,
      );
      if (!mounted) return;
      if (info.hasPending) {
        final choice = await _askUpdateFirst(info);
        if (!mounted || choice == null) return;
        if (choice == _UpdateFirstChoice.download) {
          setState(() => _pushing = entry.id);
          try {
            await BookUpdateService().downloadPending(info);
          } finally {
            if (mounted) setState(() => _pushing = null);
          }
          // 目录刷新后重取条目：loadChapter 闭包绑定的是旧目录下标。
          await _load();
          if (!mounted) return;
          entry =
              _books.where((b) => b.id == entry.id).firstOrNull ?? entry;
        }
      }
    } catch (_) {
      // 保持原条目继续传书。
    }

    final status =
        _bandStatus[entry.id] ?? await _remote.status(entry.title);
    if (!mounted) return;
    _bandStatus[entry.id] = status;
    final missing = status.missingFrom(entry.chapters.length);
    List<int>? chapters;

    if (status.syncedChapters.isNotEmpty) {
      if (missing.isEmpty) {
        md3ShowSnackBar(context, '手环上已是最新，无需重传');
        return;
      }
      final choice = await _askIncrement(
        title: entry.title,
        synced: status.syncedChapters.length,
        missing: missing.length,
        total: entry.chapters.length,
      );
      if (choice == null) return;
      if (choice == _PushChoice.increment) chapters = missing;
    }

    setState(() => _pushing = entry.id);
    try {
      final ok = await _transfer.sendBook(
        title: entry.title,
        chapterTitles: entry.chapterTitles,
        loadChapter: entry.loadChapter,
        chapters: chapters,
        totalChapters: entry.chapters.length,
        author: entry.author,
      );
      if (!mounted) return;
      if (ok) {
        await _probe(entry, silent: true);
        if (!mounted) return;
        md3ShowSnackBar(context, '${entry.title}：${chapters == null ? '整本' : '缺失章节'}已送达');
      } else {
        md3ShowSnackBar(context, _transfer.state.error ?? '传输失败');
      }
    } finally {
      if (mounted) setState(() => _pushing = null);
    }
  }

  Future<void> _cancelPush() => _transfer.cancel();

  /// 打开独立传输页（多选书目 / 设置 / 实时进度），返回后刷新手环状态。
  Future<void> _openTransferPage() async {
    await Navigator.push<void>(
      context,
      Md3SharedAxisPageRoute(
        builder: (_) => BandTransferPage(
          initialSelection: _books,
          initialBandStatus: _bandStatus,
        ),
      ),
    );
    if (!mounted) return;
    if (_connected) unawaited(_probeAll());
  }

  Future<void> _deleteOnBand(BandBookEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: Md3Shape.extraLargeRadius),
        title: const Text('删除手环副本'),
        content: Text('将从手环删除《${entry.title}》的全部章节、封面和阅读进度，手机端不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final ok = await _remote.deleteBook(entry.title);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _bandStatus[entry.id] = BandBookStatus.empty;
        _bandReading.remove(entry.id);
      });
      md3ShowSnackBar(context, '已从手环删除《${entry.title}》');
    } else {
      md3ShowSnackBar(context, '删除失败，请重试');
    }
  }

  Future<void> _syncOne(BandBookEntry entry) async {
    if (!_connected || _syncing) return;
    setState(() {
      _syncing = true;
      _syncHint = '同步《${entry.title}》…';
    });
    final outcome = await _sync.syncBook(
      title: entry.title,
      bookId: entry.id,
      chapterCount: entry.chapters.length,
      item: entry.toMediaItem(),
    );
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncHint = null;
    });
    await _probe(entry, silent: true);
    if (!mounted) return;
    md3ShowSnackBar(context, outcome.summary);
  }

  Future<void> _syncAll({bool silent = false}) async {
    if (!_connected || _syncing) return;
    final targets = [
      for (final entry in _books)
        BandSyncTarget(
          title: entry.title,
          bookId: entry.id,
          chapterCount: entry.chapters.length,
          item: entry.toMediaItem(),
        ),
    ];
    if (targets.isEmpty) return;

    setState(() {
      _syncing = true;
      _syncHint = '同步阅读数据 0/${targets.length}';
    });

    final results = await _sync.syncAll(
      targets,
      onProgress: (done, total, outcome) {
        if (!mounted) return;
        setState(() => _syncHint = '同步阅读数据 $done/$total · ${outcome.title}');
      },
    );

    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncHint = null;
    });
    await _probeAll();
    if (!mounted || silent) return;

    final touched = results.where((r) => r.chapterIndex != null).length;
    final seconds = results.fold<int>(0, (sum, r) => sum + r.secondsMerged);
    final minutes = (seconds / 60).round();
    md3ShowSnackBar(
      context,
      minutes > 0 ? '已同步 $touched 本书，补入 $minutes 分钟' : '已同步 $touched 本书',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _transfer.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('手环传书'),
        actions: [
          IconButton(
            tooltip: '安装包工具',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BandRpkToolPage()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _load();
                if (_connected) await _refreshDevice();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Md3Dimens.compactMargin,
                  Md3Dimens.gutter,
                  Md3Dimens.compactMargin,
                  Md3Dimens.compactMargin + 24,
                ),
                children: [
                  _DeviceCard(
                    state: state,
                    storage: _storage,
                    storageLoading: _storageLoading,
                    connecting: _connecting,
                    onConnect: () => _connect(),
                    onDisconnect: _disconnect,
                    onRefresh: _refreshDevice,
                  ),
                  const SizedBox(height: Md3Dimens.gutter * 2),
                  _SyncCard(
                    autoSync: _autoSync,
                    autoConnect: _autoConnect,
                    syncing: _syncing,
                    hint: _syncHint,
                    connected: _connected,
                    onAutoSyncChanged: _setAutoSync,
                    onAutoConnectChanged: _setAutoConnect,
                    onSyncAll: () => _syncAll(),
                  ),
                  const SizedBox(height: Md3Dimens.gutter * 2),
                  Card.outlined(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.swap_vert_circle_outlined),
                      title: const Text('传书传输页'),
                      subtitle: const Text('多选书目、传书设置与实时进度'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openTransferPage,
                    ),
                  ),
                  if (state.busy) ...[
                    const SizedBox(height: Md3Dimens.gutter * 2),
                    _TransferCard(
                      state: state,
                      onCancel: _cancelPush,
                      onView: _openTransferPage,
                    ),
                  ],
                  const SizedBox(height: Md3Dimens.gutter * 2),
                  md3SectionHeader(
                    context,
                    '可传书目',
                    trailing: Text(
                      '${_books.length} 本',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: Md3Dimens.gutter),
                  if (_books.isEmpty)
                    _EmptyHint(
                      text: '还没有可传的书。\n先在小说的详情页下载章节，或导入本地 TXT / EPUB。',
                    )
                  else
                    for (final entry in _books)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Md3Dimens.gutter * 2),
                        child: _BookCard(
                          entry: entry,
                          status: _bandStatus[entry.id],
                          reading: _bandReading[entry.id],
                          connected: _connected,
                          probing:
                              _probing == entry.id ||
                              (_probingAll && !_bandStatus.containsKey(entry.id)),
                          pushing: _pushing == entry.id,
                          busy: state.busy,
                          onPush: () => _push(entry),
                          onSync: () => _syncOne(entry),
                          onRefresh: () => _probe(entry),
                          onDelete: () => _deleteOnBand(entry),
                        ),
                      ),
                  const SizedBox(height: Md3Dimens.gutter),
                  _Footnote(connected: _connected),
                ],
              ),
            ),
    );
  }

  /// 传书前发现网络目录有新章节：先补到手机再传，还是只传手上现有的。
  Future<_UpdateFirstChoice?> _askUpdateFirst(BookUpdateInfo info) {
    return md3ShowModalSheet<_UpdateFirstChoice>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Md3Dimens.compactMargin,
              0,
              Md3Dimens.compactMargin,
              Md3Dimens.compactMargin,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '《${info.title}》有 ${info.pending.length} 章还没到手机'
                  '${info.fresh.isNotEmpty ? '（${info.fresh.length} 章是新更新）' : ''}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '先下载到手机再传，手环才能拿到这些章节；'
                  '跳过则只把手环缺的已有章节传过去。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.pop(sheetContext, _UpdateFirstChoice.download),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text('下载 ${info.pending.length} 章并传到手环'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(sheetContext, _UpdateFirstChoice.skip),
                  icon: const Icon(Icons.skip_next),
                  label: const Text('跳过更新，只传已有章节'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<_PushChoice?> _askIncrement({
    required String title,
    required int synced,
    required int missing,
    required int total,
  }) {
    return md3ShowModalSheet<_PushChoice>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Md3Dimens.compactMargin,
              0,
              Md3Dimens.compactMargin,
              Md3Dimens.compactMargin,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('《$title》', style: theme.textTheme.titleLarge),
                const SizedBox(height: Md3Dimens.gutter),
                Text(
                  '手环上已有 $synced/$total 章，缺 $missing 章。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Md3Dimens.gutter * 2),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.pop(sheetContext, _PushChoice.increment),
                  icon: const Icon(Icons.playlist_add_check),
                  label: Text('仅补缺失的 $missing 章'),
                ),
                const SizedBox(height: Md3Dimens.gutter),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(sheetContext, _PushChoice.full),
                  icon: const Icon(Icons.refresh),
                  label: const Text('整本重传'),
                ),
                const SizedBox(height: Md3Dimens.gutter),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _PushChoice { increment, full }

/// 传书前发现网络目录有新章节时，用户对「先补到手机」的选择。
enum _UpdateFirstChoice { download, skip }

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.state,
    required this.storage,
    required this.storageLoading,
    required this.connecting,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRefresh,
  });

  final BandTransferState state;
  final BandStorageInfo storage;
  final bool storageLoading;
  final bool connecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connected = state.connected;
    final device = state.device;

    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Md3Dimens.compactMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: connected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: Md3Shape.mediumRadius,
                  ),
                  child: Icon(
                    Icons.watch,
                    color: connected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: Md3Dimens.compactMargin),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device?.name ?? '小米手环',
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        connected
                            ? '已连接${state.bandVersion != null ? ' · 固件 ${state.bandVersion}' : ''}'
                            : (connecting
                                  ? (state.label.isNotEmpty
                                        ? state.label
                                        : '正在连接…')
                                  : (state.error ?? '未连接')),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: connected
                              ? scheme.primary
                              : (state.error != null && !connecting
                                    ? scheme.error
                                    : scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                if (connected)
                  IconButton(
                    onPressed: onRefresh,
                    tooltip: '刷新设备状态',
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            if (connected) ...[
              const SizedBox(height: Md3Dimens.compactMargin),
              _StorageBar(storage: storage, loading: storageLoading),
            ],
            const SizedBox(height: Md3Dimens.compactMargin),
            SizedBox(
              width: double.infinity,
              child: connected
                  ? OutlinedButton.icon(
                      onPressed: onDisconnect,
                      icon: const Icon(Icons.link_off),
                      label: const Text('断开连接'),
                    )
                  : FilledButton.icon(
                      onPressed: connecting ? null : onConnect,
                      icon: connecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bluetooth_searching),
                      label: Text(connecting ? '连接中…' : '连接手环'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageBar extends StatelessWidget {
  const _StorageBar({required this.storage, required this.loading});

  final BandStorageInfo storage;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasData = storage.totalStorage > 0;
    // 读取中 / 读取失败（超时回空）/ 已读到数据 三态区分：
    // 旧实现 totalStorage==0 一律显示「读取中…」，手环端不回包时永远挂着。
    final String statusText;
    if (hasData) {
      statusText =
          '${BandStorageInfo.formatBytes(storage.availableStorage)} 可用 / ${BandStorageInfo.formatBytes(storage.totalStorage)}';
    } else if (loading) {
      statusText = '读取中…';
    } else {
      statusText = '读取失败';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sd_storage_outlined, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('手环存储', style: theme.textTheme.labelLarge),
            const Spacer(),
            Text(
              statusText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasData
                    ? scheme.onSurfaceVariant
                    : (loading ? scheme.onSurfaceVariant : scheme.error),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(Md3Shape.full)),
          child: LinearProgressIndicator(
            value: hasData
                ? storage.usedFraction
                : (loading ? null : 0),
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        if (hasData) ...[
          const SizedBox(height: 6),
          Text(
            '已用 ${BandStorageInfo.formatBytes(storage.usedStorage)}'
            '${storage.product != null ? ' · ${storage.product}' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.autoSync,
    required this.autoConnect,
    required this.syncing,
    required this.hint,
    required this.connected,
    required this.onAutoSyncChanged,
    required this.onAutoConnectChanged,
    required this.onSyncAll,
  });

  final bool autoSync;
  final bool autoConnect;
  final bool syncing;
  final String? hint;
  final bool connected;
  final ValueChanged<bool> onAutoSyncChanged;
  final ValueChanged<bool> onAutoConnectChanged;
  final VoidCallback onSyncAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card.outlined(
      margin: EdgeInsets.zero,
        child: Column(
          children: [
            SwitchListTile(
              value: autoConnect,
              onChanged: onAutoConnectChanged,
              secondary: const Icon(Icons.watch_outlined),
              title: const Text('启动时自动连接手环'),
              subtitle: const Text('打开 App 后悄悄尝试连接，失败不打扰'),
            ),
            const Divider(height: 1),
            SwitchListTile(
              value: autoSync,
              onChanged: onAutoSyncChanged,
              secondary: const Icon(Icons.sync),
              title: const Text('连接后自动同步阅读数据'),
              subtitle: const Text('全部书目：进度取较新一端，时长按天合并'),
            ),
          const Divider(height: 1),
          ListTile(
            enabled: connected && !syncing,
            leading: syncing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_alt),
            title: Text(syncing ? (hint ?? '同步中…') : '立即同步全部'),
            subtitle: Text(
              connected ? '进度取较新一端，时长按天合并' : '连接手环后可用',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: connected && !syncing ? onSyncAll : null,
          ),
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.state,
    required this.onCancel,
    required this.onView,
  });

  final BandTransferState state;
  final VoidCallback onCancel;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Md3Dimens.compactMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.downloading ? Icons.cloud_download_outlined : Icons.upload,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.label.isEmpty ? '传输中' : state.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(onPressed: onView, child: const Text('查看')),
                TextButton(onPressed: onCancel, child: const Text('取消')),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(Md3Shape.full)),
              child: LinearProgressIndicator(
                value: state.fraction.clamp(0, 1),
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '第 ${state.sentChapters}/${state.totalChapters} 章',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const Spacer(),
                if (state.speed.isNotEmpty)
                  Text(
                    state.speed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                if (state.retries > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '重试 ${state.retries}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.entry,
    required this.status,
    required this.reading,
    required this.connected,
    required this.probing,
    required this.pushing,
    required this.busy,
    required this.onPush,
    required this.onSync,
    required this.onRefresh,
    required this.onDelete,
  });

  final BandBookEntry entry;
  final BandBookStatus? status;
  final BandReadingData? reading;
  final bool connected;
  final bool probing;
  final bool pushing;
  final bool busy;
  final VoidCallback onPush;
  final VoidCallback onSync;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = entry.chapters.length;
    final synced = status?.syncedChapters.length;
    final progress = (synced != null && total > 0) ? synced / total : 0.0;
    final minutes = ((reading?.totalSeconds ?? 0) / 60).round();

    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Md3Dimens.compactMargin,
          Md3Dimens.compactMargin,
          Md3Dimens.compactMargin,
          Md3Dimens.gutter,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (entry.author.isNotEmpty) entry.author,
                          entry.sourceLabel,
                          '$total 章',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: connected && !probing ? onRefresh : null,
                  tooltip: '刷新手环进度',
                  icon: probing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            if (connected) ...[
              const SizedBox(height: Md3Dimens.gutter),
              Row(
                children: [
                  Icon(Icons.menu_book_outlined, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      synced == null
                          ? '正在读取手环状态…'
                          : synced == 0
                          ? '手环上还没有这本书'
                          : '手环已有 $synced/$total 章',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: synced == null ? scheme.onSurfaceVariant : scheme.onSurface,
                      ),
                    ),
                  ),
                  if (reading?.chapterIndex != null)
                    Text(
                      '读至第 ${reading!.chapterIndex! + 1} 章',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(Md3Shape.full)),
                child: LinearProgressIndicator(
                  value: synced == null ? null : progress,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              if (minutes > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      '手环累计阅读 ${minutes >= 60 ? '${minutes ~/ 60} 小时 ${minutes % 60} 分' : '$minutes 分钟'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: Md3Dimens.compactMargin),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: connected && !busy && !pushing ? onPush : null,
                  icon: pushing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(pushing ? '传输中' : '传书'),
                ),
                const SizedBox(width: Md3Dimens.gutter),
                IconButton(
                  onPressed: connected && !busy ? onSync : null,
                  tooltip: '同步阅读数据',
                  icon: const Icon(Icons.sync_alt),
                ),
                IconButton(
                  onPressed: connected && !busy ? onDelete : null,
                  tooltip: '删除手环副本',
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.import_contacts_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: Md3Dimens.compactMargin),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        md3SectionHeader(context, '说明'),
        const SizedBox(height: Md3Dimens.gutter),
        Text(
          '· 传书时手机若还在下载，会一边下一边传，不必等整本下完。\n'
          '· 增量同步只补手环缺的章节，已存在的不会重传。\n'
          '· 进度以读得更远的一端为准；时长按天取较大值合并，不会重复累加。\n'
          '· 手环端需装配套的「弦电子书」rpk（同包名 + 同签名）。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
        if (!connected) ...[
          const SizedBox(height: Md3Dimens.gutter),
          Text(
            '当前未连接：先打开手环上的「电子书」，再点上方「连接手环」。',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
      ],
    );
  }
}
