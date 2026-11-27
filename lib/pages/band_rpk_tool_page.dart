import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/band_rpk/band_rpk_service.dart';
import '../services/band_rpk/rpk_repack.dart';
import '../services/book_txt_export.dart' show ExportTarget, ExportWriteException;

/// 手环安装包工具：导入官方 rpk，改包名重签，另存或分享。
///
/// 手环上的快应用由「包名 + 签名」定位，两个包同名就只能留一个。内置书版本
/// 一旦覆盖安装，官方的传书入口就找不到它了；把包名改掉再重签，两个包可以
/// 同时在手环里存在，互不影响。
class BandRpkToolPage extends StatefulWidget {
  const BandRpkToolPage({super.key});

  @override
  State<BandRpkToolPage> createState() => _BandRpkToolPageState();
}

class _BandRpkToolPageState extends State<BandRpkToolPage> {
  final BandRpkService _service = BandRpkService.shared;
  final TextEditingController _packageController = TextEditingController();

  RpkSource? _source;
  RpkManifest? _manifest;
  RpkArtifact? _artifact;

  bool _rename = true;
  bool _busy = false;
  bool _packageEdited = false;
  String? _stage;
  String? _error;
  String? _packageError;

  @override
  void dispose() {
    _packageController.dispose();
    super.dispose();
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
      if (!mounted) return;
      setState(() {
        _source = picked;
        _manifest = manifest;
        _packageEdited = false;
        _packageController.text = _defaultPackage(manifest.package);
        _packageError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  String _defaultPackage(String original) {
    // 官方包名一般以 .reader 收尾，加 .seed 一眼能看出是「内置书版」。
    return original.endsWith('.seed') ? original : '$original.seed';
  }

  void _onPackageChanged(String value) {
    _packageEdited = true;
    setState(() => _packageError = validatePackageName(value.trim()));
  }

  Future<void> _build() async {
    final source = _source;
    if (source == null) return;
    final target = _packageController.text.trim();
    if (_rename) {
      final error = validatePackageName(target);
      if (error != null) {
        setState(() => _packageError = error);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _artifact = null;
      _stage = _rename ? '准备签名密钥' : '读取安装包';
    });
    try {
      final artifact = _rename
          ? await _service.build(
              source: source,
              newPackage: target,
              onStage: (stage) {
                if (mounted) setState(() => _stage = stage);
              },
            )
          : _service.passthrough(source);
      if (!mounted) return;
      setState(() {
        _artifact = artifact;
        _busy = false;
        _stage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = null;
        _error = '$error';
      });
    }
  }

  Future<void> _save() async {
    final artifact = _artifact;
    if (artifact == null) return;
    try {
      final target = await _service.saveToDownloads(artifact);
      if (!mounted) return;
      _toast(_targetMessage(target));
    } catch (error) {
      if (!mounted) return;
      _toast(error is ExportWriteException ? error.message : '$error');
    }
  }

  Future<void> _share() async {
    final artifact = _artifact;
    if (artifact == null) return;
    final ok = await _service.shareFile(artifact);
    if (!mounted) return;
    if (!ok) _toast('没有找到能接收安装包的应用');
  }

  String _targetMessage(ExportTarget target) {
    if (!target.isPublic) {
      return '系统版本较旧，已存到应用目录：${target.path}';
    }
    return '已保存到下载目录：${target.path}';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _source;
    final manifest = _manifest;
    return Scaffold(
      appBar: AppBar(title: const Text('手环安装包工具')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          _intro(theme),
          const SizedBox(height: 12),
          _fileCard(theme, source, manifest),
          if (manifest != null) ...<Widget>[
            const SizedBox(height: 12),
            _renameCard(theme, manifest),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _build,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_rename ? Icons.auto_fix_high : Icons.inventory_2_outlined),
              label: Text(_busy
                  ? (_stage ?? '处理中')
                  : (_rename ? '生成共存版安装包' : '准备原包')),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            _errorCard(theme, _error!),
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
            Text('两个版本可以同时装', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '手环按「包名 + 签名」区分快应用，同名只能装一个。'
              '改掉包名并重新签名后，这个包不会顶掉手环上已有的页屿，'
              '两边数据各自独立。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '签名用本机生成的密钥，首次使用需要等几秒。'
              '改包名的版本与手机端不再互认，传书、唤起都要用原包名那份。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileCard(ThemeData theme, RpkSource? source, RpkManifest? manifest) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: Text(source?.name ?? '还没有选择安装包'),
            subtitle: Text(
              source == null
                  ? '选择手环端 rpk（官方包或内置书版本都可以）'
                  : _formatSize(source.bytes.length),
            ),
            trailing: TextButton(
              onPressed: _busy ? null : _pick,
              child: Text(source == null ? '选择' : '重选'),
            ),
          ),
          if (manifest != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: <Widget>[
                  _row(theme, '应用名', manifest.name),
                  _row(theme, '原包名', manifest.package),
                  _row(
                    theme,
                    '版本',
                    '${manifest.versionName}（${manifest.versionCode}）',
                  ),
                  _row(theme, '页面', '${manifest.pageCount} 个'),
                ],
              ),
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
            title: const Text('改包名，实现共存'),
            subtitle: const Text('关闭后直接使用原包，不重签名'),
          ),
          if (_rename)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _packageController,
                enabled: !_busy,
                autocorrect: false,
                keyboardType: TextInputType.url,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.]')),
                ],
                decoration: InputDecoration(
                  labelText: '新包名',
                  helperText: '只能包含字母、数字、下划线，用点分段',
                  errorText: _packageError,
                  suffixIcon: _packageEdited
                      ? IconButton(
                          tooltip: '恢复默认',
                          icon: const Icon(Icons.restart_alt),
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _packageController.text =
                                        _defaultPackage(manifest.package);
                                    _packageEdited = false;
                                    _packageError = null;
                                  }),
                        )
                      : null,
                ),
                onChanged: _onPackageChanged,
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultCard(ThemeData theme, RpkArtifact artifact) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('已生成', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(artifact.fileName, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              artifact.renamed
                  ? '${artifact.oldPackage} → ${artifact.newPackage}'
                  : '包名未改动：${artifact.newPackage}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              artifact.renamed
                  ? '${artifact.fileCount} 个文件 · ${_formatSize(artifact.sizeBytes)}'
                  : _formatSize(artifact.sizeBytes),
              style: theme.textTheme.bodySmall,
            ),
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
                  child: FilledButton.icon(
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

  Widget _errorCard(ThemeData theme, String message) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 64,
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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
