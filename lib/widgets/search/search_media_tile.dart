import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../models/shuqi_book.dart';
import '../../theme/md3.dart';
import '../home/home_media_card.dart';
import '../media_card.dart';
import '../wenku/wenku_ui.dart';

String _fileCode(MediaItem item) {
  final prefix = isShuqiItem(item) ? 'SQ' : 'FQ';
  final numeric = int.tryParse(item.id);
  if (numeric != null) {
    return '$prefix-${numeric.toString().padLeft(5, '0')}';
  }
  final id = item.id.trim();
  return id.isEmpty ? '$prefix-UNFILED' : '$prefix-$id';
}

String searchMediaMeta(MediaItem item) => [
  if (item.author.isNotEmpty) item.author,
  kindLabels[item.kind] ?? item.kind,
  if (mediaLengthLabel(item).isNotEmpty) mediaLengthLabel(item),
  if (item.score != null)
    '${item.score!.toStringAsFixed(1)}分'
  else if (!isShuqiItem(item))
    '暂无评分',
].join(' · ');

/// MediaItem adapter for the result list: official MD3 [ListTile]
/// (cover / code+title / meta / chevron), state layer 由框架负责。
class SearchNovelRow extends StatelessWidget {
  const SearchNovelRow({super.key, required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Semantics(
      button: true,
      label: item.title,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        // One-line ListTile clamps the leading to 56px tall; keep the cover's
        // ~30:41 portrait ratio within that bound instead of a square crop.
        leading: ClipRRect(
          borderRadius: Md3Shape.smallRadius,
          child: SizedBox(
            width: 42,
            height: 56,
            child: StoryCover(
              item: item,
              cacheWidth: math.max(1, (42 * pixelRatio).ceil()),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ArchiveCode(_fileCode(item)),
            const SizedBox(height: 4),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 7),
            Text(
              searchMediaMeta(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: Icon(
          CupertinoIcons.chevron_right,
          size: 15,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// MediaItem adapter for the result grid: official [InkWell] state layer +
/// official cover shape/typescale.
class SearchBookGridTile extends StatelessWidget {
  const SearchBookGridTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: item.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: Md3Shape.smallRadius,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final coverHeight = width / (30 / 41);
            final pixelRatio = MediaQuery.devicePixelRatioOf(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: Md3Shape.smallRadius,
                  child: SizedBox(
                    height: coverHeight,
                    child: StoryCover(
                      item: item,
                      cacheWidth: math.max(1, (width * pixelRatio).ceil()),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  searchMediaMeta(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
