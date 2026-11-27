import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/epub/epub_builder.dart';
import 'package:fqapp/services/epub/epub_document.dart';
import 'package:fqapp/services/epub/epub_metadata.dart';
import 'package:xml/xml.dart';

/// EPUB 3 导出的包结构：条目顺序、mimetype 存储方式、manifest 与 spine 的
/// 一一对应，以及元数据是否按约定写进了 OPF。
void main() {
  const meta = EpubMetadata(
    bookId: '7184812049967352844',
    title: '重生 08，豆包成了我的外挂',
    author: '某作者',
    abstract: '第一段简介。\n第二段简介。',
    category: '都市脑洞',
    tags: ['都市脑洞', '系统流', '重生'],
    score: '8.9',
    scoreCount: '12000',
    wordNumber: '1328318',
    serialCount: '312',
    readCount: '79528',
    shelfCount: '0',
    status: '已完结',
    source: 'https://fanqienovel.com/page/7184812049967352844',
  );

  final chapters = [
    const EpubChapter(title: '第 1 章 开局', paragraphs: ['正文一。', '正文二。']),
    const EpubChapter(title: '第 2 章 落子', paragraphs: ['正文三。']),
  ];

  // A 1x1 PNG, enough for the sniffer to pick image/png.
  final cover = Uint8List.fromList(const [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  ]);

  group('buildEpubPackage', () {
    test('mimetype 必须是首个条目且不压缩', () {
      final package = buildEpubPackage(
        meta: meta,
        chapters: chapters,
        cover: cover,
      );
      final archive = ZipDecoder().decodeBytes(package.bytes);
      final first = archive.files.first;
      expect(first.name, 'mimetype');
      expect(utf8.decode(first.content as List<int>), 'application/epub+zip');
      expect(first.compression, CompressionType.none);
    });

    test('manifest 的章节条目与 spine 一一对应', () {
      final package = buildEpubPackage(
        meta: meta,
        chapters: chapters,
        cover: cover,
      );
      final archive = ZipDecoder().decodeBytes(package.bytes);
      final opf = _entry(archive, 'OEBPS/content.opf');

      final manifest = RegExp(
        r'<item id="ch(\d+)" href="text/ch\d+\.xhtml"',
      ).allMatches(opf).map((m) => m.group(1)).toList();
      final spine = RegExp(
        r'<itemref idref="ch(\d+)"/>',
      ).allMatches(opf).map((m) => m.group(1)).toList();
      expect(manifest, ['1', '2']);
      expect(spine, manifest);

      for (var i = 1; i <= chapters.length; i++) {
        expect(_entry(archive, 'OEBPS/text/${chapterFile(i)}'), contains('<p>'));
      }
    });

    test('封面写入 images/ 并登记为 cover-image', () {
      final package = buildEpubPackage(
        meta: meta,
        chapters: chapters,
        cover: cover,
      );
      expect(package.hasCover, isTrue);
      expect(package.coverMime, 'image/png');
      final archive = ZipDecoder().decodeBytes(package.bytes);
      final opf = _entry(archive, 'OEBPS/content.opf');
      expect(opf, contains('properties="cover-image"'));
      expect(opf, contains('href="images/cover.png"'));
      expect(opf, contains('<meta name="cover" content="cover-image"/>'));
      expect(_entry(archive, 'OEBPS/text/cover.xhtml'), contains('cover.png'));
    });

    test('元数据按约定写入 OPF', () {
      final package = buildEpubPackage(
        meta: meta,
        chapters: chapters,
        cover: cover,
      );
      final opf = _entry(
        ZipDecoder().decodeBytes(package.bytes),
        'OEBPS/content.opf',
      );
      expect(opf, contains('<dc:title id="main-title">重生 08，豆包成了我的外挂</dc:title>'));
      expect(opf, contains('<dc:creator id="creator">某作者</dc:creator>'));
      expect(opf, contains('fanqie:7184812049967352844'));
      expect(opf, contains('schema:ratingValue">8.9'));
      expect(opf, contains('schema:ratingCount">12000'));
      expect(opf, contains('schema:wordCount">1328318'));
      expect(opf, contains('fq:serialStatus">已完结'));
      expect(opf, contains('fq:readCount">79528'));
      // Zero counters are omitted rather than printed as `0`.
      expect(opf, isNot(contains('fq:shelfCount')));
      expect(opf, contains('belongs-to-collection" id="col">都市脑洞'));
      expect(opf, contains('<dc:subject>系统流</dc:subject>'));
    });

    test('书名页带完整信息与标签', () {
      final package = buildEpubPackage(
        meta: meta,
        chapters: chapters,
        cover: cover,
      );
      final page = _entry(
        ZipDecoder().decodeBytes(package.bytes),
        'OEBPS/text/titlepage.xhtml',
      );
      expect(page, contains('某作者 著'));
      expect(page, contains('8.9 / 10（1.2万 人评分）'));
      expect(page, contains('2 章（连载至 312 章）'));
      expect(page, contains('<li>系统流</li>'));
      expect(page, contains('第一段简介。'));
      expect(page, contains('作品编号：7184812049967352844'));
    });

    test('每个 XHTML/XML 条目都能被解析器读回', () {
      final package = buildEpubPackage(
        meta: meta,
        chapters: chapters,
        cover: cover,
      );
      final archive = ZipDecoder().decodeBytes(package.bytes);
      for (final file in archive.files) {
        if (!file.name.endsWith('.xhtml') &&
            !file.name.endsWith('.opf') &&
            !file.name.endsWith('.ncx') &&
            !file.name.endsWith('.xml')) {
          continue;
        }
        final text = utf8.decode(file.content as List<int>);
        expect(
          () => XmlDocument.parse(text),
          returnsNormally,
          reason: '${file.name} 不是合法 XML',
        );
      }
    });

    test('uuid 对同一本书保持稳定', () {
      final a = buildEpubPackage(meta: meta, chapters: chapters);
      final b = buildEpubPackage(meta: meta, chapters: chapters);
      expect(a.uuid, b.uuid);
      expect(a.uuid, startsWith('urn:uuid:'));
    });

    test('没有章节时拒绝打包', () {
      expect(
        () => buildEpubPackage(meta: meta, chapters: const []),
        throwsArgumentError,
      );
    });
  });

  group('uuid5', () {
    test('与 RFC 4122 示例一致', () {
      // python: uuid.uuid5(uuid.NAMESPACE_DNS, 'python.org')
      expect(
        uuid5('6ba7b810-9dad-11d1-80b4-00c04fd430c8', 'python.org'),
        '886313e1-3b8a-5372-9b90-0c9aee199e5d',
      );
    });
  });

  group('xmlEscape', () {
    test('转义五个 XML 实体并丢掉非法控制字符', () {
      expect(
        xmlEscape('a&b<c>"d"\u0008e'),
        'a&amp;b&lt;c&gt;&quot;d&quot;e',
      );
    });
  });

  group('metadataFromPayload', () {
    test('读上游字符串数字并忽略 0 计数', () {
      final meta = metadataFromPayload({
        'data': {
          'book_id': '42',
          'book_name': '测试书',
          'author_info': {'user_name': '作者甲'},
          'abstract': '简介',
          'category': '玄幻',
          'tags': '玄幻,热血',
          'score': '89',
          'score_count': '0',
          'word_number': '120000',
          'serial_count': '80',
          'read_count': '0',
          'add_bookshelf_count': '345',
          'creation_status': '0',
          'published_date': '1700000000',
          'roles': '["张三","李四"]',
        },
      });
      // 0-100 刻度的评分折算到 0-10。
      expect(meta.score, '8.9');
      expect(meta.scoreCount, '');
      expect(meta.readCount, '');
      expect(meta.shelfCount, '345');
      expect(meta.status, '已完结');
      expect(meta.category, '玄幻');
      expect(meta.tags, ['玄幻', '热血']);
      expect(meta.roles, ['张三', '李四']);
      expect(meta.published, '2023-11-14');
    });
  });
}

String _entry(Archive archive, String name) {
  final file = archive.findFile(name);
  expect(file, isNotNull, reason: '缺少条目 $name');
  return utf8.decode(file!.content as List<int>);
}
