import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_update_service.dart';
import 'settings_archive_rows.dart';

/// 立即检查更新并按需弹窗。设置页「立即检查更新」与关于页「检查更新」共用。
///
/// [autoPrompt] = true 时走启动静默路径：同一版本只提示一次
/// （[AppUpdateService.shouldAutoPrompt]），且已看过的公告不再弹。
/// 手动检查（false）：总是展示结果——有新版弹新版、没有则 SnackBar「已是最新」。
Future<void> checkUpdateNow(
  BuildContext context, {
  bool autoPrompt = false,
}) async {
  final result = await AppUpdateService().check();
  if (!context.mounted) return;
  await showUpdateFlow(context, result, autoPrompt: autoPrompt);
}

/// 拿既成的 [UpdateCheckResult] 走展示流程（启动静默检查复用，不二次请求）。
Future<void> showUpdateFlow(
  BuildContext context,
  UpdateCheckResult result, {
  bool autoPrompt = false,
}) async {
  if (!result.ok) {
    if (!autoPrompt) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新检查失败：${result.error ?? '未知错误'}')),
      );
    }
    return;
  }

  final manifest = result.manifest!;
  final ann = manifest.announcement;

  // 公告优先（先看完公告再谈更新）。
  if (ann != null && await AppUpdateService.shouldShowAnnouncement(ann)) {
    await AppUpdateService.markAnnouncementSeen(ann);
    if (!context.mounted) return;
    await _showAnnouncement(context, ann);
    if (!context.mounted) return;
  }

  if (!context.mounted) return;
  if (!result.hasUpdate) {
    if (!autoPrompt) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已是最新版本（${manifest.latest.versionName}，经 ${result.mirror}）',
          ),
        ),
      );
    }
    return;
  }

  // 自动提示对同一 versionCode 只弹一次。
  if (autoPrompt) {
    if (!await AppUpdateService.shouldAutoPrompt(manifest.latest.versionCode)) {
      return;
    }
    await AppUpdateService.markAutoPrompted(manifest.latest.versionCode);
    if (!context.mounted) return;
  }

  if (!context.mounted) return;
  await _showUpdateDialog(context, result);
}

Future<void> _showUpdateDialog(BuildContext context, UpdateCheckResult result) async {
  final info = result.manifest!.latest;
  final mustUpdate = result.mustUpdate;
  await showDialog<void>(
    context: context,
    barrierDismissible: !mustUpdate,
    builder: (context) => AlertDialog(
      title: Text('发现新版本 ${info.versionName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info.notes.isNotEmpty) Text(info.notes),
          const SizedBox(height: 12),
          Text(
            '点击「前往下载」前往更新页面。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        if (!mustUpdate)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            launchUrl(Uri.parse(info.url), mode: LaunchMode.externalApplication);
          },
          child: const Text('前往下载'),
        ),
      ],
    ),
  );
}

/// 信息公告弹窗：固定「公告」头部 + 图标，与「发现新版本」更新弹窗刻意区分，
/// 避免公告被误当成更新提示。
Future<void> _showAnnouncement(BuildContext context, Announcement ann) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.campaign_outlined),
      title: const Text('公告'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ann.title.isNotEmpty) ...[
            Text(ann.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          Text(ann.body),
        ],
      ),
      actions: [
        if (ann.url != null && ann.url!.isNotEmpty)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              launchUrl(Uri.parse(ann.url!), mode: LaunchMode.externalApplication);
            },
            child: const Text('查看详情'),
          ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// 「启动时检查更新」开关行。
class AutoUpdateCheckRow extends StatefulWidget {
  const AutoUpdateCheckRow({super.key});

  @override
  State<AutoUpdateCheckRow> createState() => _AutoUpdateCheckRowState();
}

class _AutoUpdateCheckRowState extends State<AutoUpdateCheckRow> {
  bool? _value;

  @override
  void initState() {
    super.initState();
    AppUpdateService.autoCheckEnabled().then((v) {
      if (mounted) setState(() => _value = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = _value ?? true;
    return SettingsToggleRow(
      icon: CupertinoIcons.arrow_down_circle,
      title: '启动时检查更新',
      description: '启动时从公开仓拉取 update.json 检查新版与公告，可关闭',
      value: value,
      onChanged: (v) async {
        setState(() => _value = v);
        await AppUpdateService.setAutoCheckEnabled(v);
      },
    );
  }
}

/// 「更新镜像」选择行：自动（测速优选）或手动钉死一个镜像。
class UpdateMirrorRow extends StatefulWidget {
  const UpdateMirrorRow({super.key});

  @override
  State<UpdateMirrorRow> createState() => _UpdateMirrorRowState();
}

class _UpdateMirrorRowState extends State<UpdateMirrorRow> {
  String _mode = 'auto';

  @override
  void initState() {
    super.initState();
    AppUpdateService.mirrorMode().then((v) {
      if (mounted) setState(() => _mode = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = _mode == 'auto'
        ? '自动（测速优选）'
        : AppUpdateService.mirrors
              .where((m) => m.id == _mode)
              .map((m) => m.label)
              .firstOrNull ??
          _mode;
    return SettingsToggleRow(
      icon: CupertinoIcons.globe,
      title: '更新镜像',
      description: '当前：$label。点按切换自动优选或手动指定',
      // 这是选择器不是开关，复用行壳但点击开选择弹层。
      value: _mode == 'auto',
      onChanged: (_) => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in {
              'auto': '自动（并发测速，先回先赢）',
              for (final m in AppUpdateService.mirrors) m.id: m.label,
            }.entries)
              ListTile(
                leading: Icon(
                  _mode == entry.key
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(entry.value),
                onTap: () => Navigator.of(context).pop(entry.key),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await AppUpdateService.setMirrorMode(choice);
    if (mounted) setState(() => _mode = choice);
  }
}
