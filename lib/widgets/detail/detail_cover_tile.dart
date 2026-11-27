import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../models/media_item.dart';
import '../../theme/md3.dart';
import '../home/home_design.dart';
import '../home/home_media_card.dart';

/// 3:4-ish detail cover, tappable to open the zoomable viewer.
///
/// Wrapped in an official MD3 [Card] (tonal elevation + medium shape); e-ink
/// keeps the shape and paints the artwork in grayscale.
class DetailCoverTile extends StatelessWidget {
  final MediaItem item;

  /// 桌面两栏布局：封面放大。
  final bool desktop;
  final bool compact;

  const DetailCoverTile({
    super.key,
    required this.item,
    this.desktop = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    final width = desktop ? (compact ? 112.0 : 168.0) : 92.0;
    final height = desktop ? width * 4 / 3 : 128.0;
    return SizedBox(
      width: width,
      height: height,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: Md3Elevation.level1,
        shape: const RoundedRectangleBorder(
          borderRadius: Md3Shape.mediumRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: HomePressable(
          key: const Key('detail_cover_button'),
          semanticLabel: '查看《${item.title}》封面',
          onTap: () => showDetailCover(context, item),
          borderRadius: Md3Shape.mediumRadius,
          child: ExcludeSemantics(
            child: palette.eink
                ? ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0, 0, 0, 1, 0, //
                    ]),
                    child: StoryCover(item: item, cacheWidth: 320),
                  )
                : StoryCover(item: item, cacheWidth: 320),
          ),
        ),
      ),
    );
  }
}

/// Full-screen zoomable cover viewer. Tapping the cover opens it.
Future<void> showDetailCover(BuildContext context, MediaItem item) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭封面',
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Md3Motion.medium2,
      pageBuilder: (context, animation, secondaryAnimation) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton(
                    tooltip: '关闭封面',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  key: const Key('detail_cover_viewer'),
                  maxScale: 3,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: AspectRatio(
                          aspectRatio: 5 / 7,
                          child: ClipRRect(
                            borderRadius: Md3Shape.mediumRadius,
                            child: StoryCover(item: item, cacheWidth: 1000),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                child: Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
