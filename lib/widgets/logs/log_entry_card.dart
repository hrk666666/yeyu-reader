import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../services/app_log.dart';
import '../../theme/md3.dart';
import '../home/home_design.dart';

/// Collapsed summaries keep stack traces from taking over the log list.
class LogEntryCard extends StatefulWidget {
  const LogEntryCard({super.key, required this.entry, required this.onCopy});

  final LogEntry entry;
  final VoidCallback onCopy;

  @override
  State<LogEntryCard> createState() => _LogEntryCardState();
}

class _LogEntryCardState extends State<LogEntryCard> {
  bool _expanded = false;

  /// 级别色全部取自官方 [ColorScheme] 角色：info 用 primary、warn 用
  /// tertiary、error 用 error；墨水屏 / OLED 的黑白由主题 ColorScheme 保证。
  Color _levelColor(ColorScheme scheme, LogLevel level) {
    return switch (level) {
      LogLevel.debug => scheme.onSurfaceVariant,
      LogLevel.info => scheme.primary,
      LogLevel.warn => scheme.tertiary,
      LogLevel.error => scheme.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final palette = HomePalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = _levelColor(scheme, entry.level);
    final time = entry.time.toLocal();
    final timestamp = time.toIso8601String();
    final messageStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.5,
      color: palette.ink,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card.filled(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: _expanded,
              child: InkWell(
                borderRadius: Md3Shape.largeRadius,
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _levelBadge(palette, color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.tag,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: palette.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timestamp.substring(11, 19),
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.muted,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _expanded
                                ? LucideIcons.chevron_up
                                : LucideIcons.chevron_down,
                            size: 18,
                            color: palette.muted,
                          ),
                        ],
                      ),
                      if (!_expanded) ...[
                        const SizedBox(height: 8),
                        Text(
                          entry.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: messageStyle,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '${timestamp.replaceFirst('T', ' ')} · ${entry.tag}',
                      style: TextStyle(fontSize: 11, color: palette.muted),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(entry.message, style: messageStyle),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: widget.onCopy,
                      style: TextButton.styleFrom(
                        foregroundColor: palette.accentText,
                      ),
                      icon: const Icon(LucideIcons.copy, size: 16),
                      label: const Text('复制单条'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _levelBadge(HomePalette palette, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: palette.eink ? Colors.transparent : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: palette.eink ? Border.all(color: Colors.black) : null,
      ),
      child: Text(
        widget.entry.level.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
