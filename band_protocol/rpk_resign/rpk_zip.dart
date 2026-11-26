/// rpk（本质是 zip）的读取与重建。
///
/// 改包名只需要动 manifest.json 一个文件，其余 190 多个文件的压缩流应当
/// 原样搬运：既省掉一次全量解压/压缩，也保证没被改动的字节与官方产物一致。
/// 所以这里把 zip 拆成「中央目录 + 每条的压缩数据区间」，重建时按需替换。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int _lfhSignature = 0x04034b50;
const int _cdSignature = 0x02014b50;
const int _eocdSignature = 0x06054b50;

/// 中央目录里的一条记录。
class RpkEntry {
  RpkEntry({
    required this.name,
    required this.flag,
    required this.method,
    required this.mtime,
    required this.mdate,
    required this.crc,
    required this.csize,
    required this.usize,
    required this.extra,
    required this.comment,
    required this.eattr,
    required this.verMade,
    required this.verNeed,
    required this.lfhOffset,
  });

  final String name;
  final int flag;
  final int method;
  final int mtime;
  final int mdate;
  final int crc;
  final int csize;
  final int usize;
  final Uint8List extra;
  final Uint8List comment;
  final int eattr;
  final int verMade;
  final int verNeed;
  final int lfhOffset;

  bool get isDirectory => name.endsWith('/');
  bool get isStored => method == 0;
}

/// 重建 zip 时的一条输入。
class RpkBuildEntry {
  RpkBuildEntry({
    required this.name,
    required this.method,
    required this.mtime,
    required this.mdate,
    required this.eattr,
    required this.verMade,
    required this.verNeed,
    this.raw,
    this.data,
    this.crc = 0,
    this.csize = 0,
    this.usize = 0,
    this.flag = 0,
    this.rawHeader,
    Uint8List? extra,
  }) : extra = extra ?? Uint8List(0);

  final String name;
  final int method;
  final int mtime;
  final int mdate;
  final int eattr;
  final int verMade;
  final int verNeed;

  /// 原样搬运的压缩数据（不解压）。
  final Uint8List? raw;

  /// 需要写入的明文（会重新压缩）。
  final Uint8List? data;

  final int crc;
  final int csize;
  final int usize;
  final int flag;
  final Uint8List extra;

  /// 原封不动的 local header（含 name 与 extra）。
  ///
  /// 搬运未改动条目时用它：local 与中央目录里的 extra 不保证一致，
  /// 重建 header 有可能丢掉工具链写入的字段。
  final Uint8List? rawHeader;
}

class RpkZip {
  RpkZip(this.bytes, this.entries, this.comment, this.eocdOffset);

  final Uint8List bytes;
  final List<RpkEntry> entries;
  final Uint8List comment;
  final int eocdOffset;

  /// 解析一个 zip/rpk（签名块不影响中央目录解析）。
  static RpkZip parse(Uint8List bytes) {
    final eocd = _findEocd(bytes);
    final view = ByteData.sublistView(bytes);
    final count = view.getUint16(eocd + 10, Endian.little);
    final cdSize = view.getUint32(eocd + 12, Endian.little);
    final cdOffset = view.getUint32(eocd + 16, Endian.little);
    final commentLen = view.getUint16(eocd + 20, Endian.little);
    final comment = Uint8List.sublistView(
      bytes,
      eocd + 22,
      eocd + 22 + commentLen,
    );

    final entries = <RpkEntry>[];
    var p = cdOffset;
    for (var i = 0; i < count; i++) {
      if (view.getUint32(p, Endian.little) != _cdSignature) {
        throw const FormatException('中央目录记录损坏');
      }
      final verMade = view.getUint16(p + 4, Endian.little);
      final verNeed = view.getUint16(p + 6, Endian.little);
      final flag = view.getUint16(p + 8, Endian.little);
      final method = view.getUint16(p + 10, Endian.little);
      final mtime = view.getUint16(p + 12, Endian.little);
      final mdate = view.getUint16(p + 14, Endian.little);
      final crc = view.getUint32(p + 16, Endian.little);
      final csize = view.getUint32(p + 20, Endian.little);
      final usize = view.getUint32(p + 24, Endian.little);
      final nameLen = view.getUint16(p + 28, Endian.little);
      final extraLen = view.getUint16(p + 30, Endian.little);
      final commentLength = view.getUint16(p + 32, Endian.little);
      final eattr = view.getUint32(p + 38, Endian.little);
      final lfhOffset = view.getUint32(p + 42, Endian.little);
      final name = utf8.decode(
        Uint8List.sublistView(bytes, p + 46, p + 46 + nameLen),
        allowMalformed: true,
      );
      final extra = Uint8List.sublistView(
        bytes,
        p + 46 + nameLen,
        p + 46 + nameLen + extraLen,
      );
      final commentBytes = Uint8List.sublistView(
        bytes,
        p + 46 + nameLen + extraLen,
        p + 46 + nameLen + extraLen + commentLength,
      );
      entries.add(RpkEntry(
        name: name,
        flag: flag,
        method: method,
        mtime: mtime,
        mdate: mdate,
        crc: crc,
        csize: csize,
        usize: usize,
        extra: extra,
        comment: commentBytes,
        eattr: eattr,
        verMade: verMade,
        verNeed: verNeed,
        lfhOffset: lfhOffset,
      ));
      p += 46 + nameLen + extraLen + commentLength;
    }
    if (p - cdOffset != cdSize) {
      throw const FormatException('中央目录长度与外层记录不一致');
    }
    return RpkZip(bytes, entries, comment, eocd);
  }

  static int _findEocd(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    var off = bytes.length - 22;
    while (off >= 0) {
      if (view.getUint32(off, Endian.little) == _eocdSignature) return off;
      off--;
    }
    throw const FormatException('不是有效的 zip/rpk：找不到 EOCD');
  }

  /// 原样的 local header（含文件名与 extra）。
  Uint8List rawLocalHeader(RpkEntry e) {
    final view = ByteData.sublistView(bytes);
    if (view.getUint32(e.lfhOffset, Endian.little) != _lfhSignature) {
      throw FormatException('local header 损坏: ${e.name}');
    }
    final nameLen = view.getUint16(e.lfhOffset + 26, Endian.little);
    final extraLen = view.getUint16(e.lfhOffset + 28, Endian.little);
    return Uint8List.sublistView(
        bytes, e.lfhOffset, e.lfhOffset + 30 + nameLen + extraLen);
  }

  /// 该条目在原始字节里 [起始, 结束) 的压缩数据区间（不含 local header）。
  Uint8List rawCompressed(RpkEntry e) {
    final view = ByteData.sublistView(bytes);
    if (view.getUint32(e.lfhOffset, Endian.little) != _lfhSignature) {
      throw FormatException('local header 损坏: ${e.name}');
    }
    final nameLen = view.getUint16(e.lfhOffset + 26, Endian.little);
    final extraLen = view.getUint16(e.lfhOffset + 28, Endian.little);
    final start = e.lfhOffset + 30 + nameLen + extraLen;
    return Uint8List.sublistView(bytes, start, start + e.csize);
  }

  /// 解压一条的内容。
  Uint8List read(RpkEntry e) {
    if (e.isDirectory || e.csize == 0) return Uint8List(0);
    final raw = rawCompressed(e);
    if (e.isStored) return Uint8List.fromList(raw);
    return Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
  }

  /// 便捷方法：按名字取内容。
  Uint8List? readByName(String name) {
    for (final e in entries) {
      if (e.name == name && !e.isDirectory) return read(e);
    }
    return null;
  }

  bool has(String name) => entries.any((e) => e.name == name && !e.isDirectory);
}

/// 把条目列表写成 zip 字节。
Uint8List buildZip(List<RpkBuildEntry> items, {List<int> comment = const <int>[]}) {
  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var count = 0;

  for (final item in items) {
    final nameBytes = utf8.encode(item.name);
    Uint8List payload;
    int crc;
    int csize;
    int usize;
    int flag = item.flag;

    final data = item.data;
    if (data != null) {
      crc = _crc32(data);
      usize = data.length;
      if (item.method == 8) {
        payload = Uint8List.fromList(ZLibEncoder(raw: true, level: 9).convert(data));
      } else {
        payload = data;
      }
      csize = payload.length;
      flag &= ~0x08; // 不用 data descriptor，尺寸已经写死
    } else {
      payload = item.raw ?? Uint8List(0);
      crc = item.crc;
      csize = item.csize;
      usize = item.usize;
    }

    final offset = out.length;
    final rawHeader = item.rawHeader;
    if (rawHeader != null) {
      out.add(rawHeader);
    } else {
      final lfh = ByteData(30);
      lfh.setUint32(0, _lfhSignature, Endian.little);
      lfh.setUint16(4, item.verNeed, Endian.little);
      lfh.setUint16(6, flag, Endian.little);
      lfh.setUint16(8, item.method, Endian.little);
      lfh.setUint16(10, item.mtime, Endian.little);
      lfh.setUint16(12, item.mdate, Endian.little);
      lfh.setUint32(14, crc, Endian.little);
      lfh.setUint32(18, csize, Endian.little);
      lfh.setUint32(22, usize, Endian.little);
      lfh.setUint16(26, nameBytes.length, Endian.little);
      lfh.setUint16(28, item.extra.length, Endian.little);
      out.add(lfh.buffer.asUint8List());
      out.add(nameBytes);
      out.add(item.extra);
    }
    out.add(payload);

    final cd = ByteData(46);
    cd.setUint32(0, _cdSignature, Endian.little);
    cd.setUint16(4, item.verMade, Endian.little);
    cd.setUint16(6, item.verNeed, Endian.little);
    cd.setUint16(8, flag, Endian.little);
    cd.setUint16(10, item.method, Endian.little);
    cd.setUint16(12, item.mtime, Endian.little);
    cd.setUint16(14, item.mdate, Endian.little);
    cd.setUint32(16, crc, Endian.little);
    cd.setUint32(20, csize, Endian.little);
    cd.setUint32(24, usize, Endian.little);
    cd.setUint16(28, nameBytes.length, Endian.little);
    cd.setUint16(30, item.extra.length, Endian.little);
    cd.setUint16(32, 0, Endian.little);
    cd.setUint16(34, 0, Endian.little);
    cd.setUint16(36, 0, Endian.little);
    cd.setUint32(38, item.eattr, Endian.little);
    cd.setUint32(42, offset, Endian.little);
    central.add(cd.buffer.asUint8List());
    central.add(nameBytes);
    central.add(item.extra);
    count++;
  }

  final cdOffset = out.length;
  out.add(central.takeBytes());
  final cdSize = out.length - cdOffset;

  final eocd = ByteData(22);
  eocd.setUint32(0, _eocdSignature, Endian.little);
  eocd.setUint16(4, 0, Endian.little);
  eocd.setUint16(6, 0, Endian.little);
  eocd.setUint16(8, count, Endian.little);
  eocd.setUint16(10, count, Endian.little);
  eocd.setUint32(12, cdSize, Endian.little);
  eocd.setUint32(16, cdOffset, Endian.little);
  eocd.setUint16(20, comment.length, Endian.little);
  out.add(eocd.buffer.asUint8List());
  out.add(comment);
  return out.takeBytes();
}

int _crc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
