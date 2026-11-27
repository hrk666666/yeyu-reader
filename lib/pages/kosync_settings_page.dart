import 'dart:async';

import 'package:flutter/material.dart';

import '../services/kosync/kosync_client.dart';
import '../services/kosync/kosync_preferences.dart';
import '../services/kosync/kosync_sync_service.dart';
import '../theme/md3.dart';
import '../widgets/settings/settings_widgets.dart';

/// 阅读进度同步（kosync）设置页。
///
/// 同步走的是 KOReader 用的那套 kosync 协议，所以同一个同步服务器既能给
/// 页屿用，也能给 KOReader 用。服务器可以是官方的公共服务，也可以是用户
/// 自己起的 `koreader-sync-server`（局域网里常见）。
///
/// 口令只保存 MD5：协议本身也只用 MD5 鉴权，明文口令没有上传的必要，
/// 留着反而多一份泄露面。
class KosyncSettingsPage extends StatefulWidget {
  const KosyncSettingsPage({super.key});

  @override
  State<KosyncSettingsPage> createState() => _KosyncSettingsPageState();
}

class _KosyncSettingsPageState extends State<KosyncSettingsPage> {
  final TextEditingController _serverController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _deviceController = TextEditingController();

  bool _enabled = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String _status = '';
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    // 填好的地址与账号不点任何按钮也要留住：保存不依赖界面，离开时补写一次。
    unawaited(_save(enabled: null));
    _serverController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _deviceController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final prefs = KosyncPreferences.instance;
    await prefs.load();
    if (!mounted) return;
    setState(() {
      _enabled = prefs.enabled.value;
      _serverController.text = prefs.serverUrl.value;
      _userController.text = prefs.username.value;
      _deviceController.text = prefs.deviceName.value;
    });
  }

  /// 把界面上填的内容存进配置。
  ///
  /// 口令框留空表示不改口令——已经存过 MD5 的用户不必每次进来都重输。
  Future<void> _save({required bool? enabled}) async {
    final prefs = KosyncPreferences.instance;
    await prefs.setServerUrl(_serverController.text);
    await prefs.setUsername(_userController.text);
    await prefs.setDeviceName(_deviceController.text);
    final password = _passwordController.text;
    if (password.isNotEmpty) {
      await prefs.setPassword(password);
      _passwordController.clear();
    }
    if (enabled != null) await prefs.setEnabled(enabled);
    KosyncSyncService.instance.invalidate();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '';
      _statusOk = false;
    });
    try {
      await action();
    } on KosyncException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.localizedMessage;
        _statusOk = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '操作失败：$error';
        _statusOk = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() async {
    await _run(() async {
      await _save(enabled: null);
      final ok = await KosyncSyncService.instance.verifyCredentials();
      if (!mounted) return;
      setState(() {
        _status = ok ? '连接成功，账号可用' : '连接成功，但服务器没有认可这个账号';
        _statusOk = ok;
      });
    });
  }

  Future<void> _register() async {
    await _run(() async {
      await _save(enabled: null);
      await KosyncSyncService.instance.registerAccount();
      if (!mounted) return;
      setState(() {
        _status = '注册成功，现在可以在手机上用这个账号同步进度';
        _statusOk = true;
      });
    });
  }

  /// 清掉本地保存的账号与口令。服务器上的记录不受影响。
  Future<void> _clearAccount() async {
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '清除账号信息',
      message: '本地保存的账号与口令会被删除，需要时重新填写。服务器上的记录不受影响。',
      confirmLabel: '清除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(() async {
      await KosyncPreferences.instance.clear();
      KosyncSyncService.instance.invalidate();
      _passwordController.clear();
      if (!mounted) return;
      _userController.clear();
      setState(() {
        _enabled = false;
        _status = '已清除本地账号信息';
        _statusOk = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsScaffold(
      title: '阅读进度同步',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SettingsGroupCard(
            children: [
              SettingsRow(
                icon: Icons.cloud_sync_outlined,
                title: '启用进度同步',
                subtitle: '把读到哪一章同步到服务器',
                trailing: SettingsSwitch(
                  value: _enabled,
                  onChanged: _busy
                      ? null
                      : (value) async {
                          await _save(enabled: value);
                          if (mounted) setState(() => _enabled = value);
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SettingsGroupCard(
            showDividers: false,
            children: [
              _field(
                controller: _serverController,
                label: '同步服务器地址',
                hint: KosyncPreferences.defaultServerUrl,
                keyboardType: TextInputType.url,
              ),
              _field(
                controller: _userController,
                label: '账号',
                hint: '在服务器上注册的账号名',
              ),
              _field(
                controller: _passwordController,
                label: '口令',
                hint: '只保存 MD5，明文不会留在设备上',
                obscure: _obscurePassword,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              _field(
                controller: _deviceController,
                label: '设备名称',
                hint: '同步记录里显示的设备名',
              ),
            ],
          ),
          const SizedBox(height: 14),
          SettingsGroupCard(
            children: [
              SettingsRow(
                icon: Icons.wifi_tethering,
                title: '测试连接',
                subtitle: '用当前账号向服务器验一次身份',
                enabled: !_busy,
                trailing: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _busy ? null : _testConnection,
              ),
              SettingsRow(
                icon: Icons.person_add_alt,
                title: '注册账号',
                subtitle: '在服务器上创建这个账号',
                enabled: !_busy,
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _register,
              ),
              SettingsRow(
                icon: Icons.delete_outline,
                title: '清除账号信息',
                subtitle: '删掉本地保存的账号与口令，不影响服务器上的数据',
                enabled: !_busy,
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _clearAccount,
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _statusOk
                    ? scheme.primaryContainer
                    : scheme.errorContainer,
                borderRadius: BorderRadius.circular(Md3Shape.large),
              ),
              child: Text(
                _status,
                style: TextStyle(
                  color: _statusOk
                      ? scheme.onPrimaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '同步服务器可以填官方公共服务，也可以填自己部署的服务地址。'
              '局域网里的服务请填 http:// 开头的地址，例如 '
              'http://192.168.1.10:7200。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: suffix,
          isDense: true,
        ),
      ),
    );
  }
}
