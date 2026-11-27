// Upstream source: Wenku8_Flutter rev ebcd7f1
//   lib/reading_statistics_page.dart (ArchiveSection section headers,
//     _Metrics/_RankLine list vocabulary, _muted)
// Mechanical substitutions:
// - The rank rows use the vendored `ContentPanel` / `ArchiveSection` /
//   `GlassTextButton` instead of fqapp's `HomeSectionHeader` / `HomePressable`,
//   so the statistics route shares the archive surface.
// - Upstream has no "most read" ranking; fqapp's local read-time ranking is
//   kept because it is the only book-level statistic fqapp records. Cover
//   loading stays on fqapp's `PosterCache` pipeline (upstream `NovelCover` is
//   not part of this slice).
// - The full-list sheet stays fqapp's `showHomeSheet`; the row and its
//   duration formatting are shared between the preview and the sheet.
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../models/media_item.dart';
import '../../models/reading_stats.dart';
import '../../services/poster_cache.dart';
import '../home/home_media_card.dart';
import '../home/home_sheet.dart';
import '../wenku/wenku_ui.dart';

typedef MineOpenEntry = void Function(Map<String, dynamic> entry);

/// 读得最多：按时长排的前 5 本，超过 5 本时右上角「全部」打开完整列表。
class MineTopBooks extends StatelessWidget {
  static const previewCount = 5;

  final List<ReadingRankItem> rank;
  final MineOpenEntry onOpen;

  const MineTopBooks({super.key, required this.rank, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArchiveSection(
          title: '读得最多',
          code: '05 / MOST READ',
          subtitle: rank.isEmpty ? '' : '累计 ${rank.length} 本',
        ),
        if (rank.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: AppText(
              '读过的书会按时长排在这里',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          if (rank.length > previewCount)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => showMineRankSheet(context, rank, onOpen),
                  child: const Text('全部'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          for (var i = 0; i < rank.length && i < previewCount; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MineRankRow(
                rank: i + 1,
                item: rank[i],
                onTap: () => onOpen(rank[i].entry),
              ),
            ),
        ],
      ],
    );
  }
}

/// 完整排行。点一行先收起弹层，再交给 [onOpen] 打开原内容。
Future<void> showMineRankSheet(
  BuildContext context,
  List<ReadingRankItem> rank,
  MineOpenEntry onOpen,
) async {
  await showHomeSheet<void>(
    context: context,
    title: '全部 ${rank.length} 本',
    contentPadding: EdgeInsets.zero,
    children: [
      for (var i = 0; i < rank.length; i++)
        MineRankRow(
          rank: i + 1,
          item: rank[i],
          onTap: () {
            Navigator.pop(context);
            onOpen(rank[i].entry);
          },
        ),
    ],
  );
}

class MineRankRow extends StatelessWidget {
  final int rank;
  final ReadingRankItem item;
  final VoidCallback onTap;

  const MineRankRow({
    super.key,
    required this.rank,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: ArchiveDesign.codeStyle(
                context,
                color: rank <= 3 ? scheme.primary : scheme.onSurfaceVariant,
              ).copyWith(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          _Cover(url: item.entry['cover']?.toString() ?? ''),
        ],
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(
        _meta(item.entry),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        formatReadingDuration(item.minutes),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 类型 · 读到第几章 · 最近打开日期；缺的项直接省略。
String _meta(Map<String, dynamic> entry) {
  final kind = entry['kind']?.toString() ?? 'book';
  final episode = (entry['episode'] as num?)?.toInt();
  final time = (entry['time'] as num?)?.toInt() ?? 0;
  final opened = DateTime.fromMillisecondsSinceEpoch(time);
  return [
    homeKindLabel(kind),
    if (episode != null)
      isVideoKind(kind) ? '看到第${episode + 1}集' : '读到第${episode + 1}章',
    if (time > 0) '最近 ${opened.month}月${opened.day}日',
  ].join(' · ');
}

class _Cover extends StatelessWidget {
  final String url;

  const _Cover({required this.url});

  static const _width = 36.0;
  static const _height = 48.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: _width,
      height: _height,
      color: scheme.surfaceContainerHighest,
      child: Icon(
        LucideIcons.book_open,
        size: 16,
        color: scheme.onSurfaceVariant,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: url.isEmpty
          ? placeholder
          : CachedNetworkImage(
              cacheManager: PosterCache.instance,
              imageUrl: url,
              width: _width,
              height: _height,
              fit: BoxFit.cover,
              memCacheWidth: 108,
              memCacheHeight: 144,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}
