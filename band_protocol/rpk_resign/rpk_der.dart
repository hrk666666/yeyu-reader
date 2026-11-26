/// 最小可用的 DER 编解码。
///
/// 手环 rpk 的签名块里带一份自签 X.509 证书和一个 SubjectPublicKeyInfo，
/// 安装时它们必须是标准 DER；Android 侧的 keystore 工具链帮不上忙，所以这里
/// 只实现「构造」和「解析」需要的几个类型（SEQUENCE / INTEGER / OID /
/// BIT STRING / UTCTime / UTF8String），不追求覆盖完整的 ASN.1。
library;

import 'dart:convert';
import 'dart:typed_data';

/// 一个 DER 节点的标签常量。
class DerTag {
  static const int integer = 0x02;
  static const int bitString = 0x03;
  static const int octetString = 0x04;
  static const int nullValue = 0x05;
  static const int oid = 0x06;
  static const int utf8String = 0x0C;
  static const int utcTime = 0x17;
  static const int sequence = 0x30;
  static const int set = 0x31;
}

/// 把内容包成 TLV。
Uint8List derTlv(int tag, List<int> body) {
  final out = BytesBuilder(copy: false);
  out.addByte(tag);
  out.add(_derLength(body.length));
  out.add(body);
  return out.toBytes();
}

List<int> _derLength(int len) {
  if (len < 0x80) return <int>[len];
  final tmp = <int>[];
  var v = len;
  while (v > 0) {
    tmp.insert(0, v & 0xFF);
    v >>= 8;
  }
  return <int>[0x80 | tmp.length, ...tmp];
}

/// 正整数的 DER 编码（大端、去前导零、必要时补一个 0 避免被当成负数）。
Uint8List derInteger(BigInt value) {
  assert(value >= BigInt.zero);
  var bytes = _unsignedBytes(value);
  if (bytes.isNotEmpty && bytes.first >= 0x80) {
    bytes = Uint8List.fromList(<int>[0, ...bytes]);
  }
  return derTlv(DerTag.integer, bytes);
}

/// 小整数。
Uint8List derSmallInt(int value) => derInteger(BigInt.from(value));

Uint8List _unsignedBytes(BigInt value) {
  if (value == BigInt.zero) return Uint8List.fromList(<int>[0]);
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List derSequence(List<List<int>> items) =>
    derTlv(DerTag.sequence, <int>[for (final i in items) ...i]);

Uint8List derSet(List<List<int>> items) =>
    derTlv(DerTag.set, <int>[for (final i in items) ...i]);

/// OBJECT IDENTIFIER。
Uint8List derOid(String dotted) {
  final parts = dotted.split('.').map(int.parse).toList();
  final body = <int>[parts[0] * 40 + parts[1]];
  for (final p in parts.skip(2)) {
    final chunk = <int>[];
    var v = p;
    do {
      chunk.insert(0, v & 0x7F);
      v >>= 7;
    } while (v > 0);
    for (var i = 0; i < chunk.length - 1; i++) {
      chunk[i] |= 0x80;
    }
    body.addAll(chunk);
  }
  return derTlv(DerTag.oid, body);
}

Uint8List derNull() => derTlv(DerTag.nullValue, const <int>[]);

/// BIT STRING（[unusedBits] 通常为 0）。
Uint8List derBitString(List<int> data, {int unusedBits = 0}) =>
    derTlv(DerTag.bitString, <int>[unusedBits, ...data]);

Uint8List derUtf8String(String text) =>
    derTlv(DerTag.utf8String, utf8.encode(text));

/// UTCTime（2050 年以前用两位年份，之后应由调用方换成 GeneralizedTime）。
Uint8List derUtcTime(DateTime time) {
  final u = time.toUtc();
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  final text = '${p(u.year % 100)}${p(u.month)}${p(u.day)}'
      '${p(u.hour)}${p(u.minute)}${p(u.second)}Z';
  return derTlv(DerTag.utcTime, text.codeUnits);
}

// ---------------------------------------------------------------------------
// 解析（读私钥 PEM 与证书用）
// ---------------------------------------------------------------------------

/// 一个解析出来的 TLV。
class DerNode {
  DerNode(this.tag, this.value, this.end);

  final int tag;
  final Uint8List value;

  /// 该节点在原 buffer 中的结束位置。
  final int end;

  List<DerNode> get children {
    final out = <DerNode>[];
    var off = 0;
    while (off < value.length) {
      final node = parseDer(value, off);
      out.add(node);
      off = node.end;
    }
    return out;
  }

  BigInt get asInteger => _toBigInt(value);

  String get asOid => _oidToString(value);

  String get asString => utf8.decode(value, allowMalformed: true);
}

DerNode parseDer(Uint8List buf, [int offset = 0]) {
  var off = offset;
  final tag = buf[off++];
  var len = buf[off++];
  if (len & 0x80 != 0) {
    final n = len & 0x7F;
    len = 0;
    for (var i = 0; i < n; i++) {
      len = (len << 8) | buf[off++];
    }
  }
  final value = Uint8List.sublistView(buf, off, off + len);
  return DerNode(tag, value, off + len);
}

BigInt _toBigInt(Uint8List bytes) {
  var hex = '0';
  for (final b in bytes) {
    hex += b.toRadixString(16).padLeft(2, '0');
  }
  return BigInt.parse(hex, radix: 16);
}

String _oidToString(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  final first = bytes[0];
  final parts = <String>['${first ~/ 40}', '${first % 40}'];
  var v = 0;
  for (final b in bytes.skip(1)) {
    v = (v << 7) | (b & 0x7F);
    if (b & 0x80 == 0) {
      parts.add('$v');
      v = 0;
    }
  }
  return parts.join('.');
}
