import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// 榜单页的整页空 / 错态。
///
/// 官方 MD3 文案层级：图标 → [TextTheme.titleLarge] 标题 →
/// [TextTheme.bodyMedium] 说明 → [FilledButton] 重试；外层可垂直滚动，
/// 窄屏大字号下按钮仍可达。
class RankStateView extends StatelessWidget {
  const RankStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(LucideIcons.refresh_cw, size: 18),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
