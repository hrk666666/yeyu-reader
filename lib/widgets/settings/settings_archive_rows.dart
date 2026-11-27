// Ported layout helpers from Wenku8_Flutter (revision ebcd7f1):
//   lib/pages.dart               -> SettingsPage._toggleSetting (icon + title +
//                                   description + glass switch)
//   lib/low_performance_page.dart -> _option (title + description + switch)
//   lib/pages.dart               -> the inline ContentPanel row used by the
//                                   reading/data sections (icon + title +
//                                   chevron)
//
// Mechanical substitutions:
// - `AppControls.toggle` -> `GlassControls.toggle`
//   (`lib/widgets/wenku/glass_controls.dart`, the shared vendored
//   `glass_controls.dart` / `app_ui.dart` adapters).
// - `app_ui.dart` AppText/ArchiveIcon/ContentPanel/JellyTapSurface/ArchivePart
//   -> the shared `wenku_ui.dart` exports.
// - `NovelMotion` is not referenced by these rows.
//
// These are fqapp settings rows, not upstream widgets with the same names:
// they exist so every ported settings surface shares one geometry.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../wenku/wenku_ui.dart';

/// Upstream `ContentPanel` with the settings-section dividers between rows.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.children,
    this.dividerHeight = 22,
  });
  final List<Widget> children;
  final double dividerHeight;

  @override
  Widget build(BuildContext context) => ContentPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) Divider(height: dividerHeight),
          children[index],
        ],
      ],
    ),
  );
}

/// Upstream `SettingsPage._toggleSetting`: icon, title, description and a
/// glass switch. The whole row is tappable, matching fqapp's previous
/// SettingsRow behaviour.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.optimistic = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final FutureOr<void> Function(bool)? onChanged;

  /// Pass false when [onChanged] may ask for confirmation or a system
  /// permission: the switch must keep the persisted value until it commits.
  final bool optimistic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = onChanged;
    return JellyTapSurface(
      onTap: change == null ? null : () => change(!value),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ArchiveIcon(icon, size: 21),
              const SizedBox(width: 12),
              Expanded(child: AppText(title, style: theme.textTheme.bodyLarge)),
              const SizedBox(width: 12),
              Semantics(
                label: title,
                child: Switch(
                  value: value,
                  onChanged: change == null ? null : (next) => change(next),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 33, top: 4),
            child: AppText(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Upstream `low_performance_page.dart` `_option`: the same switch row without
/// a leading icon, for options inside a page-local panel.
class SettingsOptionRow extends StatelessWidget {
  const SettingsOptionRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final FutureOr<void> Function(bool)? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = onChanged;
    return JellyTapSurface(
      onTap: change == null ? null : () => change(!value),
      child: ArchivePart(
        start: .18,
        end: .84,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(title, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 6),
                  AppText(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: title,
              child: Switch(
                value: value,
                onChanged: onChanged == null
                    ? null
                    : (next) => onChanged!(next),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline row used by upstream settings sections: icon, title/subtitle and a
/// forward chevron (or a custom trailing control).
class SettingsLinkRow extends StatelessWidget {
  const SettingsLinkRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JellyTapSurface(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ArchiveIcon(icon, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(title, style: theme.textTheme.bodyLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: 5),
                    AppText(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.6,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                const ArchiveIcon(CupertinoIcons.chevron_forward, size: 14),
          ],
        ),
      ),
    );
  }
}

/// Secondary copy under a settings panel, matching the archive supporting
/// style used by the upstream settings pages.
class SettingsHint extends StatelessWidget {
  const SettingsHint(this.text, {super.key, this.fontSize});
  final String text;

  /// 覆盖默认的 `bodyMedium`(14)；需要更小的辅助文案时传 12（`bodySmall`）。
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium;
    return AppText(
      text,
      style: (fontSize == null ? base : base?.copyWith(fontSize: fontSize))
          ?.copyWith(height: 1.6, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}
