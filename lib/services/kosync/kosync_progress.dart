/// 进度位置串的编解码。
///
/// kosync 协议本身不规定 `progress` 的内容，它只是服务端原样存下来的
/// 字符串；怎么解释由两端自己约定。KOReader 用的是「分页书的页码」或
/// 「滚动书的 XPointer」，那套语义绑定在 EPUB 的 DOM 结构上。
///
/// 页屿不用那套：页屿的 EPUB 在导入时就被拆成纯文本章节，DOM 路径已经
/// 丢失，补不回来；而且滚动位置是像素值，随字号、行距、屏幕宽度变化，
/// 换台设备同一个像素位置根本不是同一段文字。所以页屿用字符偏移：
///
/// ```
/// y1:<章节序号>:<章节内字符偏移>
/// ```
///
/// 章节序号与字符偏移只跟书籍内容有关，两台设备读到同一段文字时算出的
/// 值一致，与各自的排版无关。
///
/// 远端若送来别的格式（典型是 KOReader 的 XPointer），页屿无法精确解释，
/// 退回到按 `percentage` 定位——精度到章节，仍能续读。
class KosyncProgress {
  const KosyncProgress._();

  /// 页屿自有定位串的版本前缀。
  static const String prefix = 'y1';

  /// 编码位置串。
  static String encode({
    required int chapterIndex,
    required int textOffset,
  }) {
    final chapter = chapterIndex < 0 ? 0 : chapterIndex;
    final offset = textOffset < 0 ? 0 : textOffset;
    return '$prefix:$chapter:$offset';
  }

  /// 解析远端进度，返回可用的目标位置。
  ///
  /// [chapterCount] 是本地章节总数，用来把百分比换算成章节序号；
  /// [percentage] 是远端记录的全书进度（0 到 1）。
  ///
  /// 返回 null 表示远端记录里没有任何可用信息。
  static KosyncRemotePosition? decode(
    String raw, {
    required int chapterCount,
    required double percentage,
  }) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    if (text.startsWith('$prefix:')) {
      final parts = text.split(':');
      if (parts.length >= 3) {
        final chapter = int.tryParse(parts[1]);
        final offset = int.tryParse(parts[2]);
        if (chapter != null && offset != null) {
          return KosyncRemotePosition(
            chapterIndex: chapter,
            textOffset: offset,
            exact: true,
            percentage: percentage,
            rawProgress: raw,
          );
        }
      }
    }

    // Foreign format: fall back to the book-wide percentage.
    if (chapterCount <= 0) {
      return KosyncRemotePosition(
        chapterIndex: 0,
        textOffset: null,
        exact: false,
        percentage: percentage,
        rawProgress: raw,
      );
    }

    final clamped = percentage.clamp(0.0, 1.0).toDouble();
    var chapter = (clamped * chapterCount).floor();
    if (chapter >= chapterCount) chapter = chapterCount - 1;
    if (chapter < 0) chapter = 0;
    final fraction = (clamped * chapterCount - chapter).clamp(0.0, 1.0);
    return KosyncRemotePosition(
      chapterIndex: chapter,
      textOffset: null,
      exact: false,
      percentage: clamped,
      chapterFraction: fraction,
      rawProgress: raw,
    );
  }
}

/// 远端进度解析出来的目标位置。
class KosyncRemotePosition {
  const KosyncRemotePosition({
    required this.chapterIndex,
    required this.textOffset,
    required this.exact,
    required this.percentage,
    required this.rawProgress,
    this.chapterFraction = 0,
  });

  /// 目标章节序号，0 起。
  final int chapterIndex;

  /// 章节内字符偏移；只有精确解析时才有值。
  final int? textOffset;

  /// 是否精确解析（false 表示只能按百分比定位）。
  final bool exact;

  /// 远端记录的全书进度。
  final double percentage;

  /// 按百分比回退时，目标章节内的相对位置（0 到 1）。
  final double chapterFraction;

  /// 远端原始的定位串，便于排查。
  final String rawProgress;
}
