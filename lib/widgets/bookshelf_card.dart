import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../theme/md3.dart';
import 'home/home_design.dart';
import 'shelf/shelf_cover_image.dart';
import 'shelf/shelf_design.dart';

// ---------------------------------------------------------------------------
// Shared pieces.
// ---------------------------------------------------------------------------

/// 封面底图：宽高由调用方按版式给定，圆角与占位逻辑三档共用。
class _ShelfCover extends StatelessWidget {
  final MediaItem item;
  final double width;
  final double height;
  final double radius;
  final String? badgeText;
  final bool selected;

  const _ShelfCover({
    required this.item,
    required this.width,
    required this.height,
    required this.radius,
    this.badgeText,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    final fallback = _DefaultCover(item: item);
    return SizedBox(
      key: const Key('bookshelf-cover'),
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: ColoredBox(
              color: palette.soft,
              child: ShelfCoverImage(
                item: item,
                fallback: fallback,
                width: width,
                height: height,
                decodeWidth: math.max(1, (width * 3).round()),
              ),
            ),
          ),
          // 选中态：M3 primary 18% state layer + 2dp primary 描边。
          if (selected)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          if (badgeText != null && !selected)
            Positioned(
              top: ShelfTokens.spaceXS,
              right: ShelfTokens.spaceXS,
              child: _ProgressBadge(text: badgeText!),
            ),
        ],
      ),
    );
  }
}

/// 右上角进度角标：accent 渐变小胶囊，贴边内嵌 4dp。
///
/// 角标显示调用方检测到的「更新」或阅读进度。
/// 白字是品牌渐变上的固定前景，允许硬编码。
class _ProgressBadge extends StatelessWidget {
  final String text;

  const _ProgressBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: Md3Shape.extraSmallRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onPrimary,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 编辑态多选框：22×22dp，选中态填充品牌色。
class _SelectionBox extends StatelessWidget {
  final bool selected;
  final Color border;

  const _SelectionBox({required this.selected, required this.border});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 22,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? scheme.primary
              : scheme.surface.withValues(alpha: 0.55),
          border: Border.all(
            color: selected ? scheme.primary : border,
            width: 1.5,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 14, color: scheme.onPrimary)
            : null,
      ),
    );
  }
}

class _DefaultCover extends StatelessWidget {
  final MediaItem item;

  const _DefaultCover({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = HomePalette.of(context);
    final accent = bookshelfKindColor(item.kind) ?? scheme.primary;
    final background = Color.alphaBlend(
      accent.withValues(alpha: 0.14),
      scheme.surfaceContainerHighest,
    );
    final cleaned = _cleanBookInfo(item.title, item.author);
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _DefaultCoverPainter(
          background: background,
          accentColor: accent,
          titleColor: palette.ink,
          authorColor: palette.muted,
          title: cleaned.title,
          author: cleaned.author,
        ),
      ),
    );
  }
}

class _CleanedCoverInfo {
  final String title;
  final String author;
  const _CleanedCoverInfo({required this.title, required this.author});
}

/// 智能清洗封面展示的书名与作者：
/// 1. 若标题混入了「作者：xxx」「by xxx」，自动提取出干净作者名，并从书名中剔除；
/// 2. 剥离无意义的打包噪音标签（如 (精校版)、[全本]、(校对版)），还原本真书名。
_CleanedCoverInfo _cleanBookInfo(String rawTitle, String rawAuthor) {
  var title = rawTitle.trim();
  var author = rawAuthor.trim();

  if (author.isEmpty || author == '未知作者') {
    final authorMatch = RegExp(
      r'[（(\[【]?\s*作者\s*[:：\s]+\s*([^）)\]】\s]+)[）)\]】]?',
    ).firstMatch(title);
    if (authorMatch != null) {
      author = authorMatch.group(1)?.trim() ?? '';
      title = title.replaceRange(authorMatch.start, authorMatch.end, '').trim();
    } else {
      final byMatch = RegExp(
        r'[（(\[【]?\s*by\s*[:：\s]+\s*([^）)\]】\s]+)[）)\]】]?',
        caseSensitive: false,
      ).firstMatch(title);
      if (byMatch != null) {
        author = byMatch.group(1)?.trim() ?? '';
        title = title.replaceRange(byMatch.start, byMatch.end, '').trim();
      }
    }
  }

  title = title
      .replaceAll(
        RegExp(
          r'[（(\[【]\s*(?:精校版?|校对版?|全本|全集|完结|完本|精修版?|无错版?|未删节|未删减|手打|更新|排版|精编)[^）)\]】]*[）)\]】]',
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  title = title.replaceAll(RegExp(r'^[_\-—\s,，:：]+|[_\-—\s,，:：]+$'), '').trim();
  author = author
      .replaceAll(RegExp(r'^(?:作者|by)[:：\s]*', caseSensitive: false), '')
      .trim();

  if (title.isEmpty) title = rawTitle.trim();
  return _CleanedCoverInfo(title: title, author: author);
}

class _DefaultCoverPainter extends CustomPainter {
  final Color background;
  final Color accentColor;
  final Color titleColor;
  final Color authorColor;
  final String title;
  final String author;

  const _DefaultCoverPainter({
    required this.background,
    required this.accentColor,
    required this.titleColor,
    required this.authorColor,
    required this.title,
    required this.author,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 30) {
      canvas.drawRect(Offset.zero & size, Paint()..color = background);
      return;
    }

    // 1. 实体封面底色与微渐变光泽
    final bgRect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.alphaBlend(Colors.white.withValues(alpha: 0.08), background),
          background,
          Color.alphaBlend(Colors.black.withValues(alpha: 0.06), background),
        ],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, bgPaint);

    // 2. 左侧物理书脊立体折痕与暗影
    final spineWidth = (size.width * 0.055).clamp(4.0, 7.0);
    final spineRect = Rect.fromLTWH(0, 0, spineWidth, size.height);
    final spinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.black.withValues(alpha: 0.18),
          Colors.black.withValues(alpha: 0.04),
          Colors.transparent,
        ],
      ).createShader(spineRect);
    canvas.drawRect(spineRect, spinePaint);

    // 书脊折痕细线
    canvas.drawLine(
      Offset(spineWidth, 0),
      Offset(spineWidth, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 0.8,
    );

    // 3. 极小缩略图（如列表行 56x78）精简模式
    if (size.width < 70) {
      _paintCompact(canvas, size, spineWidth);
      return;
    }

    // 4. 标准封面：内封装饰雅致边框
    final insetLeft = spineWidth + 5.0;
    const insetTop = 6.0;
    const insetRight = 6.0;
    const insetBottom = 6.0;
    final innerRect = Rect.fromLTRB(
      insetLeft,
      insetTop,
      size.width - insetRight,
      size.height - insetBottom,
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = accentColor.withValues(alpha: 0.22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, const Radius.circular(3.0)),
      borderPaint,
    );

    // 5. 核心排版区（居中偏上黄金分割位）
    final contentWidth = size.width - spineWidth - 16.0;
    final centerX = spineWidth + 8.0 + contentWidth / 2;

    // 字号根据封面物理宽度与字数动态适配，彻底告别过大散落的巨幅单字。
    // [锁定] 这是画在假书封面上的装饰性排版（TextPainter 上 canvas），
    // 尺寸跟随封面物理宽度缩放，不走 textTheme 语义档（同 6.5/8.5 迷你字）。
    final double titleFontSize;
    if (size.width < 125) {
      if (title.length <= 5) {
        titleFontSize = 12.5;
      } else if (title.length <= 9) {
        titleFontSize = 11.0;
      } else {
        titleFontSize = 10.0;
      }
    } else {
      if (title.length <= 5) {
        titleFontSize = 14.5;
      } else if (title.length <= 9) {
        titleFontSize = 13.0;
      } else {
        titleFontSize = 11.5;
      }
    }

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: titleColor,
          fontSize: titleFontSize,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: 0.3,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '...',
    )..layout(maxWidth: contentWidth);

    TextPainter? authorPainter;
    if (author.isNotEmpty && size.height > 85) {
      final authorFontSize = (titleFontSize * 0.78).clamp(8.0, 10.0);
      final authorText = author.length > 8 ? author.substring(0, 8) : author;
      authorPainter = TextPainter(
        text: TextSpan(
          text: '$authorText 著',
          style: TextStyle(
            color: authorColor.withValues(alpha: 0.85),
            fontSize: authorFontSize,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: contentWidth);
    }

    final totalTextHeight =
        titlePainter.height +
        (authorPainter != null ? authorPainter.height + 12.0 : 0.0);

    // 垂直视觉中心（封面高度 32% ~ 36% 处）
    final startY = (size.height * 0.33 - totalTextHeight / 2).clamp(
      insetTop + 8.0,
      size.height * 0.45,
    );

    // 绘制柔和宣纸质感书名签底板（Plaque）
    const padH = 6.0;
    const padV = 8.0;
    final plaqueW =
        (math.max(titlePainter.width, authorPainter?.width ?? 0) + padH * 2)
            .clamp(contentWidth * 0.68, contentWidth);
    final plaqueRect = Rect.fromCenter(
      center: Offset(centerX, startY + totalTextHeight / 2),
      width: plaqueW,
      height: totalTextHeight + padV * 2,
    );
    final plaqueRRect = RRect.fromRectAndRadius(
      plaqueRect,
      const Radius.circular(3.5),
    );

    // 书名签微透白底与雅致细描边
    canvas.drawRRect(
      plaqueRRect,
      Paint()..color = Colors.white.withValues(alpha: 0.42),
    );
    canvas.drawRRect(
      plaqueRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = accentColor.withValues(alpha: 0.25),
    );

    // 绘制标题
    final titleOrigin = Offset(centerX - titlePainter.width / 2, startY + padV);
    titlePainter.paint(canvas, titleOrigin);

    var currentY = startY + padV + titlePainter.height;

    // 绘制雅致分割线（— ◆ —）与作者
    if (authorPainter != null) {
      currentY += 5.0;
      const divHalf = 12.0;
      final divPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.35)
        ..strokeWidth = 0.6;
      canvas.drawLine(
        Offset(centerX - divHalf, currentY),
        Offset(centerX - 3.5, currentY),
        divPaint,
      );
      canvas.drawCircle(
        Offset(centerX, currentY),
        1.1,
        divPaint..style = PaintingStyle.fill,
      );
      canvas.drawLine(
        Offset(centerX + 3.5, currentY),
        Offset(centerX + divHalf, currentY),
        divPaint..style = PaintingStyle.stroke,
      );
      currentY += 5.0;

      authorPainter.paint(
        canvas,
        Offset(centerX - authorPainter.width / 2, currentY),
      );
    }

    // 6. 封面底部古典微章（Publisher Tag/Seal）
    final bottomY = size.height - 18.0;
    final stampPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = accentColor.withValues(alpha: 0.28);
    final stampRect = Rect.fromCenter(
      center: Offset(centerX, bottomY),
      width: 28.0,
      height: 10.0,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(stampRect, const Radius.circular(2.0)),
      stampPaint,
    );
    final stampText = TextPainter(
      text: TextSpan(
        text: '精品',
        // [锁定] 假书封面印章装饰字，canvas 自绘随封面缩放，
        // 不走 textTheme（6.5sp 低于可读下限仅因它是装饰印记）。
        style: TextStyle(
          color: accentColor.withValues(alpha: 0.65),
          fontSize: 6.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    stampText.paint(
      canvas,
      Offset(centerX - stampText.width / 2, bottomY - stampText.height / 2),
    );
  }

  void _paintCompact(Canvas canvas, Size size, double spineWidth) {
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        // [锁定] 迷你封面（<70dp）上的装饰性书名字，canvas 自绘
        // 随封面缩放，不走 textTheme 语义档。
        style: TextStyle(
          color: titleColor,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    )..layout(maxWidth: size.width - spineWidth - 6.0);

    final origin = Offset(
      spineWidth + (size.width - spineWidth - titlePainter.width) / 2,
      (size.height - titlePainter.height) / 2,
    );
    titlePainter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_DefaultCoverPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.titleColor != titleColor ||
      oldDelegate.authorColor != authorColor ||
      oldDelegate.title != title ||
      oldDelegate.author != author;
}

// ---------------------------------------------------------------------------
// 宫格 / 双列 / 列表 cards.
// ---------------------------------------------------------------------------

/// 宫格条目：满格宽封面（比 1.4）+ 进度角标 + 两行标题 + 一行副信息。
///
/// 按压与长按都交给 [HomePressable]（内部是官方 `InkWell`，自带 state layer），
/// 不再套外层 `GestureDetector`，命中区与按压态才是同一块。
class BookshelfGridCard extends StatelessWidget {
  final MediaItem item;
  final String? badgeText;
  final String? infoText;
  final bool editing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const BookshelfGridCard({
    super.key,
    required this.item,
    required this.onTap,
    this.badgeText,
    this.infoText,
    this.editing = false,
    this.selected = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final titleHeight =
        scaler.scale(ShelfTokens.titleGrid) * ShelfTokens.titleLineHeight * 2;
    return Semantics(
      button: true,
      selected: selected,
      label: item.title,
      child: HomePressable(
        onTap: onTap,
        onLongPress: onLongPress,
        semanticLabel: item.title,
        borderRadius: Md3Shape.smallRadius,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : shelfGridCellWidth(360);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    _ShelfCover(
                      item: item,
                      width: width,
                      height: width * ShelfTokens.gridCoverRatio,
                      radius: ShelfTokens.radiusCover,
                      badgeText: editing ? null : badgeText,
                      selected: selected,
                    ),
                    if (editing)
                      Positioned(
                        top: 5,
                        left: 5,
                        child: _SelectionBox(
                          selected: selected,
                          border: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: titleHeight,
                  width: double.infinity,
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ShelfTokens.titleGrid,
                      fontWeight: FontWeight.w500,
                      height: ShelfTokens.titleLineHeight,
                      color: palette.ink,
                    ),
                  ),
                ),
                if (infoText != null) ...[
                  const SizedBox(height: ShelfTokens.spaceXS),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      infoText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ShelfTokens.subtitle,
                        height: ShelfTokens.subtitleLineHeight,
                        color: palette.muted,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 双列条目：整格是一张卡（surface 底、radius 14、line 描边），上半封面
/// （满格宽减 padding、比 1.4），下半 标题 1 行 + 副信息 1 行 + 类型标签。
///
/// 取消了官方的封面/信息卡 84dp 重叠布局：重叠栈在无障碍大字号下需要手工
/// 对齐两套高度，且信息卡盖住封面下沿的「悬浮」观感在扁平分层语言里收益
/// 不成正比；改成顺排 Column 后几何全部由 token 推导，不会重叠。
class BookshelfDoubleCard extends StatelessWidget {
  final MediaItem item;
  final String? badgeText;
  final String? subtitleText;
  final bool editing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const BookshelfDoubleCard({
    super.key,
    required this.item,
    required this.onTap,
    this.badgeText,
    this.subtitleText,
    this.editing = false,
    this.selected = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final titleHeight =
        scaler.scale(ShelfTokens.titleDouble) * ShelfTokens.titleLineHeight;
    final subtitleHeight =
        scaler.scale(ShelfTokens.subtitle) * ShelfTokens.subtitleLineHeight;
    final kindColor = bookshelfKindColor(item.kind);
    return Semantics(
      button: true,
      selected: selected,
      label: item.title,
      child: HomePressable(
        onTap: onTap,
        onLongPress: onLongPress,
        semanticLabel: item.title,
        borderRadius: Md3Shape.mediumRadius,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 160.0;
            final coverWidth = math.max(
              1.0,
              cellWidth - ShelfTokens.doubleCardPadding * 2,
            );
            final coverHeight = coverWidth * ShelfTokens.doubleCoverRatio;
            final tagHeight = shelfKindTagHeight(context);
            return Card.filled(
              key: const Key('shelf-double-card'),
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: Md3Shape.mediumRadius,
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(ShelfTokens.doubleCardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        _ShelfCover(
                          item: item,
                          width: coverWidth,
                          height: coverHeight,
                          radius: ShelfTokens.radiusCover,
                          badgeText: editing ? null : badgeText,
                          selected: selected,
                        ),
                        if (editing)
                          Positioned(
                            top: 5,
                            left: 5,
                            child: _SelectionBox(
                              selected: selected,
                              border: Theme.of(context).colorScheme.surface,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: ShelfTokens.spaceS),
                    SizedBox(
                      height: titleHeight,
                      width: double.infinity,
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ShelfTokens.titleDouble,
                          fontWeight: FontWeight.w600,
                          height: ShelfTokens.titleLineHeight,
                          color: palette.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: ShelfTokens.spaceXS),
                    if (subtitleText != null)
                      SizedBox(
                        height: subtitleHeight,
                        width: double.infinity,
                        child: Text(
                          subtitleText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ShelfTokens.subtitle,
                            height: ShelfTokens.subtitleLineHeight,
                            color: palette.muted,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    // 类型小标签：kind 色 12% 底（数据真实存在，非装饰）。
                    SizedBox(
                      height: tagHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: (kindColor ?? palette.muted).withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: Md3Shape.smallRadius,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ShelfTokens.spaceS,
                          ),
                          child: Text(
                            bookshelfKindLabel(item.kind),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: ShelfTokens.kindTagSize,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                              color: kindColor ?? palette.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 列表条目：官方两行 `ListTile`（72dp 最小行高）+ 行底标准进度条。
///
/// 行级用框架的 `ListTile`（自带 state layer / 48dp 触区 / a11y 语义）而不是
/// 手搓 `InkWell` + `Row`：整行缩放的位移感在密集列表里会抖，卡片级的缩放
/// 只留给宫格/双列。
class BookshelfListCard extends StatelessWidget {
  final MediaItem item;
  final String? progressText;
  final String? metaText;

  /// 阅读进度 0..1；无值时不渲染行底进度条。
  final double? progress;
  final bool editing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const BookshelfListCard({
    super.key,
    required this.item,
    required this.onTap,
    this.progressText,
    this.metaText,
    this.progress,
    this.editing = false,
    this.selected = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final subtitleStyle = textTheme.bodySmall?.copyWith(
      height: ShelfTokens.subtitleLineHeight,
      color: scheme.onSurfaceVariant,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: item.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            onTap: onTap,
            onLongPress: onLongPress,
            // 官方两行 ListTile 最小 72dp；大字号下由内容自然撑高。
            minTileHeight: ShelfTokens.listRowHeight,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: ShelfTokens.screenPadding,
            ),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (editing) ...[
                  _SelectionBox(selected: selected, border: scheme.outline),
                  const SizedBox(width: ShelfTokens.spaceM),
                ],
                _ShelfCover(
                  item: item,
                  width: ShelfTokens.listCoverWidth,
                  height: ShelfTokens.listCoverHeight,
                  radius: ShelfTokens.radiusListCover,
                  selected: selected,
                ),
              ],
            ),
            // 标题字重交给 listTileTheme（M3 列表标题不加粗）。
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
            ),
            subtitle: (progressText == null && metaText == null)
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (progressText != null)
                        Text(
                          progressText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: subtitleStyle,
                        ),
                      if (metaText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            metaText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: subtitleStyle,
                          ),
                        ),
                    ],
                  ),
          ),
          if (progress != null)
            SizedBox(
              key: const Key('shelf-list-progress'),
              height: ShelfTokens.listProgressHeight,
              width: double.infinity,
              child: LinearProgressIndicator(
                value: progress!.clamp(0, 1),
                minHeight: ShelfTokens.listProgressHeight,
                color: scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
        ],
      ),
    );
  }
}
