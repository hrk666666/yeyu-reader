import '../../models/book_detail.dart';
import 'epub_document.dart';

/// Upstream `creation_status` → the words the detail page shows.
const _statusText = {0: '已完结', 1: '连载中', 4: '已断更'};

/// Builds the package metadata straight from the raw detail payload.
///
/// [BookDetail] deliberately drops fields the reader does not display (rating
/// count, shelf count, publisher, 首发 date, character list), so an EPUB built
/// from it alone would ship a thinner title page than the batch tool produces.
/// Everything here is read defensively: the upstream sends numbers as strings
/// and occasionally omits a field entirely.
EpubMetadata metadataFromPayload(Map<String, dynamic> payload) {
  final data = resolveDetailData(payload) ?? const <String, dynamic>{};
  final detail = BookDetail.fromPayload(payload);

  final tags = _strings(data['tags']);
  final category = _text(data['category']).ifEmpty(
    tags.isEmpty ? '' : tags.first,
  );

  return EpubMetadata(
    bookId: _text(data['book_id']).ifEmpty(detail.bookId),
    title: _text(data['book_name']).ifEmpty(detail.title),
    subtitle: _text(data['sub_title']),
    author: _authorName(data).ifEmpty(detail.author.name),
    abstract: _text(data['abstract']).ifEmpty(detail.abstract),
    category: category,
    tags: tags,
    score: _score(data['score']),
    scoreCount: _counter(data['score_count']),
    wordNumber: _text(data['word_number']).ifEmpty(
      detail.wordNumber > 0 ? '${detail.wordNumber}' : '',
    ),
    serialCount: _text(data['serial_count']).ifEmpty(
      detail.serialCount > 0 ? '${detail.serialCount}' : '',
    ),
    readCount: _counter(data['read_count']),
    shelfCount: _counter(data['add_bookshelf_count']),
    publisher: _text(data['publisher']).ifEmpty(_text(data['press'])),
    published: _dateOnly(data['published_date']),
    updated: _dateOnly(data['last_chapter_update_time']),
    originalName: _text(data['original_book_name']),
    status: _statusText[_int(data['creation_status'])] ?? '',
    source: _text(data['source']),
    roles: _roles(data['roles']),
  );
}

/// The metadata a cached book can still describe when the detail request fails:
/// title and author are already on disk, everything else stays empty rather
/// than being invented.
EpubMetadata metadataFromCached({
  required String bookId,
  required String title,
  required String author,
  String category = '',
  List<String> tags = const [],
  String abstract = '',
  int chapterCount = 0,
}) => EpubMetadata(
  bookId: bookId,
  title: title,
  author: author.isEmpty ? '佚名' : author,
  category: category,
  tags: tags,
  abstract: abstract,
  chapterCount: chapterCount,
);

String _authorName(Map<String, dynamic> data) {
  final info = data['author_info'];
  if (info is Map) {
    final name = _text(info['user_name']);
    if (name.isNotEmpty) return name;
  }
  return _text(data['author']);
}

/// Ratings arrive on either a 0-10 or a 0-100 scale depending on the book;
/// anything at or below zero means "no rating", not "rated zero".
String _score(dynamic raw) {
  final value = double.tryParse(_text(raw));
  if (value == null || value <= 0) return '';
  final normalized = value > 10 ? value / 10 : value;
  return normalized.toStringAsFixed(1);
}

/// A counter the title page can print, or empty when the number is missing or
/// zero — `0 人在读` would be a lie, not a fact.
String _counter(dynamic raw) {
  final text = _text(raw).trim();
  if (text.isEmpty) return '';
  final value = double.tryParse(text);
  if (value != null && value <= 0) return '';
  return text;
}

/// Epoch seconds/millis → `2026-03-01`. Upstream mixes both magntitudes and
/// sometimes sends an already-formatted date.
String _dateOnly(dynamic raw) {
  final text = _text(raw).trim();
  if (text.isEmpty) return '';
  final value = int.tryParse(text);
  if (value == null) {
    final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(text);
    return match?.group(0) ?? '';
  }
  // 10-digit values are seconds, 13-digit are millis.
  final millis = value > 99999999999 ? value : value * 1000;
  final time = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)}';
}

/// `roles` is a list, a JSON array string, or a comma/、 separated string.
List<String> _roles(dynamic raw) {
  if (raw == null) return const [];
  final out = <String>[];
  void push(dynamic value) {
    var name = '';
    if (value is Map) {
      name = _text(value['name']).ifEmpty(
        _text(value['role_name']).ifEmpty(_text(value['RoleName'])),
      );
    } else {
      name = _text(value);
    }
    name = name.replaceAll(RegExp(r'''^['"]+|['"]+$'''), '').trim();
    if (name.isNotEmpty && !out.contains(name)) out.add(name);
  }

  if (raw is List) {
    raw.forEach(push);
    return out;
  }
  final text = _text(raw).trim();
  if (text.isEmpty) return const [];
  final stripped = text.startsWith('[') && text.endsWith(']')
      ? text.substring(1, text.length - 1)
      : text;
  for (final part in stripped.split(RegExp(r'[,、]+'))) {
    push(part);
  }
  return out;
}

List<String> _strings(dynamic raw) {
  if (raw is List) {
    return [
      for (final item in raw)
        if (_text(item).trim().isNotEmpty) _text(item).trim(),
    ];
  }
  return [
    for (final part in _text(raw).split(RegExp(r'[,，、]+')))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

int _int(dynamic raw) => int.tryParse(_text(raw).trim()) ?? -1;

String _text(dynamic raw) {
  if (raw == null) return '';
  if (raw is String) return raw;
  if (raw is num) return '$raw';
  return '';
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
