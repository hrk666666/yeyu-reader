import 'package:flutter/material.dart';

import '../../models/search_discovery.dart';
import '../../theme/md3.dart';
import '../wenku/wenku_ui.dart';

const double _searchGutter = 24;

/// Query suggestions follow the archive's plain 48dp result rows.
class SearchSuggestionList extends StatelessWidget {
  final List<SearchSuggestion> suggestions;
  final ValueChanged<String> onSelect;
  final double topInset;

  const SearchSuggestionList({
    super.key,
    required this.suggestions,
    required this.onSelect,
    this.topInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      key: const Key('search_suggestions'),
      padding: EdgeInsets.only(top: topInset),
      itemCount: suggestions.length,
      separatorBuilder: (context, _) => Divider(
        height: 1,
        thickness: .7,
        indent: _searchGutter,
        endIndent: _searchGutter,
      ),
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        return ListTile(
          key: ValueKey('search_suggestion_${suggestion.text}'),
          onTap: () => onSelect(suggestion.text),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: _searchGutter,
          ),
          leading: Icon(
            Icons.search,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          title: _SuggestionText(suggestion: suggestion),
        );
      },
    );
  }
}

/// Keeps the upstream `<em>` match emphasis without introducing a second accent.
class _SuggestionText extends StatelessWidget {
  final SearchSuggestion suggestion;

  const _SuggestionText({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(
      color: scheme.onSurfaceVariant,
      fontSize: 14,
      height: 1.4,
    );
    final marked = base.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final parts = _splitHighlight(suggestion.highlighted);
    if (parts.isEmpty) {
      return Text(
        suggestion.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    return RichText(
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base,
        children: [
          for (final part in parts)
            TextSpan(text: part.$1, style: part.$2 ? marked : base),
        ],
      ),
    );
  }

  static List<(String, bool)> _splitHighlight(String raw) {
    if (raw.isEmpty || !raw.contains('<em>')) return const [];
    final out = <(String, bool)>[];
    var rest = raw;
    while (rest.isNotEmpty) {
      final start = rest.indexOf('<em>');
      if (start < 0) {
        out.add((rest, false));
        break;
      }
      if (start > 0) out.add((rest.substring(0, start), false));
      final end = rest.indexOf('</em>', start);
      if (end < 0) {
        out.add((rest.substring(start + 4), true));
        break;
      }
      out.add((rest.substring(start + 4, end), true));
      rest = rest.substring(end + 5);
    }
    return out.where((part) => part.$1.isNotEmpty).toList();
  }
}

/// The hot board keeps fqapp's live discovery data in the upstream index style.
class HotSearchBoard extends StatelessWidget {
  static const maxRows = 10;

  final HotSearch hot;
  final ValueChanged<String> onSelect;

  const HotSearchBoard({super.key, required this.hot, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (hot.isEmpty) return const SizedBox.shrink();
    final entries = hot.entries.take(maxRows).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ArchiveSection(
          title: '热搜榜',
          code: '02 / TRENDING INDEX',
          subtitle: '按当前热度排列',
        ),
        const SizedBox(height: 10),
        Column(
          key: const Key('search_hot_words'),
          children: [
            for (var index = 0; index < entries.length; index++)
              _HotRow(
                entry: entries[index],
                rank: index + 1,
                onTap: () => onSelect(entries[index].title),
              ),
          ],
        ),
      ],
    );
  }
}

class _HotRow extends StatelessWidget {
  final HotSearchEntry entry;
  final int rank;
  final VoidCallback onTap;

  const _HotRow({required this.entry, required this.rank, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = rank <= 3;
    return ListTile(
      key: ValueKey('search_hot_${entry.title}'),
      onTap: onTap,
      dense: true,
      minVerticalPadding: 0,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 24,
        child: Text(
          '$rank',
          textAlign: TextAlign.center,
          style: (top ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
              ?.copyWith(
            color: top ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: top ? FontWeight.w700 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      title: Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: top ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.badge.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: Md3Shape.extraSmallRadius,
              ),
              child: Text(
                entry.badge,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          if (entry.hotValue.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              entry.hotValue,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Search landing content: the upstream `RecentSearches` block first (omitted
/// when empty, as upstream), then fqapp's live hot index.
class SearchDiscoveryView extends StatelessWidget {
  final HotSearch hot;
  final List<String> history;
  final bool historyLoading;
  final String filter;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearHistory;
  final ValueChanged<String> onRemoveHistory;
  final double topInset;

  const SearchDiscoveryView({
    super.key,
    required this.hot,
    required this.history,
    required this.historyLoading,
    required this.filter,
    required this.onSearch,
    required this.onClearHistory,
    required this.onRemoveHistory,
    this.topInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final visible = filter.isEmpty
        ? history
        : history
              .where((item) => item.toLowerCase().contains(filter))
              .toList(growable: false);
    final showHot = filter.isEmpty && hot.isNotEmpty;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        _searchGutter,
        topInset,
        _searchGutter,
        // Search covers the dock, so only the safe area is cleared (upstream
        // `InlineSearchResults`).
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (!historyLoading && visible.isNotEmpty)
          _RecentSearches(
            queries: visible,
            onRecall: onSearch,
            onClear: onClearHistory,
            onRemove: onRemoveHistory,
          ),
        if (showHot)
          HotSearchBoard(hot: hot, onSelect: onSearch)
        else if (!historyLoading && visible.isEmpty)
          AppText(
            filter.isEmpty ? '搜索名称或作品 ID，开始寻找故事。' : '没有匹配的搜索记录',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Upstream `recent_searches.dart`. fqapp keeps per-query removal: a long
/// press removes one entry instead of a permanent × on every chip.
class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.queries,
    required this.onRecall,
    required this.onClear,
    required this.onRemove,
  });

  final List<String> queries;
  final ValueChanged<String> onRecall;
  final VoidCallback onClear;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: AppText(
                '最近搜索',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: '清空最近搜索',
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final query in queries)
              Semantics(
                onLongPressHint: '删除这条记录',
                child: GestureDetector(
                  onLongPress: () {
                    AppHaptics.play(context, HapticCue.action);
                    onRemove(query);
                  },
                  child: ActionChip(
                    key: ValueKey('search_history_$query'),
                    label: Text(
                      query,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => onRecall(query),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
