import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../services/audio_page_theme.dart';
import '../../theme/md3.dart';

/// 章末连播倒计时条。
///
/// 官方是 `te`「%s后播放下一集」：章节播完不立刻跳，给一段可取消的窗口。
/// 归零后由控制器打开下一章，这一条只负责显示与取消。
class AudioAdvanceBanner extends StatelessWidget {
  /// 剩余秒数。
  final int seconds;
  final VoidCallback onCancel;

  const AudioAdvanceBanner({
    super.key,
    required this.seconds,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AudioPageThemeScope.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Md3Dimens.compactMargin,
        0,
        Md3Dimens.compactMargin,
        2,
      ),
      child: Card.filled(
        key: const Key('audio_advance_banner'),
        color: theme.card,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            children: [
              Icon(LucideIcons.skip_forward, size: 16, color: theme.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$seconds 秒后播放下一集',
                  key: const Key('audio_advance_countdown'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(color: theme.ink),
                ),
              ),
              Semantics(
                label: '取消自动播放下一集',
                button: true,
                child: TextButton(
                  key: const Key('audio_advance_cancel'),
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.accent,
                    textStyle: textTheme.labelLarge,
                    minimumSize: const Size(
                      Md3Dimens.minTouchTarget,
                      Md3Dimens.minTouchTarget,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
