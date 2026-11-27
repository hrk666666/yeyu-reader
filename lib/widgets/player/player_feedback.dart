import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/playback_issue.dart';
import '../../theme/md3.dart';

class PlayerErrorFeedback extends StatelessWidget {
  final PlaybackIssue issue;
  final VoidCallback? onRetry;

  const PlayerErrorFeedback({super.key, required this.issue, this.onRetry});

  @override
  Widget build(BuildContext context) => _FeedbackCard(
    title: issue.title,
    message: issue.message,
    leading: Icon(
      Icons.error_outline,
      color: Theme.of(context).colorScheme.onInverseSurface,
      size: 24,
    ),
    onRetry: onRetry,
  );
}

/// A single foreground wait across address lookup, native creation and the
/// first frame. The page keys this by load attempt and removes it when ready.
/// Later buffering mounts a new instance while the existing texture stays put.
class PlayerLoadingFeedback extends StatefulWidget {
  final String? label;
  final VoidCallback onRetry;

  const PlayerLoadingFeedback({super.key, this.label, required this.onRetry});

  @override
  State<PlayerLoadingFeedback> createState() => _PlayerLoadingFeedbackState();
}

class _PlayerLoadingFeedbackState extends State<PlayerLoadingFeedback>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _slow = false;

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_foreground) return;
    _timer = Timer(const Duration(seconds: 8), () {
      if (mounted && _foreground) setState(() => _slow = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    if (_slow) setState(() => _slow = false);
    if (state == AppLifecycleState.resumed) _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = SizedBox.square(
      dimension: 24,
      child: CircularProgressIndicator(
        color: Theme.of(context).colorScheme.onInverseSurface,
        strokeWidth: 2,
      ),
    );
    if (_slow) {
      return _FeedbackCard(
        title: widget.label == null ? '缓冲较慢' : '加载较慢',
        message: '网络或视频响应较慢，可以继续等待，或检查网络后重试。',
        leading: progress,
        onRetry: widget.onRetry,
      );
    }
    return IgnorePointer(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              progress,
              if (widget.label != null) ...[
                const SizedBox(height: 16),
                Text(
                  widget.label!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final String title;
  final String message;
  final Widget leading;
  final VoidCallback? onRetry;

  const _FeedbackCard({
    required this.title,
    required this.message,
    required this.leading,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final retryButton = onRetry == null
          ? null
          : FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            );
      // An expanded description panel can leave only a narrow video strip.
      // Keep the action reachable without overflowing or enlarging the video.
      if (constraints.maxWidth < 140 || constraints.maxHeight < 96) {
        return Center(
          child: Tooltip(
            message: '$title\n$message',
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child:
                  retryButton ??
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onInverseSurface,
                    ),
                  ),
            ),
          ),
        );
      }
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Card(
              color: Theme.of(context).colorScheme.inverseSurface,
              elevation: Md3Elevation.level3,
              shape: const RoundedRectangleBorder(
                borderRadius: Md3Shape.mediumRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        leading,
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onInverseSurface,
                          ),
                    ),
                    if (retryButton != null) ...[
                      const SizedBox(height: 8),
                      retryButton,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
