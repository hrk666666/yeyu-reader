import 'package:flutter/material.dart';

/// fqapp-only rating filter on the results heading.
///
/// 官方 MD3 [FilterChip]：点击按 [_thresholds] 顺序切换到下一档评分，
/// [onChanged] 只会收到 0 / 8 / 9 三个离散值，业务逻辑保持不变。
class SearchScoreFilter extends StatelessWidget {
  static const thresholds = <double>[0, 8, 9];

  final bool enabled;
  final double minimumScore;
  final ValueChanged<double> onChanged;

  const SearchScoreFilter({
    super.key,
    required this.enabled,
    required this.minimumScore,
    required this.onChanged,
  });

  static String labelFor(double value) =>
      value == 0 ? '评分不限' : '${value.toStringAsFixed(0)} 分以上';

  @override
  Widget build(BuildContext context) {
    final value = enabled ? minimumScore : 0.0;
    final index = thresholds.indexOf(value);
    final next = thresholds[(index + 1) % thresholds.length];
    return Semantics(
      container: true,
      label: '评分筛选',
      value: labelFor(value),
      hint: enabled ? '切换为${labelFor(next)}' : null,
      child: FilterChip(
        key: const Key('search-minimum-score'),
        label: Text(labelFor(value)),
        selected: value > 0,
        showCheckmark: false,
        avatar: const Icon(Icons.tune, size: 16),
        onSelected: enabled ? (_) => onChanged(next) : null,
      ),
    );
  }
}
