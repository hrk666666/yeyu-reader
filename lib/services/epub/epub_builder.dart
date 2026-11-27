import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'epub_document.dart';

/// A finished EPUB package held in memory, ready to hand to the platform sink.
class EpubPackage {
  const EpubPackage({
    required this.bytes,
    required this.uuid,
    required this.chapterCount,
    required this.hasCover,
    required this.coverMime,
  });

  final Uint8List bytes;

  /// `urn:uuid:...`, derived from the book id so re-exporting the same book
  /// yields the same identifier and readers treat it as one work.
  final String uuid;
  final int chapterCount;
  final bool hasCover;

  /// Sniffed from the cover bytes; empty when there is no cover.
  final String coverMime;
}

/// Assembles a complete EPUB 3 package.
///
/// Entry order matters: `mimetype` must come first and must be stored, not
/// deflated — every reader sniffs the first 30 bytes of the file to decide
/// whether it is looking at an EPUB at all.
///
/// Throws [ArgumentError] when there is nothing to write.
EpubPackage buildEpubPackage({
  required EpubMetadata meta,
  required List<EpubChapter> chapters,
  Uint8List? cover,
  DateTime? modifiedAt,
}) {
  if (chapters.isEmpty) {
    throw ArgumentError.value(chapters, 'chapters', 'EPUB 至少需要一个章节');
  }
  if (meta.title.trim().isEmpty) {
    throw ArgumentError.value(meta.title, 'meta.title', 'EPUB 需要书名');
  }

  final uuid = 'urn:uuid:${uuid5(_namespaceUrl, 'fanqie:${meta.bookId.isEmpty ? meta.title : meta.bookId}')}';
  final coverInfo = _sniffCover(cover);
  final hasCover = coverInfo != null;
  final modified = _isoUtc(modifiedAt ?? DateTime.now());
  final facts = meta.copyWith(chapterCount: chapters.length);

  final archive = Archive();

  void add(String name, List<int> data, {bool store = false}) {
    final file = store
        ? ArchiveFile.noCompress(name, data.length, data)
        : ArchiveFile(name, data.length, data);
    archive.addFile(file);
  }

  add('mimetype', utf8.encode('application/epub+zip'), store: true);
  add('META-INF/container.xml', utf8.encode(containerXml));
  add(
    'OEBPS/content.opf',
    utf8.encode(
      buildOpf(
        meta: facts,
        uuid: uuid,
        modified: modified,
        hasCover: hasCover,
        coverHref: coverInfo?.fileName ?? '',
        coverMime: coverInfo?.mime ?? '',
        chapterCount: chapters.length,
      ),
    ),
  );
  add(
    'OEBPS/nav.xhtml',
    utf8.encode(buildNav(meta: facts, chapters: chapters, hasCover: hasCover)),
  );
  add(
    'OEBPS/toc.ncx',
    utf8.encode(buildNcx(meta: facts, uuid: uuid, chapters: chapters)),
  );
  add('OEBPS/style.css', utf8.encode(epubCss));
  add(
    'OEBPS/text/titlepage.xhtml',
    utf8.encode(
      buildTitlePage(
        meta: facts,
        hasCover: hasCover,
        coverHref: coverInfo?.fileName ?? '',
      ),
    ),
  );
  add('OEBPS/text/toc.xhtml', utf8.encode(buildTocPage(chapters)));
  if (coverInfo != null) {
    add(
      'OEBPS/text/cover.xhtml',
      utf8.encode(
        buildCoverPage(title: facts.title, coverHref: coverInfo.fileName),
      ),
    );
    // Covers are already compressed images; deflating them again costs time and
    // saves nothing.
    add('OEBPS/images/${coverInfo.fileName}', cover!, store: true);
  }
  for (var i = 0; i < chapters.length; i++) {
    add(
      'OEBPS/text/${chapterFile(i + 1)}',
      utf8.encode(buildChapterPage(chapters[i])),
    );
  }

  final bytes = ZipEncoder().encodeBytes(archive);
  return EpubPackage(
    bytes: bytes,
    uuid: uuid,
    chapterCount: chapters.length,
    hasCover: hasCover,
    coverMime: coverInfo?.mime ?? '',
  );
}

class _CoverInfo {
  const _CoverInfo(this.fileName, this.mime);
  final String fileName;
  final String mime;
}

/// Magic-number sniffing: the upstream sometimes serves a WebP under a `.jpg`
/// name, and declaring the wrong media type makes strict readers drop the cover.
_CoverInfo? _sniffCover(Uint8List? data) {
  if (data == null || data.isEmpty) return null;
  if (data.length > 3 && data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff) {
    return const _CoverInfo('cover.jpg', 'image/jpeg');
  }
  if (data.length > 8 &&
      data[0] == 0x89 &&
      data[1] == 0x50 &&
      data[2] == 0x4e &&
      data[3] == 0x47) {
    return const _CoverInfo('cover.png', 'image/png');
  }
  if (data.length > 12 &&
      data[0] == 0x52 &&
      data[1] == 0x49 &&
      data[2] == 0x46 &&
      data[3] == 0x46 &&
      data[8] == 0x57 &&
      data[9] == 0x45 &&
      data[10] == 0x42 &&
      data[11] == 0x50) {
    return const _CoverInfo('cover.webp', 'image/webp');
  }
  if (data.length > 6 && data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46) {
    return const _CoverInfo('cover.gif', 'image/gif');
  }
  return null;
}

String _isoUtc(DateTime time) {
  final utc = time.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}'
      'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}

/// RFC 4122 name-based UUID (version 5). Dart has no built-in helper and the
/// identifier has to stay stable across exports, so the hash is done by hand.
String uuid5(String namespace, String name) {
  final namespaceBytes = _uuidToBytes(namespace);
  final hash = sha1.convert([...namespaceBytes, ...utf8.encode(name)]).bytes;
  final bytes = Uint8List.fromList(hash.sublist(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

List<int> _uuidToBytes(String uuid) {
  final hex = uuid.replaceAll('-', '');
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

/// RFC 4122 namespace for URLs.
const _namespaceUrl = '6ba7b811-9dad-11d1-80b4-00c04fd430c8';
