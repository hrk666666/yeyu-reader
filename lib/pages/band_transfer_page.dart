import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/band_book/band_book_catalog.dart';
import '../services/band_book/band_book_remote.dart';
import '../services/band_book/band_book_transfer.dart';
import '../services/book_update_service.dart';
import '../theme/md3.dart';
import '../widgets/wenku/src/app_haptics.dart';

/// 设置项键：断线后是否自动重连续传。
const String _autoRetryKey = 'band_transfer_auto_retry';

/// 设置项键：传书前是否先把网络更新下载到手机。
const String _updateFirstKey = 'band_transfer_update_first';

/// 设置项键：传书范围策略（[BandPushMode.name]）。
const String _syncModeKey = 'band_transfer_sync_mode';

/// 传书范围策略。
enum BandPushMode {
  /// 手环上没传过就整本传，传过就只补缺的章节。
  auto,

  /// 只补手环缺失的章节。
  increment,

  /// 忽略手环状态，整本重传。
  full;

  static BandPushMode parse(String? raw) => switch (raw) {
    'increment' => BandPushMode.increment,
    'full' => BandPushMode.full,
    _ => BandPushMode.auto,
  };
}

/// 一轮批量传书的策略快照（点「开始传输」时从设置区取）。
@immutable
class BandPushOptions {
  const BandPushOptions({
    this.autoRetry = true,
    this.updateFirst = true,
    this.mode = BandPushMode.auto,
  });

  final bool autoRetry;
  final bool updateFirst;
  final BandPushMode mode;
}

/// 单本书的传输结果。
enum BandTransferOutcome { success, failed, skipped }

@immutable
class BandTransferResult {
  const BandTransferResult({
    required this.title,
    required this.outcome,
    this.message = '',
  });

  final String title;
  final BandTransferOutcome outcome;
  final String message;
}

/// 批量传书队列（进程内单例）：传输中离开页面不中断，回来接着看结果。
class BandTransferSession extends ChangeNotifier {
  BandTransferSession._();

  static final BandTransferSession instance = BandTransferSession._();

  final List<BandTransferResult> results = <BandTransferResult>[];

  /// 队列是否在跑（含两本之间的准备 / 下载更新阶段）。
  bool running = false;

  /// 队列当前处理到的书名与阶段文案。
  String? currentTitle;
  String phaseLabel = '';

  int _total = 0;
  bool _cancelRequested = false;

  int get total => _total;

  /// 按 [books] 顺序逐本传输；已有任务在跑时直接返回。
  Future<void> start({
    required List<BandBookEntry> books,
    required BandPushOptions options,
  }) async {
    if (running || books.isEmpty) return;
    running = true;
    _cancelRequested = false;
    _total = books.length;
    results.clear();
    currentTitle = null;
    phaseLabel = '连接手环';
    notifyListeners();

    final transfer = BandBookTransfer.shared;
    final remote = BandBookRemote(transfer);
    try {
      if (!transfer.state.connected) {
        await transfer.connect(reuse: true);
      }
      if (!transfer.state.connected) {
        final error = transfer.state.error ?? '手环未连接';
        for (final book in books) {
          results.add(
            BandTransferResult(
              title: book.title,
              outcome: BandTransferOutcome.failed,
              message: error,
            ),
          );
        }
        return;
      }
      for (final book in books) {
        if (_cancelRequested) {
          results.add(
            BandTransferResult(
              title: book.title,
              outcome: BandTransferOutcome.skipped,
              message: '已取消',
            ),
          );
          continue;
        }
        currentTitle = book.title;
        phaseLabel = '准备';
        notifyListeners();
        results.add(await _runOne(book, options, remote));
        notifyListeners();
      }
    } finally {
      running = false;
      currentTitle = null;
      phaseLabel = '';
      notifyListeners();
    }
  }

  /// 取消整条队列：当前这本立刻断，排在后面的记为已取消。
  Future<void> cancel() async {
    if (!running) return;
    _cancelRequested = true;
    await BandBookTransfer.shared.cancel();
    notifyListeners();
  }

  Future<BandTransferResult> _runOne(
    BandBookEntry entry,
    BandPushOptions options,
    BandBookRemote remote,
  ) async {
    final transfer = BandBookTransfer.shared;
    var current = entry;

    // 「有更新先下载再传」：网络目录比本地新时先补到手机，手环才能拿到
    // 新章节。检测失败（离线 / 非缓存书）不阻塞，用手上章节继续。
    if (options.updateFirst) {
      phaseLabel = '检查更新';
      notifyListeners();
      try {
        final info = await BookUpdateService().check(
          current.id,
          title: current.title,
        );
        if (info.hasPending) {
          phaseLabel = '下载更新 ${info.pending.length} 章';
          notifyListeners();
          await BookUpdateService().downloadPending(info);
          final books = await BandBookCatalog().load();
          // 目录刷新后重取条目：loadChapter 闭包绑定的是旧目录下标。
          current = books.where((b) => b.id == current.id).firstOrNull ?? current;
        }
      } catch (_) {
        // 保持原条目继续传书。
      }
    }

    if (_cancelRequested) {
      return BandTransferResult(
        title: current.title,
        outcome: BandTransferOutcome.skipped,
        message: '已取消',
      );
    }

    phaseLabel = '查询手环进度';
    notifyListeners();
    final status = await remote.status(current.title);
    final missing = status.missingFrom(current.chapters.length);
    List<int>? chapters;
    switch (options.mode) {
      case BandPushMode.full:
        chapters = null;
      case BandPushMode.increment:
        if (missing.isEmpty) {
          return BandTransferResult(
            title: current.title,
            outcome: BandTransferOutcome.skipped,
            message: '手环上已是最新',
          );
        }
        chapters = missing;
      case BandPushMode.auto:
        if (status.syncedChapters.isEmpty) {
          chapters = null;
        } else if (missing.isEmpty) {
          return BandTransferResult(
            title: current.title,
            outcome: BandTransferOutcome.skipped,
            message: '手环上已是最新',
          );
        } else {
          chapters = missing;
        }
    }

    if (_cancelRequested) {
      return BandTransferResult(
        title: current.title,
        outcome: BandTransferOutcome.skipped,
        message: '已取消',
      );
    }

    phaseLabel = '传输';
    notifyListeners();
    final ok = await transfer.sendBook(
      title: current.title,
      chapterTitles: current.chapterTitles,
      loadChapter: current.loadChapter,
      chapters: chapters,
      totalChapters: current.chapters.length,
      author: current.author,
      wordCount: current.wordCount,
      autoRetry: options.autoRetry,
    );
    if (ok) {
      return BandTransferResult(
        title: current.title,
        outcome: BandTransferOutcome.success,
        message: chapters == null ? '整本已送达' : '已补 ${chapters.length} 章',
      );
    }
    if (_cancelRequested) {
      return BandTransferResult(
        title: current.title,
        outcome: BandTransferOutcome.skipped,
        message: '已取消',
      );
    }
    return BandTransferResult(
      title: current.title,
      outcome: BandTransferOutcome.failed,
      message: transfer.state.error ?? '传输失败',
    );
  }
}

/// 独立的传书传输页：传书设置 + 书目多选 + 实时进度与结果。
class BandTransferPage extends StatefulWidget {
  const BandTransferPage({
    super.key,
    this.initialSelection,
    this.initialBandStatus,
  });

  /// 打开页面时已勾选的书目，同时用作书目列表（避免重复扫描本机书库）。
  final List<BandBookEntry>? initialSelection;

  /// 已探明的手环章节进度，用于书目选择区显示「已同步 X/N」。
  final Map<String, BandBookStatus>? initialBandStatus;

  @override
  State<BandTransferPage> createState() => _BandTransferPageState();
}

class _BandTransferPageState extends State<BandTransferPage> {
  final BandBookTransfer _transfer = BandBookTransfer.shared;
  late final BandBookRemote _remote = BandBookRemote(_transfer);
  final BandTransferSession _session = BandTransferSession.instance;
  late final Listenable _live = Listenable.merge([_transfer, _session]);

  final Map<String, BandBookStatus> _bandStatus = <String, BandBookStatus>{};
  final Set<String> _selected = <String>{};

  List<BandBookEntry> _books = const <BandBookEntry>[];
  bool _loading = true;
  bool _probing = false;

  bool _autoRetry = true;
  bool _updateFirst = true;
  BandPushMode _mode = BandPushMode.auto;

  @override
  void initState() {
    super.initState();
    final initialStatus = widget.initialBandStatus;
    if (initialStatus != null) _bandStatus.addAll(initialStatus);
    unawaited(_load());
    unawaited(_loadPrefs());
  }

  Future<void> _load() async {
    final List<BandBookEntry> books;
    if (widget.initialSelection case final initial?) {
      books = initial;
    } else {
      books = await BandBookCatalog().load();
    }
    if (!mounted) return;
    setState(() {
      _books = books;
      if (widget.initialSelection != null) {
        _selected
          ..clear()
          ..addAll([for (final b in books) b.id]);
      }
      _loading = false;
    });
    unawaited(_probeAll());
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoRetry = sp.getBool(_autoRetryKey) ?? true;
      _updateFirst = sp.getBool(_updateFirstKey) ?? true;
      _mode = BandPushMode.parse(sp.getString(_syncModeKey));
    });
  }

  Future<void> _setAutoRetry(bool value) async {
    setState(() => _autoRetry = value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_autoRetryKey, value);
  }

  Future<void> _setUpdateFirst(bool value) async {
    setState(() => _updateFirst = value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_updateFirstKey, value);
  }

  Future<void> _setMode(BandPushMode value) async {
    setState(() => _mode = value);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_syncModeKey, value.name);
  }

  /// 逐本探一遍手环进度，让书目选择区显示「已同步 X/N」。
  Future<void> _probeAll() async {
    if (_probing || !mounted || !_transfer.state.connected) return;
    setState(() => _probing = true);
    try {
      for (final entry in _books) {
        if (!mounted || _transfer.state.busy) break;
        final status = await _remote.status(entry.title);
        if (!mounted) return;
        setState(() => _bandStatus[entry.id] = status);
      }
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  void _toggle(BandBookEntry entry, bool? value) {
    AppHaptics.play(context, HapticCue.selection);
    setState(() {
      if (value ?? false) {
        _selected.add(entry.id);
      } else {
        _selected.remove(entry.id);
      }
    });
  }

  void _selectAll() {
    AppHaptics.play(context, HapticCue.selection);
    setState(() {
      _selected
        ..clear()
        ..addAll([for (final b in _books) b.id]);
    });
  }

  void _invertSelection() {
    AppHaptics.play(context, HapticCue.selection);
    final current = Set<String>.of(_selected);
    setState(() {
      _selected
        ..clear()
        ..addAll([for (final b in _books) if (!current.contains(b.id)) b.id]);
    });
  }

  /// 开始传输：按列表顺序逐本进队列（不弹确认框，按设置自动决策）。
  Future<void> _start() async {
    final books = [
      for (final b in _books) if (_selected.contains(b.id)) b,
    ];
    if (books.isEmpty) return;
    AppHaptics.play(context, HapticCue.action);
    final options = BandPushOptions(
      autoRetry: _autoRetry,
      updateFirst: _updateFirst,
      mode: _mode,
    );
    await _session.start(books: books, options: options);
    if (!mounted) return;
    unawaited(_probeAll());
  }

  /// 取消：队列在跑就整条取消，否则只取消别处发起的单本传输。
  Future<void> _cancelTransfer() async {
    AppHaptics.play(context, HapticCue.warning);
    if (_session.running) {
      await _session.cancel();
    } else {
      await _transfer.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _live,
      builder: (context, _) {
        final theme = Theme.of(context);
        final session = _session;
        final state = _transfer.state;
        final busy = state.busy;

        return Scaffold(
          appBar: AppBar(
            title: const Text('传书传输'),
            actions: [
              if (_selected.isNotEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: Md3Dimens.compactMargin),
                    child: Text(
                      '已选 ${_selected.length} 本',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Md3Dimens.compactMargin,
                    Md3Dimens.gutter,
                    Md3Dimens.compactMargin,
                    Md3Dimens.compactMargin + 24,
                  ),
                  children: [
                    _buildSettings(context),
                    const SizedBox(height: Md3Dimens.gutter * 2),
                    md3SectionHeader(
                      context,
                      '选择书目',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _books.isEmpty ? null : _selectAll,
                            child: const Text('全选'),
                          ),
                          TextButton(
                            onPressed: _books.isEmpty ? null : _invertSelection,
                            child: const Text('反选'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Md3Dimens.gutter),
                    if (_books.isEmpty)
                      const _EmptyHint(
                        text: '还没有可传的书。\n先在小说的详情页下载章节，或导入本地 TXT / EPUB。',
                      )
                    else
                      for (final entry in _books)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: Md3Dimens.gutter,
                          ),
                          child: _BookSelectTile(
                            entry: entry,
                            status: _bandStatus[entry.id],
                            checked: _selected.contains(entry.id),
                            onChanged: (value) => _toggle(entry, value),
                          ),
                        ),
                    const SizedBox(height: Md3Dimens.gutter),
                    md3SectionHeader(context, '传输进度'),
                    const SizedBox(height: Md3Dimens.gutter),
                    _buildProgress(context),
                    if (session.results.isNotEmpty) ...[
                      const SizedBox(height: Md3Dimens.gutter * 2),
                      md3SectionHeader(
                        context,
                        '传输结果',
                        trailing: Text(
                          '${session.results.length} 本',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: Md3Dimens.gutter),
                      Card.outlined(
                        margin: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < session.results.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              _ResultTile(result: session.results[i]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Md3Dimens.compactMargin,
                Md3Dimens.gutter,
                Md3Dimens.compactMargin,
                Md3Dimens.compactMargin,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selected.isEmpty ? '未选择书目' : '已选 ${_selected.length} 本',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: session.running
                        ? _cancelTransfer
                        : (busy || _selected.isEmpty ? null : _start),
                    icon: session.running || busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      session.running
                          ? '取消传输'
                          : busy
                          ? '传输中'
                          : '开始传输',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettings(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile(
            value: _autoRetry,
            onChanged: _setAutoRetry,
            secondary: const Icon(Icons.restart_alt),
            title: const Text('自动重试断线续传'),
            subtitle: const Text('连接中断后自动重连，从断点接着传'),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _updateFirst,
            onChanged: _setUpdateFirst,
            secondary: const Icon(Icons.download_for_offline_outlined),
            title: const Text('有更新先下载再传'),
            subtitle: const Text('传书前先把网络新章节补到手机'),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Md3Dimens.compactMargin,
              Md3Dimens.gutter,
              Md3Dimens.compactMargin,
              Md3Dimens.gutter,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('传书范围', style: theme.textTheme.titleSmall),
                const SizedBox(height: Md3Dimens.gutter),
                SegmentedButton<BandPushMode>(
                  segments: const [
                    ButtonSegment(value: BandPushMode.auto, label: Text('自动')),
                    ButtonSegment(
                      value: BandPushMode.increment,
                      label: Text('仅增量'),
                    ),
                    ButtonSegment(value: BandPushMode.full, label: Text('整本')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) =>
                      _setMode(selection.first),
                ),
                const SizedBox(height: 6),
                Text(
                  switch (_mode) {
                    BandPushMode.auto =>
                      '自动：手环上没传过就整本传，传过就只补缺的章节。',
                    BandPushMode.increment =>
                      '仅增量：只传手环缺失的章节，不重传已有章节。',
                    BandPushMode.full => '整本：忽略手环状态，整本重传全部章节。',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = _transfer.state;
    final session = _session;
    final busy = state.busy;
    final running = session.running || busy;

    final String title;
    if (busy) {
      title = state.label.isEmpty
          ? (session.currentTitle ?? '传输中')
          : state.label;
    } else if (session.running) {
      title = session.currentTitle == null
          ? session.phaseLabel
          : '${session.currentTitle} · ${session.phaseLabel}';
    } else {
      title = '传输队列';
    }

    return Card.filled(
      margin: EdgeInsets.zero,
      color: running ? scheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(Md3Dimens.compactMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.downloading
                      ? Icons.cloud_download_outlined
                      : Icons.upload,
                  color: running
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: running
                          ? scheme.onSecondaryContainer
                          : scheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (session.running || busy)
                  TextButton(
                    onPressed: _cancelTransfer,
                    child: const Text('取消'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(Md3Shape.full),
              ),
              child: LinearProgressIndicator(
                value: busy
                    ? state.fraction.clamp(0, 1)
                    : (running ? null : 0),
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            if (running) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    session.running
                        ? '队列 ${session.results.length}/${session.total} 本'
                        : '第 ${state.sentChapters}/${state.totalChapters} 章',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  if (state.downloading) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.cloud_download_outlined,
                      size: 14,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '边下边传',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ],
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
            ] else ...[
              const SizedBox(height: 8),
              Text(
                '选择书目后点「开始传输」，按列表顺序逐本推到手环。\n'
                '传输中可以离开本页，队列会继续跑。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookSelectTile extends StatelessWidget {
  const _BookSelectTile({
    required this.entry,
    required this.status,
    required this.checked,
    required this.onChanged,
  });

  final BandBookEntry entry;
  final BandBookStatus? status;
  final bool checked;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = entry.chapters.length;
    final synced = status?.syncedChapters.length;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: CheckboxListTile(
        value: checked,
        onChanged: onChanged,
        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            entry.sourceLabel,
            '$total 章',
            if (synced != null) '已同步 $synced/$total',
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final BandTransferResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color, label) = switch (result.outcome) {
      BandTransferOutcome.success => (
        Icons.check_circle_outline,
        scheme.primary,
        '成功',
      ),
      BandTransferOutcome.failed => (
        Icons.error_outline,
        scheme.error,
        '失败',
      ),
      BandTransferOutcome.skipped => (
        Icons.skip_next_outlined,
        scheme.onSurfaceVariant,
        '跳过',
      ),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: result.message.isEmpty
          ? null
          : Text(result.message, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: color),
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
