import 'dart:async';

import 'package:flutter/material.dart';

import '../services/band_rpk/band_rpk_service.dart';
import '../services/band_rpk/rpk_repack.dart';
import '../services/band_seed/seed_books.dart';
import '../services/band_seed/seed_injector.dart';
import '../services/book_txt_export.dart' show ExportTarget, ExportWriteException;
import '../services/imported_book_store.dart';

/// 内置书安装包：把书架里的本地书塞进手环 rpk，装完打开就有书。
///
/// 只能塞进「app.js 明文 + 页面 jsc」的混合包：注入是纯文本操作，纯 jsc 构建
/// 的包没有可改的入口脚本。所以这里要选一个混合构建的基座包，而不是随便一个
/// 官方包。写入发生在手环首次启动、首帧渲染之后，已存在的书不会被覆盖。
class BandSeedPage extends StatefulWidget {
  const BandSeedPage({super.key, this.store, this.service});

  /// 测试注入用；缺省走真实实现。
  final ImportedBookStore? store;
  final BandRpkService? service;

  @override
  State<BandSeedPage> createState() => _BandSeedPageState();
}

class _BandSeedPageState extends State<BandSeedPage> {
  late final ImportedBookStore _store = widget.store ?? ImportedBookStore.instance;
  late final BandRpkService _service = widget.service ?? BandRpkService.shared;
  final TextEditingController _packageController = TextEditingController();

  RpkSource? _source;
  RpkManifest? _manifest;
  SeedEntryKind _entryKind = SeedEntryKind.unknown;

  List<ImportedBook> _books = const <ImportedBook>[];
  final Set<String> _selected = <String>{};
  bool _loadingBooks = true;
  String? _booksError;

  bool _rename = true;
  bool _busy = false;
  String? _stage;
  String? _error;
  String? _packageError;
  RpkArtifact? _artifact;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBooks());
  }

  @override
  void dispose() {
    _packageController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks() async {
    try {
      final books = await _store.books();
      if (!mounted) return;
      setState(() {
        _books = books;
        _loadingBooks = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _booksError = '$error';
        _loadingBooks = false;
      });
    }
  }

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _artifact = null;
    });
    try {
      final picked = await _service.pick();
      if (picked == null) return;
      final manifest = _service.inspect(picked);
      final kind = detectEntryKind(rpkEntryNames(picked.bytes));
      if (!mounted) return;
      setState(() {
        _source = picked;
        _manifest = manifest;
        _entryKind = kind;
        _packageController.text = _defaultPackage(manifest.package);
        _packageError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is FormatException ? error.message : '$error');
    }
  }

  String _defaultPackage(String original) {
    if (original.isEmpty) return 'com.yeyu.reader.seed';
    return original.endsWith('.seed') ? original : '$original.seed';
  }

  void _toggle(String bookId, bool selected) {
    setState(() {
      _artifact = null;
      if (selected) {
        _selected.add(bookId);
      } else {
        _selected.remove(bookId);
      }
    });
  }

  Future<void> _build() async {
    final source = _source;
    if (source == null) return;
    if (_selected.isEmpty) {
      _toast('先选至少一本书');
      return;
    }
    final target = _rename ? _packageController.text.trim() : null;
    if (_rename) {
      final problem = validatePackageName(target!);
      if (problem != null) {
        setState(() => _packageError = problem);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _packageError = null;
      _artifact = null;
      _stage = '读取书稿';
    });
    try {
      final chosen = _books.where((b) => _selected.contains(b.id)).toList();
      final sources = <SeedSourceBook>[];
      for (var i = 0; i < chosen.length; i++) {
        final book = chosen[i];
        if (mounted) {
          setState(() => _stage = '读取《${book.title}》(${i + 1}/${chosen.length})');
        }
        final chapters = <SeedSourceChapter>[];
        for (final chapter in book.chapters) {
          final text = await _store.chapterText(book.id, chapter.itemId);
          chapters.add(SeedSourceChapter(title: chapter.title, text: text));
        }
        sources.add(SeedSourceBook(
          title: book.title,
          author: book.author,
          chapters: chapters,
        ));
      }
      if (!mounted) return;
      final artifact = await _service.buildSeeded(
        source: source,
        books: sources,
        newPackage: target,
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (!mounted) return;
      setState(() {
        _artifact = artifact;
        _busy = false;
        _stage = null;
      });
    } on SeedInjectException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.detail;
        _busy = false;
        _stage = null;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _busy = false;
        _stage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _busy = false;
        _stage = null;
      });
    }
  }

  Future<void> _save() async {
    final artifact = _artifact;
    if (artifact == null) return;
    try {
      final target = await _service.saveToDownloads(artifact);
      if (!mounted) return;
      _toast('已存到${_describe(target)}');
    } on ExportWriteException catch (error) {
      if (!mounted) return;
      _toast(error.message);
    }
  }

  Future<void> _share() async {
    final artifact = _artifact;
    if (artifact == null) return;
    final ok = await _service.shareFile(artifact);
    if (!mounted || ok) return;
    _toast('没有可用的分享目标');
  }

  String _describe(ExportTarget target) =>
      target.isPublic ? '下载目录：${target.path}' : target.path;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manifest = _manifest;
    return Scaffold(
      appBar: AppBar(title: const Text('内置书安装包')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          _intro(theme),
          const SizedBox(height: 12),
          _fileCard(theme),
          if (_entryKind == SeedEntryKind.bytecode) ...<Widget>[
            const SizedBox(height: 12),
            _notice(
              theme,
              Icons.info_outline,
              '这个包只有 app.jsc，塞不了书',
              'app.jsc 是编译后的字节码，改不了。要用 app.js 明文的混合构建包当基座。',
            ),
          ],
          const SizedBox(height: 12),
          _booksCard(theme),
          if (manifest != null) ...<Widget>[
            const SizedBox(height: 12),
            _renameCard(theme, manifest),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || _entryKind != SeedEntryKind.plainJs
                  ? null
                  : _build,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check),
              label: Text(_busy ? (_stage ?? '处理中') : '生成内置书安装包'),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            _notice(theme, Icons.error_outline, '没能生成', _error!),
          ],
          if (_artifact != null) ...<Widget>[
            const SizedBox(height: 12),
            _resultCard(theme, _artifact!),
          ],
        ],
      ),
    );
  }

  Widget _intro(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('装完打开就有书', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '把本地书打进手环安装包，表上装好后首次打开自动写入，'
              '不需要再连手机传书。已存在的书不会被覆盖。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '只能塞进「app.js 明文 + 页面 jsc」的混合包：注入是改文本，'
              '纯 jsc 包没有可改的入口。建议一包不超过 14 万字，再多会吃紧手环内存。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileCard(ThemeData theme) {
    final source = _source;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: Text(source?.name ?? '还没有选择基座包'),
            subtitle: Text(
              source == null
                  ? '选择手环端 rpk（必须带 app.js 明文）'
                  : '入口脚本：${_entryKind == SeedEntryKind.plainJs ? 'app.js 明文，可以塞书' : 'app.jsc 字节码，塞不了'}',
            ),
            trailing: TextButton(
              onPressed: _busy ? null : _pick,
              child: Text(source == null ? '选择' : '换一个'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _booksCard(ThemeData theme) {
    if (_loadingBooks) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_booksError != null) {
      return _notice(theme, Icons.error_outline, '读不到本地书', _booksError!);
    }
    if (_books.isEmpty) {
      return _notice(
        theme,
        Icons.library_books_outlined,
        '书架里还没有本地书',
        '内置书只打包本地导入的书（TXT / EPUB）。先从书架导入，再回来做安装包。',
      );
    }
    final chapters = _selected
        .map((id) => _books.firstWhere((b) => b.id == id))
        .fold<int>(0, (sum, book) => sum + book.chapters.length);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.library_books_outlined),
            title: const Text('选择要打进包里的书'),
            subtitle: Text(_selected.isEmpty
                ? '共 ${_books.length} 本可选'
                : '已选 ${_selected.length} 本 / $chapters 章'),
          ),
          for (final book in _books)
            CheckboxListTile(
              value: _selected.contains(book.id),
              onChanged: _busy
                  ? null
                  : (value) => _toggle(book.id, value ?? false),
              title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${book.author.isEmpty ? '佚名' : book.author} · ${book.chapters.length} 章',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              dense: true,
            ),
        ],
      ),
    );
  }

  Widget _renameCard(ThemeData theme, RpkManifest manifest) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: <Widget>[
          SwitchListTile(
            value: _rename,
            onChanged: _busy
                ? null
                : (value) => setState(() => _rename = value),
            title: const Text('改包名，与原版共存'),
            subtitle: const Text('不改就只能顶掉手环上的原版页屿'),
          ),
          if (_rename)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _packageController,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: '包名',
                  errorText: _packageError,
                  helperText: '默认在原包名后加 .seed',
                ),
                onChanged: (value) {
                  final problem = validatePackageName(value.trim());
                  setState(() => _packageError = problem);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultCard(ThemeData theme, RpkArtifact artifact) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('打包完成', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row(theme, '文件', artifact.fileName),
            _row(theme, '大小', _formatSize(artifact.sizeBytes)),
            _row(theme, '包名', artifact.renamed
                ? '${artifact.oldPackage} → ${artifact.newPackage}'
                : artifact.newPackage),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _save,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('存到下载'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('分享'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(
    ThemeData theme,
    IconData icon,
    String title,
    String body,
  ) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
