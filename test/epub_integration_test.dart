import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/epub/epub_builder.dart';
import 'package:fqapp/services/epub/epub_document.dart';

/// 端到端：造一本完整的书，落成真实 .epub 文件，供外部工具校验结构。
void main() {
  test('生成可被外部校验的完整 EPUB', () {
    final cover = File('assets/branding/app_icon_source.png').readAsBytesSync();
    const meta = EpubMetadata(
      bookId: '700123456789',
      title: '重生 08：豆包成了我的外挂',
      author: '某某某',
      abstract: '一句话简介，含 <特殊字符> & 引号「测试」。\n第二段简介。',
      category: '都市',
      tags: ['重生', '系统', '校园'],
      score: '9.2',
      scoreCount: '12345',
      wordNumber: '120.5万',
      serialCount: '412',
      readCount: '88.6万',
      shelfCount: '3.2万',
      publisher: '番茄小说',
      published: '2024-03-01',
      updated: '2026-11-01',
      originalName: '原名测试',
      status: '完结',
      source: 'https://example.com/cover.jpg',
      roles: ['主角：林澈', '配角：苏晚'],
      chapterCount: 412,
    );
    final chapters = List.generate(
      12,
      (i) => EpubChapter(
        title: '第${i + 1}章 测试标题 & <标签>',
        paragraphs: List.generate(
          30,
          (j) => '这是第${i + 1}章第${j + 1}段的正文，用来验证分段、转义与分卷逻辑。',
        ),
      ),
    );

    final pkg = buildEpubPackage(
      meta: meta,
      chapters: chapters,
      cover: Uint8List.fromList(cover),
      modifiedAt: DateTime.utc(2026, 11, 8, 6, 0, 0),
    );

    File('/tmp/verify.epub').writeAsBytesSync(pkg.bytes);
    expect(pkg.chapterCount, 12);
    expect(pkg.hasCover, isTrue);
    expect(pkg.coverMime, 'image/png');
    expect(pkg.uuid, startsWith('urn:uuid:'));
  });
}
