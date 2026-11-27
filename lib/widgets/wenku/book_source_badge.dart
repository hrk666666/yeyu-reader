// Ported from Wenku8_Flutter lib/book_source_badge.dart (revision ebcd7f1).
//
// Mechanical substitution: upstream `app_language.dart` `AppText` is fqapp's
// `src/app_text.dart` `AppText` (Chinese input returned unchanged).

import 'package:flutter/material.dart';

import '../../theme/md3.dart';
import 'src/app_text.dart';

/// 官方 MD3 小型来源标签：surfaceContainerHigh tonal 容器 + extraSmall 形状 +
/// labelSmall typescale。（M3 的 Badge 需要锚定 child，这里作为独立角标用
/// tonal 容器表达。）
class BookSourceBadge extends StatelessWidget {
  const BookSourceBadge(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Md3Shape.extraSmallRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: AppText(
          label,
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
