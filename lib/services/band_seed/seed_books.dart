/// 把书籍数据转成手环端「数据目录」的文件映射。
///
/// 产物是一张 `路径 → 文本` 的表，键与手环 `internal://files/` 下的相对路径
/// 一致（`books/...`），由 [buildShellAppJs] 内联进 app.js，手环首次启动时
/// 再按这张表写盘。
///
/// 目录结构照手环端的读取实现（`utils/chapterManager.js`、`utils/interconnfile.js`）：
///
/// ```
/// books/bookshelf.json              version 必须是 3
/// books/<dirName>/book_info.json    书架补记录时读真实书名
/// books/<dirName>/lindex.txt        总章数 / 已同步章数 / 每个索引分片的章范围
/// books/<dirName>/indexes/<n>.txt   每行「序号 \t 标题 \t 字数」，一片 100 章
/// books/<dirName>/content/<i>.txt   一章一个文件
/// ```
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// 手环端每个索引分片容纳的章数（`CHAPTERS_PER_FILE`）。
const int kSeedChaptersPerChunk = 100;

/// 一本书的来源数据。
class SeedSourceBook {
  const SeedSourceBook({
    required this.title,
    required this.author,
    required this.chapters,
  });

  final String title;
  final String author;
  final List<SeedSourceChapter> chapters;

  int get wordCount =>
      chapters.fold(0, (sum, chapter) => sum + chapter.wordCount);
}

/// 一章的来源数据。
class SeedSourceChapter {
  const SeedSourceChapter({required this.title, required this.text});

  final String title;
  final String text;

  /// 手环端索引里记的字数：去掉空白後的字符数。
  int get wordCount => text.replaceAll(RegExp(r'\s'), '').length;
}

/// 生成 `books/...` 文件映射。
///
/// [now] 只用于书架进度里的时间戳，便于测试固定。
Map<String, String> buildSeedFiles(
  List<SeedSourceBook> books, {
  DateTime? now,
}) {
  if (books.isEmpty) {
    throw const FormatException('至少要选一本书');
  }
  final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final used = <String>{};
  final files = <String, String>{};
  final shelf = <Map<String, Object?>>[];

  for (var bookIndex = 0; bookIndex < books.length; bookIndex++) {
    final book = books[bookIndex];
    if (book.chapters.isEmpty) {
      throw FormatException('《${book.title}》没有章节');
    }
    final dirName = _uniqueDirName(book, used);
    final total = book.chapters.length;
    final wordCount = book.wordCount;

    files['books/$dirName/book_info.json'] = jsonEncode(<String, Object?>{
      'name': book.title,
      'chapterCount': total,
      'wordCount': wordCount,
      'hasCover': false,
      'coverFileName': '',
      'author': book.author,
      'summary': '',
      'bookStatus': '',
      'category': '',
      'localCategory': '',
    });

    files['books/$dirName/lindex.txt'] = _buildLindex(total);

    final chunks = <int, List<String>>{};
    for (var index = 0; index < total; index++) {
      final chapter = book.chapters[index];
      files['books/$dirName/content/$index.txt'] = chapter.text;
      final chunk = index ~/ kSeedChaptersPerChunk + 1;
      chunks
          .putIfAbsent(chunk, () => <String>[])
          .add('$index\t${_singleLine(chapter.title)}\t${chapter.wordCount}');
    }
    for (final entry in chunks.entries) {
      // 分片内每行以 \n 收尾，与手环端写出来的形态一致。
      files['books/$dirName/indexes/${entry.key}.txt'] =
          '${entry.value.join('\n')}\n';
    }

    shelf.add(<String, Object?>{
      'name': book.title,
      'dirName': dirName,
      'chapterCount': total,
      'wordCount': wordCount,
      'hasCover': false,
      'coverFileName': '',
      'progress': <String, Object?>{
        'chapterIndex': 0,
        'offsetInChapter': 0,
        'scrollOffset': 0,
        'chapterProgressPercent': 0,
        'lastReadTimestamp': stamp - bookIndex,
      },
      'localCategory': '',
    });
  }

  files['books/bookshelf.json'] = jsonEncode(<String, Object?>{
    'version': 3,
    'books': shelf,
  });
  return files;
}

/// `总章数\n已同步章数\n` 加上每个分片的 `start,end`。
///
/// 内置书是整本塞进包里的，所以已同步章数就是总章数。
String _buildLindex(int total) {
  final buffer = StringBuffer('$total\n$total\n');
  final chunks = (total / kSeedChaptersPerChunk).ceil();
  for (var i = 0; i < chunks; i++) {
    final start = i * kSeedChaptersPerChunk;
    final end = start + kSeedChaptersPerChunk - 1;
    buffer.write('$start,${end > total - 1 ? total - 1 : end}\n');
  }
  return buffer.toString();
}

/// 目录名用书的标题与作者算 8 位十六进制，和手环自己生成的形态一致。
String _uniqueDirName(SeedSourceBook book, Set<String> used) {
  final digest = crypto.sha1
      .convert(utf8.encode('${book.title}\u0000${book.author}'))
      .toString();
  var candidate = digest.substring(0, 8);
  var salt = 0;
  while (!used.add(candidate)) {
    salt++;
    candidate = digest.substring(salt % 32, (salt % 32) + 8);
  }
  return candidate;
}

/// 章节标题里的换行会把索引行拆断，压成空格。
String _singleLine(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();
