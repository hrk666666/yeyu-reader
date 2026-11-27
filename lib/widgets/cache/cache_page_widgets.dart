import 'package:flutter/material.dart';

import '../../theme/md3.dart';
import '../home/home_design.dart';
import '../home/home_feed_states.dart';
import '../settings/settings_widgets.dart';

/// 离线缓存页（小说 / 短剧）共用的统计卡：图标砖 + 汇总行 + 说明行。
///
/// 两页原来各画一套 16dp 圆角 Card；统一走 [SettingsGroupCard] 的 20dp 圆角
/// 与 0.6dp 描边，颜色全部来自 [HomePalette]，墨水屏自动纯黑白。
class CacheSummaryCard extends StatelessWidget {
  const CacheSummaryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    return SettingsGroupCard(
      showDividers: false,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.soft,
                  borderRadius: Md3Shape.mediumRadius,
                ),
                child: Icon(icon, size: 22, color: palette.accentText),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 缓存页统一的空态（两页此前各写了一套 64dp 圆形图标 + 16/13sp 文案）。
class CacheEmptyState extends StatelessWidget {
  const CacheEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => HomeStateView(
    icon: icon,
    title: title,
    message: message,
    scrollable: true,
  );
}

/// 缓存页统一的加载失败态：同一句说明 + 重试动作。
class CacheErrorState extends StatelessWidget {
  const CacheErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => HomeStateView(
    icon: Icons.cloud_off,
    title: message,
    message: '请稍后重试',
    actionLabel: '重试',
    actionIcon: Icons.refresh,
    onAction: onRetry,
    scrollable: true,
  );
}
