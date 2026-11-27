import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/md3.dart';
import 'src/app_text.dart';
import 'wenku_archive.dart';
import 'wenku_glass.dart';
import 'wenku_icons.dart';

class ArchiveFeaturePage extends StatelessWidget {
  const ArchiveFeaturePage({
    super.key,
    required this.title,
    required this.code,
    required this.child,
    this.actions = const [],
    this.canPop = true,
  });

  final String title;
  final String code;
  final Widget child;
  final List<Widget> actions;
  final bool canPop;

  @override
  Widget build(BuildContext context) => WenkuPage(
    header: ArchiveHeaderBar(
      leading: GlassIconButton(
        icon: CupertinoIcons.back,
        label: '返回',
        onPressed: canPop ? () => Navigator.pop(context) : null,
      ),
      title: ArchiveRouteTitle(title: title, code: code),
      actions: actions,
    ),
    child: child,
  );
}

EdgeInsets featurePadding(BuildContext context) => EdgeInsets.fromLTRB(
  md3ContentMargin(context), // 官方 M3 自适应内容边距（compact 16 / medium+ 24）
  MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
  md3ContentMargin(context),
  MediaQuery.paddingOf(context).bottom + 32,
);

class FeatureEntry extends StatelessWidget {
  const FeatureEntry({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ContentPanel(
    onTap: onTap,
    child: ArchivePart(
      start: .18,
      end: .84,
      travel: const Offset(0, 6),
      child: Row(
        children: [
          ArchiveIcon(icon, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  title,
                  // 官方 M3 typescale（titleMedium），去掉自研字号/字重。
                  style: theme.textTheme.titleMedium,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  AppText(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const ArchiveIcon(CupertinoIcons.chevron_right, size: 14),
        ],
      ),
    ),
  );
  }
}

class FeatureError extends StatelessWidget {
  const FeatureError(this.text, {super.key});

  final String? text;

  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Semantics(
            liveRegion: true,
            child: AppText(
              text!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
}
