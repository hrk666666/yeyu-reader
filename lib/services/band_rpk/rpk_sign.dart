/// rpk 签名块（`RPK Sig Block 42`）的构造与剥离。
///
/// 格式逆向自 @aiot-toolkit/aiotpack 的 SignUtil：
///   1. 把 zip 切成 header(本地文件区) / central(中央目录) / footer(EOCD) 三段
///   2. 每段算 SHA-256(0xA5 || uint32(长度) || 段字节)
///   3. 三段摘要拼成 (0x5A || uint32(3) || 三段摘要)，再取一次 SHA-256
///   4. 该摘要进 digest 块，RSA 签名的是整段 signdata
///   5. 签名块插在 header 与 central 之间，并修正 EOCD 里的中央目录偏移
///
/// 这里的字段长度必须逐字节与官方实现对齐（包括 saveDigestChunk 里
/// size 只记 body 长度这种细节），否则手环校验会直接拒绝安装。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'rpk_der.dart';
import 'rpk_rsa.dart';

const int _lfhSignature = 0x04034b50;
const int _cdSignature = 0x02014b50;
const int _eocdSignature = 0x06054b50;

/// 签名块尾部魔数。
final Uint8List signBlockMagic = ascii.encode('RPK Sig Block 42');

/// 一个待签名条目：路径 + 内容摘要。
class RpkFileDigest {
  const RpkFileDigest(this.name, this.digest);

  final String name;
  final Uint8List digest;
}

class _Section {
  _Section(this.start, this.length);

  final int start;
  final int length;
}

class _Sections {
  _Sections(this.header, this.central, this.footer);

  final _Section header;
  final _Section central;
  final _Section footer;
}

int _u32(Uint8List b, int o) => ByteData.sublistView(b).getUint32(o, Endian.little);

Uint8List _p32(int v) {
  final d = ByteData(4)..setUint32(0, v & 0xFFFFFFFF, Endian.little);
  return d.buffer.asUint8List();
}

int findEocd(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  var off = bytes.length - 22;
  while (off >= 0) {
    if (view.getUint32(off, Endian.little) == _eocdSignature) return off;
    off--;
  }
  throw const FormatException('不是有效的 zip/rpk：找不到 EOCD');
}

_Sections _parseSections(Uint8List bytes) {
  final eocd = findEocd(bytes);
  final cdOffset = _u32(bytes, eocd + 16);
  if (_u32(bytes, cdOffset) != _cdSignature) {
    throw const FormatException('中央目录起点异常');
  }
  final lfhOffset = _u32(bytes, cdOffset + 42);
  if (_u32(bytes, lfhOffset) != _lfhSignature) {
    throw const FormatException('本地文件头异常');
  }
  return _Sections(
    _Section(0, cdOffset),
    _Section(cdOffset, eocd - cdOffset),
    _Section(eocd, bytes.length - eocd),
  );
}

Uint8List _sectionDigest(Uint8List bytes, _Section s) {
  final data = Uint8List.sublistView(bytes, s.start, s.start + s.length);
  final buf = BytesBuilder(copy: false)
    ..addByte(0xA5)
    ..add(_p32(data.length))
    ..add(data);
  return Uint8List.fromList(crypto.sha256.convert(buf.takeBytes()).bytes);
}

/// 剥掉已有的签名块，得到一个「干净」zip。
///
/// 已经签过的包再签一次会不断叠加签名块，所以重签前必须先剥离。
Uint8List stripSignBlock(Uint8List bytes) {
  final eocd = findEocd(bytes);
  final cdOffset = _u32(bytes, eocd + 16);
  if (cdOffset < 16 || !_equalAt(bytes, cdOffset - 16, signBlockMagic)) {
    return bytes;
  }
  final size = _u32(bytes, cdOffset - 24);
  final start = cdOffset - size - 8;
  if (start < 0 || _u32(bytes, start) != size) {
    return bytes;
  }
  final out = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(bytes, 0, start))
    ..add(Uint8List.sublistView(bytes, cdOffset));
  final result = out.takeBytes();
  final newEocd = eocd - (cdOffset - start);
  ByteData.sublistView(result).setUint32(newEocd + 16, start, Endian.little);
  return result;
}

bool _equalAt(Uint8List bytes, int offset, Uint8List expected) {
  if (offset < 0 || offset + expected.length > bytes.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (bytes[offset + i] != expected[i]) return false;
  }
  return true;
}

/// 构造签名块。
///
/// [files] 必须是「包内每个文件（不含目录）的 SHA-256」，顺序随意；
/// [overallDigest] 是上面第 3 步算出的 32 字节。
Uint8List buildSignatureBlock({
  required List<RpkFileDigest> files,
  required Uint8List overallDigest,
  required RsaKeyPair key,
  required Uint8List certificate,
}) {
  final publicKey = rsaPublicKeyInfo(key);

  // 摘要块：len | id=0x0103 | len(digest) | digest
  final digestBlock = BytesBuilder(copy: false)
    ..add(_p32(overallDigest.length + 8))
    ..add(_p32(0x0103))
    ..add(_p32(overallDigest.length))
    ..add(overallDigest);
  final digestBytes = digestBlock.takeBytes();

  // 证书块：len | der
  final certBlock = BytesBuilder(copy: false)
    ..add(_p32(certificate.length))
    ..add(certificate);
  final certBytes = certBlock.takeBytes();

  final signdata = BytesBuilder(copy: false)
    ..add(_p32(digestBytes.length))
    ..add(digestBytes)
    ..add(_p32(certBytes.length))
    ..add(certBytes)
    ..add(_p32(0));
  final signdataBytes = signdata.takeBytes();

  final signature = rsaSignSha256(key, signdataBytes);
  final signatureBlock = BytesBuilder(copy: false)
    ..add(_p32(signature.length + 8))
    ..add(_p32(0x0103))
    ..add(_p32(signature.length))
    ..add(signature);
  final signatureBytes = signatureBlock.takeBytes();

  // signBlock.size 用的是 signatureBlock 的长度（+12），不是它自己的 size（+8）：
  // 官方实现里就这么写的，必须照抄。
  final signBlockSize =
      12 + publicKey.length + signdataBytes.length + signatureBytes.length;
  final signBlock = BytesBuilder(copy: false)
    ..add(_p32(signBlockSize))
    ..add(_p32(signdataBytes.length))
    ..add(signdataBytes)
    ..add(_p32(signatureBytes.length))
    ..add(signatureBytes)
    ..add(_p32(publicKey.length))
    ..add(publicKey);
  final signBlockBytes = signBlock.takeBytes();

  final kv1 = BytesBuilder(copy: false)
    ..add(_p32(signBlockBytes.length + 8))
    ..add(_p32(0))
    ..add(_p32(0x01000101))
    ..add(_p32(signBlockBytes.length))
    ..add(signBlockBytes);

  final fileHashBlock = _buildFileHashBlock(files, key);

  final kv2 = BytesBuilder(copy: false)
    ..add(_p32(fileHashBlock.length + 8))
    ..add(_p32(0))
    ..add(_p32(0x01000201))
    ..add(_p32(fileHashBlock.length))
    ..add(fileHashBlock);

  final kv = BytesBuilder(copy: false)
    ..add(kv1.takeBytes())
    ..add(kv2.takeBytes());
  final kvBytes = kv.takeBytes();

  final size = 24 + kvBytes.length;
  final out = BytesBuilder(copy: false)
    ..add(_p32(size))
    ..add(_p32(0))
    ..add(kvBytes)
    ..add(_p32(size))
    ..add(_p32(0))
    ..add(signBlockMagic);
  return out.takeBytes();
}

/// 文件哈希块：id | [crc32(路径) uint32 | 摘要长度 uint16 | 摘要]
Uint8List _buildFileHashBlock(List<RpkFileDigest> files, RsaKeyPair key) {
  final body = BytesBuilder(copy: false)..add(_p32(0x0103));
  for (final f in files) {
    final nameHash = _crc32(utf8.encode(f.name));
    body.add(_p32(nameHash));
    final len = ByteData(2)..setUint16(0, f.digest.length, Endian.little);
    body.add(len.buffer.asUint8List());
    body.add(f.digest);
  }
  final bodyBytes = body.takeBytes();
  final signature = rsaSignSha256(key, bodyBytes);
  // 官方实现里这个 size 只记 body 长度（不含签名头）
  final out = BytesBuilder(copy: false)
    ..add(_p32(bodyBytes.length))
    ..add(bodyBytes)
    ..add(_p32(signature.length + 8))
    ..add(_p32(0x0103))
    ..add(_p32(signature.length))
    ..add(signature);
  return out.takeBytes();
}

/// 给一个未签名的 zip 加上签名块，返回新的包字节。
Uint8List signZip(Uint8List bytes, List<RpkFileDigest> files,
    RsaKeyPair key, Uint8List certificate) {
  final sections = _parseSections(bytes);
  final whole = BytesBuilder(copy: false)
    ..addByte(0x5A)
    ..add(_p32(3))
    ..add(_sectionDigest(bytes, sections.header))
    ..add(_sectionDigest(bytes, sections.central))
    ..add(_sectionDigest(bytes, sections.footer));
  final overall = Uint8List.fromList(crypto.sha256.convert(whole.takeBytes()).bytes);

  final block = buildSignatureBlock(
    files: files,
    overallDigest: overall,
    key: key,
    certificate: certificate,
  );

  final out = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(bytes, 0, sections.header.start + sections.header.length))
    ..add(block)
    ..add(Uint8List.sublistView(
        bytes, sections.central.start, sections.central.start + sections.central.length));
  final footer = Uint8List.fromList(Uint8List.sublistView(
      bytes, sections.footer.start, sections.footer.start + sections.footer.length));
  ByteData.sublistView(footer).setUint32(
      16, sections.central.start + block.length, Endian.little);
  out.add(footer);
  return out.takeBytes();
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

// ---------------------------------------------------------------------------
// 自检：生成的包必须能被同样的规则验回来，否则不交给用户
// ---------------------------------------------------------------------------

/// 验一遍签名（外层 + 内层 CERT）。
///
/// 手环安装时就是按这套规则校验的：签名块的 signdata 用块内公钥验、
/// 三段摘要回算比对、内层 CERT 独立再验一次。返回 null 表示通过，
/// 否则是第一个失败原因（方便定位是产物坏了还是解析写错了）。
String? checkSignedRpk(Uint8List bytes) {
  final outer = _checkSignedZip(bytes);
  if (outer != null) return '外层：$outer';
  final cert = _findCertBytes(bytes);
  if (cert == null) return '外层：找不到 META-INF/CERT';
  final inner = _checkSignedZip(cert);
  if (inner != null) return '内层：$inner';
  return null;
}

bool verifySignedRpk(Uint8List bytes) => checkSignedRpk(bytes) == null;

String? _checkSignedZip(Uint8List bytes) {
  final eocd = findEocd(bytes);
  final cdOffset = _u32(bytes, eocd + 16);
  if (cdOffset < 16 || !_equalAt(bytes, cdOffset - 16, signBlockMagic)) {
    return '没有签名块';
  }
  final size = _u32(bytes, cdOffset - 24);
  final blockStart = cdOffset - size - 8;
  if (blockStart < 0 || _u32(bytes, blockStart) != size) return '签名块长度不自洽';
  final kv = _readKeyValues(bytes, blockStart + 8, blockStart + 8 + size - 16);
  final signer = kv[0x01000101];
  if (signer == null) return '缺少签名者块 0x01000101';
  final signerError = _checkSignerBlock(signer);
  if (signerError != null) return signerError;

  final clean = stripSignBlock(bytes);
  final sections = _parseSections(clean);
  final whole = BytesBuilder(copy: false)
    ..addByte(0x5A)
    ..add(_p32(3))
    ..add(_sectionDigest(clean, sections.header))
    ..add(_sectionDigest(clean, sections.central))
    ..add(_sectionDigest(clean, sections.footer));
  final overall = Uint8List.fromList(crypto.sha256.convert(whole.takeBytes()).bytes);
  if (!_equalBytes(overall, _digestOfSignerBlock(signer))) return '整体摘要不一致';
  return null;
}

Map<int, Uint8List> _readKeyValues(Uint8List bytes, int start, int limit) {
  final out = <int, Uint8List>{};
  var off = start;
  while (off + 16 <= limit) {
    final id = _u32(bytes, off + 8);
    final valueSize = _u32(bytes, off + 12);
    out[id] = Uint8List.sublistView(bytes, off + 16, off + 16 + valueSize);
    off += 16 + valueSize;
  }
  return out;
}

class _SignerParts {
  _SignerParts(this.signdata, this.signature, this.publicKey, this.digest);

  final Uint8List signdata;
  final Uint8List signature;
  final Uint8List publicKey;
  final Uint8List digest;
}

_SignerParts _splitSigner(Uint8List value) {
  final signdataSize = _u32(value, 4);
  final signdata = Uint8List.sublistView(value, 8, 8 + signdataSize);
  final rest = Uint8List.sublistView(value, 8 + signdataSize);
  final groupSize = _u32(rest, 0);
  final sigLen = _u32(rest, 12);
  final signature = Uint8List.sublistView(rest, 16, 16 + sigLen);
  final pubSize = _u32(rest, 4 + groupSize);
  final publicKey =
      Uint8List.sublistView(rest, 8 + groupSize, 8 + groupSize + pubSize);

  final digestAreaSize = _u32(signdata, 0);
  final digestLen = _u32(signdata, 12);
  final digest = Uint8List.sublistView(signdata, 16, 16 + digestLen);
  if (digestAreaSize == 0) {
    throw const FormatException('digest 块为空');
  }
  return _SignerParts(signdata, signature, publicKey, digest);
}

Uint8List _digestOfSignerBlock(Uint8List value) => _splitSigner(value).digest;

String? _checkSignerBlock(Uint8List value) {
  final parts = _splitSigner(value);
  final (n, e) = _rsaPublicKeyFromSpki(parts.publicKey);
  final k = (n.bitLength + 7) >> 3;
  if (parts.signature.length != k) {
    return '签名长度 ${parts.signature.length} 与模长 $k 不符';
  }
  final em = _modPow(_bytesToBigInt(parts.signature), e, n, k);
  const prefix = <int>[
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
    0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ];
  final expected = <int>[...prefix, ...crypto.sha256.convert(parts.signdata).bytes];
  if (em.length < expected.length + 11) return 'RSA 模长不足以容纳 PKCS#1 填充';
  if (em[0] != 0 || em[1] != 1) return 'PKCS#1 填充头不对';
  var i = 2;
  while (i < em.length && em[i] == 0xFF) {
    i++;
  }
  if (i < 10 || em[i] != 0) return 'PKCS#1 填充分隔符不对';
  if (!_equalBytes(Uint8List.sublistView(em, i + 1), Uint8List.fromList(expected))) {
    return 'signdata 与签名不匹配';
  }
  return null;
}

Uint8List? _findCertBytes(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final eocd = findEocd(bytes);
  final cdOffset = view.getUint32(eocd + 16, Endian.little);
  final count = view.getUint16(eocd + 10, Endian.little);
  var p = cdOffset;
  for (var i = 0; i < count; i++) {
    final nameLen = view.getUint16(p + 28, Endian.little);
    final extraLen = view.getUint16(p + 30, Endian.little);
    final commentLen = view.getUint16(p + 32, Endian.little);
    final name = String.fromCharCodes(
        Uint8List.sublistView(bytes, p + 46, p + 46 + nameLen));
    if (name == 'META-INF/CERT') {
      final method = view.getUint16(p + 10, Endian.little);
      final csize = view.getUint32(p + 20, Endian.little);
      final lfhOffset = view.getUint32(p + 42, Endian.little);
      final lfhNameLen = view.getUint16(lfhOffset + 26, Endian.little);
      final lfhExtraLen = view.getUint16(lfhOffset + 28, Endian.little);
      final start = lfhOffset + 30 + lfhNameLen + lfhExtraLen;
      final payload = Uint8List.sublistView(bytes, start, start + csize);
      if (method == 0) return payload;
      return Uint8List.fromList(ZLibDecoder(raw: true).convert(payload));
    }
    p += 46 + nameLen + extraLen + commentLen;
  }
  return null;
}

(BigInt, BigInt) _rsaPublicKeyFromSpki(Uint8List spki) {
  final root = parseDer(spki);
  final outer = root.children;
  final bitString = outer[1].value;
  final inner = Uint8List.sublistView(bitString, 1);
  final rsa = parseDer(inner).children;
  return (rsa[0].asInteger, rsa[1].asInteger);
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var hex = '0';
  for (final b in bytes) {
    hex += b.toRadixString(16).padLeft(2, '0');
  }
  return BigInt.parse(hex, radix: 16);
}

/// sig^e mod n，按模长补齐成定长字节。
Uint8List _modPow(BigInt base, BigInt exp, BigInt mod, int k) {
  final v = base.modPow(exp, mod);
  final out = Uint8List(k);
  var x = v;
  for (var i = k - 1; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xFF)).toInt();
    x >>= 8;
  }
  return out;
}

bool _equalBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
