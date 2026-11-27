import 'dart:convert';

/// Book facts the EPUB package writes into `content.opf` and the title page.
///
/// Field-for-field port of `fetcher/pack_epub.py::meta_block`, so an EPUB this
/// app exports opens with the same metadata as one the batch tool produced:
/// Dublin Core core fields, schema.org extensions, and the `fq:` namespace for
/// the counters Fanqie exposes but no standard vocabulary covers.
class EpubMetadata {
  const EpubMetadata({
    this.bookId = '',
    this.title = '',
    this.subtitle = '',
    this.author = '',
    this.abstract = '',
    this.category = '',
    this.tags = const [],
    this.score = '',
    this.scoreCount = '',
    this.wordNumber = '',
    this.serialCount = '',
    this.readCount = '',
    this.shelfCount = '',
    this.publisher = '',
    this.published = '',
    this.updated = '',
    this.originalName = '',
    this.status = '',
    this.source = '',
    this.roles = const [],
    this.chapterCount = 0,
  });

  /// Serializes itself; the exporter puts it in the cache record so reopening
  /// the export sheet does not re-fetch the detail payload.
  Map<String, Object?> toMap() => {
    'bookId': bookId,
    'title': title,
    'subtitle': subtitle,
    'author': author,
    'abstract': abstract,
    'category': category,
    'tags': tags,
    'score': score,
    'scoreCount': scoreCount,
    'wordNumber': wordNumber,
    'serialCount': serialCount,
    'readCount': readCount,
    'shelfCount': shelfCount,
    'publisher': publisher,
    'published': published,
    'updated': updated,
    'originalName': originalName,
    'status': status,
    'source': source,
    'roles': roles,
    'chapterCount': chapterCount,
  };

  final String bookId;
  final String title;
  final String subtitle;
  final String author;
  final String abstract;
  final String category;
  final List<String> tags;

  /// Rating on a 0-10 scale. Empty when the book has none.
  final String score;
  final String scoreCount;
  final String wordNumber;
  final String serialCount;
  final String readCount;
  final String shelfCount;
  final String publisher;
  final String published;
  final String updated;
  final String originalName;

  /// `已完结` / `连载中` / `已断更`, or empty when the upstream status is unknown.
  final String status;
  final String source;
  final List<String> roles;
  final int chapterCount;

  bool get isEmpty => title.isEmpty && bookId.isEmpty;

  EpubMetadata copyWith({int? chapterCount}) => EpubMetadata(
    bookId: bookId,
    title: title,
    subtitle: subtitle,
    author: author,
    abstract: abstract,
    category: category,
    tags: tags,
    score: score,
    scoreCount: scoreCount,
    wordNumber: wordNumber,
    serialCount: serialCount,
    readCount: readCount,
    shelfCount: shelfCount,
    publisher: publisher,
    published: published,
    updated: updated,
    originalName: originalName,
    status: status,
    source: source,
    roles: roles,
    chapterCount: chapterCount ?? this.chapterCount,
  );
}

/// One chapter as the package writes it.
class EpubChapter {
  const EpubChapter({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  bool get isEmpty => paragraphs.every((p) => p.trim().isEmpty);
}

const _namespace = 'https://github.com/ch6vip/fqapp/ns/epub';

/// `content.opf` for one book.
///
/// [uuid] must already be the `urn:uuid:` string so `dtb:uid` and the NCX
/// agree with the OPF identifier.
String buildOpf({
  required EpubMetadata meta,
  required String uuid,
  required String modified,
  required bool hasCover,
  required String coverHref,
  required String coverMime,
  required int chapterCount,
}) {
  final subjects = <String>[
    if (meta.category.isNotEmpty) meta.category,
    for (final tag in meta.tags)
      if (tag != meta.category) tag,
  ];

  final out = <String>[
    '<?xml version="1.0" encoding="utf-8"?>',
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="bookid" xml:lang="zh-CN" '
        'prefix="schema: http://schema.org/ fq: $_namespace">',
    '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:opf="http://www.idpf.org/2007/opf">',
    '    <dc:identifier id="bookid">${xmlEscape(uuid)}</dc:identifier>',
    if (meta.bookId.isNotEmpty)
      '    <dc:identifier id="source-id">fanqie:${xmlEscape(meta.bookId)}</dc:identifier>',
    '    <dc:title id="main-title">${xmlEscape(meta.title)}</dc:title>',
    '    <meta refines="#main-title" property="title-type">main</meta>',
    '    <meta refines="#main-title" property="display-seq">1</meta>',
    if (meta.subtitle.isNotEmpty) ...[
      '    <dc:title id="sub-title">${xmlEscape(meta.subtitle)}</dc:title>',
      '    <meta refines="#sub-title" property="title-type">subtitle</meta>',
    ],
    '    <dc:creator id="creator">${xmlEscape(meta.author)}</dc:creator>',
    '    <meta refines="#creator" property="role" scheme="marc:relators">aut</meta>',
    '    <meta refines="#creator" property="file-as">${xmlEscape(meta.author)}</meta>',
    '    <dc:language>zh-CN</dc:language>',
    '    <dc:contributor id="platform">番茄小说</dc:contributor>',
    '    <meta refines="#platform" property="role" scheme="marc:relators">pbl</meta>',
    if (meta.abstract.isNotEmpty)
      '    <dc:description>${xmlEscape(meta.abstract)}</dc:description>',
    if (meta.publisher.isNotEmpty)
      '    <dc:publisher>${xmlEscape(meta.publisher)}</dc:publisher>',
    if (meta.published.isNotEmpty)
      '    <dc:date>${xmlEscape(meta.published)}</dc:date>',
    for (final subject in subjects)
      '    <dc:subject>${xmlEscape(subject)}</dc:subject>',
    if (meta.source.isNotEmpty)
      '    <dc:source>${xmlEscape(meta.source)}</dc:source>',
    '    <dc:rights>仅供个人阅读存档，版权归原作者及原平台所有。</dc:rights>',
    '    <meta property="dcterms:modified">${xmlEscape(modified)}</meta>',
    '    <meta property="rendition:layout">reflowable</meta>',
    '    <meta property="rendition:flow">scrolled-doc</meta>',
    if (meta.score.isNotEmpty) ...[
      '    <meta property="schema:ratingValue">${xmlEscape(meta.score)}</meta>',
      '    <meta property="schema:ratingBestRating">10</meta>',
      '    <meta property="schema:ratingWorstRating">0</meta>',
    ],
    if (meta.scoreCount.isNotEmpty)
      '    <meta property="schema:ratingCount">${xmlEscape(meta.scoreCount)}</meta>',
    if (meta.wordNumber.isNotEmpty)
      '    <meta property="schema:wordCount">${xmlEscape(meta.wordNumber)}</meta>',
    '    <meta property="schema:numberOfPages">$chapterCount</meta>',
    if (meta.status.isNotEmpty)
      '    <meta property="fq:serialStatus">${xmlEscape(meta.status)}</meta>',
    if (meta.updated.isNotEmpty)
      '    <meta property="fq:lastUpdated">${xmlEscape(meta.updated)}</meta>',
    if (hasCount(meta.readCount))
      '    <meta property="fq:readCount">${xmlEscape(meta.readCount)}</meta>',
    if (hasCount(meta.shelfCount))
      '    <meta property="fq:shelfCount">${xmlEscape(meta.shelfCount)}</meta>',
    if (meta.chapterCount > 0)
      '    <meta property="fq:chapterCount">$chapterCount</meta>',
    if (meta.originalName.isNotEmpty && meta.originalName != meta.title)
      '    <meta property="fq:originalName">${xmlEscape(meta.originalName)}</meta>',
    for (final role in meta.roles)
      '    <meta property="fq:role">${xmlEscape(role)}</meta>',
    if (meta.category.isNotEmpty) ...[
      '    <meta property="belongs-to-collection" id="col">${xmlEscape(meta.category)}</meta>',
      '    <meta refines="#col" property="collection-type">set</meta>',
    ],
    // EPUB 2 readers only look at this one.
    if (hasCover) '    <meta name="cover" content="cover-image"/>',
    '  </metadata>',
    '  <manifest>',
    '    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
    '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
    '    <item id="css" href="style.css" media-type="text/css"/>',
    '    <item id="titlepage" href="text/titlepage.xhtml" media-type="application/xhtml+xml"/>',
    '    <item id="tocpage" href="text/toc.xhtml" media-type="application/xhtml+xml"/>',
    if (hasCover) ...[
      '    <item id="cover-image" href="images/$coverHref" '
          'media-type="$coverMime" properties="cover-image"/>',
      '    <item id="coverpage" href="text/cover.xhtml" media-type="application/xhtml+xml"/>',
    ],
    for (var i = 1; i <= chapterCount; i++)
      '    <item id="ch$i" href="text/${chapterFile(i)}" media-type="application/xhtml+xml"/>',
    '  </manifest>',
    '  <spine toc="ncx">',
    if (hasCover) '    <itemref idref="coverpage" linear="no"/>',
    '    <itemref idref="titlepage"/>',
    '    <itemref idref="tocpage"/>',
    for (var i = 1; i <= chapterCount; i++) '    <itemref idref="ch$i"/>',
    '  </spine>',
    '</package>',
  ];
  return out.join('\n');
}

/// `text/ch00001.xhtml`.
String chapterFile(int index) => 'ch${index.toString().padLeft(5, '0')}.xhtml';

/// The cover page: a bare full-bleed image, nothing else.
String buildCoverPage({required String title, required String coverHref}) =>
    _xhtml(
      '封面',
      '<div class="cover-page"><img src="../images/$coverHref" '
          'alt="${xmlEscape(title)}"/></div>',
      className: 'cover',
    );

/// Title page: cover thumbnail, heading, fact table, tag pills, full abstract,
/// colophon. This is what turns a bare text dump into a book someone can open
/// and understand without the app.
String buildTitlePage({
  required EpubMetadata meta,
  required bool hasCover,
  required String coverHref,
}) {
  final rows = <(String, String)>[
    if (meta.category.isNotEmpty) ('分类', meta.category),
    if (meta.status.isNotEmpty) ('状态', meta.status),
    if (meta.score.isNotEmpty)
      (
        '评分',
        meta.scoreCount.isEmpty
            ? '${meta.score} / 10'
            : '${meta.score} / 10（${formatCount(meta.scoreCount)} 人评分）',
      ),
    if (meta.wordNumber.isNotEmpty) ('字数', formatWords(meta.wordNumber)),
    if (meta.chapterCount > 0)
      (
        '章节',
        meta.serialCount.isNotEmpty && meta.serialCount != '${meta.chapterCount}'
            ? '${meta.chapterCount} 章（连载至 ${meta.serialCount} 章）'
            : '${meta.chapterCount} 章',
      ),
    if (hasCount(meta.readCount))
      ('在读', '${formatCount(meta.readCount)} 人'),
    if (hasCount(meta.shelfCount))
      ('收藏', '${formatCount(meta.shelfCount)} 人'),
    if (meta.publisher.isNotEmpty) ('出版', meta.publisher),
    if (meta.published.isNotEmpty) ('首发', meta.published),
    if (meta.updated.isNotEmpty) ('更新', meta.updated),
    if (meta.originalName.isNotEmpty && meta.originalName != meta.title)
      ('原名', meta.originalName),
    if (meta.roles.isNotEmpty)
      ('角色', meta.roles.take(8).join('、')),
  ];

  final out = <String>['<div class="titlepage">'];
  if (hasCover) {
    out.add(
      '<img class="cover-thumb" src="../images/$coverHref" '
      'alt="${xmlEscape(meta.title)}"/>',
    );
  }
  out.add('<h1>${xmlEscape(meta.title)}</h1>');
  if (meta.subtitle.isNotEmpty) {
    out.add('<div class="subtitle">${xmlEscape(meta.subtitle)}</div>');
  }
  out.add('<div class="byline">${xmlEscape(meta.author)} 著</div>');

  if (rows.isNotEmpty) {
    out.add('<table class="facts">');
    for (final (key, value) in rows) {
      out.add('<tr><th>${xmlEscape(key)}</th><td>${xmlEscape(value)}</td></tr>');
    }
    out.add('</table>');
  }

  if (meta.tags.isNotEmpty) {
    out.add('<div class="section-title">标签</div><ul class="tags">');
    for (final tag in meta.tags) {
      out.add('<li>${xmlEscape(tag)}</li>');
    }
    out.add('</ul>');
  }

  if (meta.abstract.isNotEmpty) {
    out.add('<div class="section-title">内容简介</div><div class="intro">');
    for (final raw in meta.abstract.split(RegExp(r'\n+'))) {
      final para = raw.replaceAll('\u3000', ' ').trim();
      if (para.isNotEmpty) out.add('<p>${xmlEscape(para)}</p>');
    }
    out.add('</div>');
  }

  out.add('<div class="colophon">');
  out.add('<p>本电子书由「页屿」自动汇编，仅作个人阅读存档。</p>');
  if (meta.bookId.isNotEmpty) out.add('<p>作品编号：${xmlEscape(meta.bookId)}</p>');
  if (meta.source.isNotEmpty) out.add('<p>来源：${xmlEscape(meta.source)}</p>');
  out.add('<p>正文、简介、评分、标签等著作权归原作者及原平台所有，请勿用于商业用途。</p>');
  out.add('</div></div>');
  return _xhtml(meta.title, out.join('\n'), className: 'titlepage-body');
}

/// Plain-list table of contents page (the reader-facing one; `nav.xhtml` is the
/// machine-readable twin).
String buildTocPage(List<EpubChapter> chapters) {
  final items = <String>[];
  for (var i = 0; i < chapters.length; i++) {
    items.add(
      '<li><a href="${chapterFile(i + 1)}">'
      '${xmlEscape(chapters[i].title)}</a></li>',
    );
  }
  return _xhtml(
    '目录',
    '<div class="toc"><h2>目录</h2><ol>${items.join()}</ol></div>',
    className: 'toc-page',
  );
}

/// One chapter body. The `第 N 章` prefix is split into its own span so the
/// title reads the way the app shows it instead of repeating the number twice.
String buildChapterPage(EpubChapter chapter) {
  final match = _chapterNumbering.firstMatch(chapter.title);
  var number = '';
  var rest = chapter.title;
  if (match != null && (match.group(2) ?? '').trim().isNotEmpty) {
    number = '第 ${match.group(1)} 章';
    rest = match.group(2)!.trim();
  }
  final head = StringBuffer('<h2 class="chapter-title">');
  if (number.isNotEmpty) head.write('<span class="num">${xmlEscape(number)}</span>');
  head.write('${xmlEscape(rest)}</h2>');
  final body = StringBuffer()
    ..write('<div class="chapter">')
    ..write(head);
  for (final paragraph in chapter.paragraphs) {
    if (paragraph.trim().isEmpty) continue;
    body.write('<p>${xmlEscape(paragraph)}</p>');
  }
  body.write('</div>');
  return _xhtml(chapter.title, body.toString());
}

/// `nav.xhtml`, with both the reading order and the landmarks block.
String buildNav({
  required EpubMetadata meta,
  required List<EpubChapter> chapters,
  required bool hasCover,
}) {
  final out = <String>[
    '<?xml version="1.0" encoding="utf-8"?>',
    '<!DOCTYPE html>',
    '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN" lang="zh-CN">',
    '<head><meta charset="utf-8"/><title>目录</title>',
    '<link rel="stylesheet" type="text/css" href="style.css"/></head><body>',
    '  <nav epub:type="toc" id="toc"><h1>目录</h1><ol>',
    '    <li><a href="text/titlepage.xhtml">书籍信息</a></li>',
  ];
  for (var i = 0; i < chapters.length; i++) {
    out.add(
      '    <li><a href="text/${chapterFile(i + 1)}">'
      '${xmlEscape(chapters[i].title)}</a></li>',
    );
  }
  out
    ..add('  </ol></nav>')
    ..add('  <nav epub:type="landmarks" id="landmarks" hidden="hidden">'
        '<h2>导航</h2><ol>');
  if (hasCover) {
    out.add('    <li><a epub:type="cover" href="text/cover.xhtml">封面</a></li>');
  }
  out
    ..add('    <li><a epub:type="toc" href="text/toc.xhtml">目录</a></li>')
    ..add('    <li><a epub:type="bodymatter" href="text/${chapterFile(1)}">'
        '正文</a></li>')
    ..add('  </ol></nav>')
    ..add('</body></html>');
  return out.join('\n');
}

/// `toc.ncx` — EPUB 2 fallback. Still required by `spine toc="ncx"`.
String buildNcx({
  required EpubMetadata meta,
  required String uuid,
  required List<EpubChapter> chapters,
}) {
  final out = <String>[
    '<?xml version="1.0" encoding="utf-8"?>',
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="zh-CN">',
    '  <head>',
    '    <meta name="dtb:uid" content="${xmlEscape(uuid)}"/>',
    '    <meta name="dtb:depth" content="1"/>',
    '    <meta name="dtb:totalPageCount" content="0"/>',
    '    <meta name="dtb:maxPageNumber" content="0"/>',
    '  </head>',
    '  <docTitle><text>${xmlEscape(meta.title)}</text></docTitle>',
    '  <docAuthor><text>${xmlEscape(meta.author)}</text></docAuthor>',
    '  <navMap>',
    '    <navPoint id="np-title" playOrder="1">'
        '<navLabel><text>书籍信息</text></navLabel>'
        '<content src="text/titlepage.xhtml"/></navPoint>',
  ];
  var order = 1;
  for (var i = 0; i < chapters.length; i++) {
    order++;
    out.add(
      '    <navPoint id="np$order" playOrder="$order">'
      '<navLabel><text>${xmlEscape(chapters[i].title)}</text></navLabel>'
      '<content src="text/${chapterFile(i + 1)}"/></navPoint>',
    );
  }
  out.add('  </navMap></ncx>');
  return out.join('\n');
}

/// `META-INF/container.xml`.
const containerXml =
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
    '  <rootfiles>\n'
    '    <rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/>\n'
    '  </rootfiles>\n'
    '</container>\n';

/// The stylesheet every page links. Same rules as the batch tool, so the two
/// outputs look identical on the same reader.
const epubCss = '''
html { font-size: 100%; }
body {
  font-family: "Noto Serif SC", "Source Han Serif SC", "Songti SC", "STSong", "SimSun", serif;
  line-height: 1.78;
  margin: 0 0.6em;
  color: #1f1c18;
  background: #fdfbf7;
  -webkit-hyphens: auto;
  hyphens: auto;
}
.cover-page { margin: 0; padding: 0; text-align: center; }
.cover-page img { max-width: 100%; max-height: 100%; }
.titlepage { padding: 1.2em 0.4em; }
.titlepage .cover-thumb {
  display: block; margin: 0 auto 1.4em; width: 46%; max-width: 220px;
  border-radius: 4px; box-shadow: 0 6px 18px rgba(0,0,0,.22);
}
.titlepage h1 {
  font-size: 1.6em; line-height: 1.35; text-align: center;
  margin: 0 0 .5em; letter-spacing: .02em;
}
.titlepage .subtitle {
  text-align: center; font-size: .92em; color: #6b6259; margin: -.2em 0 1.6em;
}
.titlepage .byline { text-align: center; font-size: 1em; color: #3d372f; margin: 0 0 1.6em; }
.facts { margin: 0 auto 1.6em; width: 100%; border-collapse: collapse; font-size: .86em; }
.facts th, .facts td { padding: .42em .3em; vertical-align: top; text-align: left; }
.facts th { width: 5.4em; color: #7a7168; font-weight: normal; white-space: nowrap; }
.facts tr + tr th, .facts tr + tr td { border-top: 1px solid #e8e1d7; }
.section-title {
  font-size: 1.02em; font-weight: bold; margin: 2em 0 .8em;
  padding-left: .55em; border-left: 3px solid #b4532a; line-height: 1.3;
}
.intro p { text-indent: 2em; margin: .6em 0; color: #322c25; font-size: .95em; }
.tags { margin: .2em 0 0; padding: 0; list-style: none; font-size: .84em; }
.tags li {
  display: inline-block; margin: 0 .4em .45em 0; padding: .16em .62em;
  border: 1px solid #d8cec1; border-radius: 999px; color: #6b6259;
}
.colophon { margin-top: 2.4em; font-size: .78em; color: #8a8177; line-height: 1.7; }
.colophon p { text-indent: 0; margin: .25em 0; }
.chapter { padding-top: .4em; }
h2.chapter-title {
  font-size: 1.22em; line-height: 1.45; text-align: center;
  margin: 1.1em 0 1.5em; font-weight: bold; letter-spacing: .02em;
}
h2.chapter-title .num { display: block; font-size: .62em; color: #9a9086; font-weight: normal; margin-bottom: .35em; }
p { text-indent: 2em; margin: .52em 0; text-align: justify; }
.toc h2 { text-align: center; font-size: 1.3em; margin: 1.2em 0 1.4em; }
.toc ol { list-style: none; margin: 0; padding: 0; font-size: .92em; }
.toc li { margin: 0; padding: .34em 0; border-bottom: 1px dotted #e4dccf; }
.toc li a { color: #2b2620; text-decoration: none; }
@media (prefers-color-scheme: dark) {
  body { background: #14120f; color: #cfc7ba; }
  .intro p { color: #bdb4a7; }
  .facts th, .titlepage .subtitle, .colophon { color: #8b8377; }
  .toc li a { color: #ddd5c8; }
  .toc li { border-bottom-color: #2a2620; }
}
''';

/// XML text escape. Also strips control characters XML 1.0 forbids outright —
/// an upstream abstract with a stray `\u0008` would otherwise make the package
/// unparseable.
String xmlEscape(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    switch (rune) {
      case 0x26:
        out.write('&amp;');
      case 0x3c:
        out.write('&lt;');
      case 0x3e:
        out.write('&gt;');
      case 0x22:
        out.write('&quot;');
      case 0x27:
        out.write('&apos;');
      default:
        if (rune == 0x9 || rune == 0xa || rune == 0xd || rune >= 0x20) {
          if (rune < 0xd800 || rune > 0xdfff) out.writeCharCode(rune);
        }
    }
  }
  return out.toString();
}

/// `12.3万` style counters, matching what the detail page shows.
String formatCount(String raw) {
  final value = double.tryParse(raw);
  if (value == null) return raw;
  if (value >= 100000000) return '${_trim(value / 100000000)}亿';
  if (value >= 10000) return '${_trim(value / 10000)}万';
  return value.toStringAsFixed(0);
}

/// `字数` column: `123.4 万字`.
String formatWords(String raw) {
  final value = double.tryParse(raw);
  if (value == null) return raw;
  if (value >= 10000) return '${_trim(value / 10000)} 万字';
  return '${value.toStringAsFixed(0)} 字';
}

/// A counter that is present and not zero. Upstream sends `0` and `0.0` for
/// books it has no number for; printing `0 人在读` would be a lie.
/// 在读 / 收藏这类计数在源数据里常带「万」「亿」后缀，`double.tryParse`
/// 直接判不出来，会把真实数据整条丢掉。这里只判「有没有量」：
/// 空串、纯 0、0 万一律视为没有；其余（含 `10万+` 这种非纯数字）保留。
bool hasCount(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;
  final match = RegExp(r'^([0-9]+(?:\.[0-9]+)?)').firstMatch(text);
  if (match == null) return true;
  final value = double.tryParse(match.group(1)!) ?? 0;
  return value > 0;
}

String _trim(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

String _xhtml(String title, String body, {String className = ''}) {
  final cls = className.isEmpty ? '' : ' class="$className"';
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<!DOCTYPE html>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN" lang="zh-CN">\n'
      '<head><meta charset="utf-8"/><title>${xmlEscape(title)}</title>'
      '<link rel="stylesheet" type="text/css" href="../style.css"/></head>\n'
      '<body$cls>\n$body\n</body></html>';
}

/// `第 12 章 标题` → (`12`, `标题`). Same pattern the batch tool uses, including
/// the full-width digits some uploads use.
final _chapterNumbering = RegExp(
  r'^第\s*([0-9０-９零一二三四五六七八九十百千万]+)\s*[章节回卷]\s*[：:.、]?\s*(.*)$',
);

/// UTF-8 bytes of [text], the encoding every zip entry in the package uses.
List<int> utf8Bytes(String text) => utf8.encode(text);
