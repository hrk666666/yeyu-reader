/// RSA-2048 密钥生成与 PKCS#1 v1.5 签名（纯 Dart，不引第三方密码库）。
///
/// 为什么自己写：手环 rpk 的签名块要求 RSA-SHA256，而手机端只需「生成一对
/// 长期密钥、按 PKCS#1 v1.5 签两段字节」。引 pointycastle 会多一份几百 KB
/// 的原生/纯 Dart 依赖，而这里要的能力就是 BigInt.modPow —— Dart 自带。
///
/// 密钥只在手机上生成一次，存在 Secure Storage 里；私钥不出设备。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'rpk_der.dart';

/// SHA-256 的 DigestInfo 前缀（RFC 8017 9.2）。
const List<int> _sha256DigestInfo = <int>[
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
  0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
];

/// 一对 RSA 密钥。
class RsaKeyPair {
  const RsaKeyPair({
    required this.modulus,
    required this.exponent,
    required this.privateExponent,
    required this.prime1,
    required this.prime2,
  });

  final BigInt modulus;
  final BigInt exponent;
  final BigInt privateExponent;
  final BigInt prime1;
  final BigInt prime2;

  int get byteLength => (modulus.bitLength + 7) >> 3;
}

/// 生成一对 RSA 密钥（默认 2048 位）。
///
/// [bits] 只影响测试，线上固定 2048。生成耗时集中在找素数上：先用小素数
/// 试除掉绝大多数候选，再做 Miller-Rabin。
RsaKeyPair generateRsaKey({int bits = 2048, Random? random}) {
  final rnd = random ?? Random.secure();
  const e = 65537;
  final eBig = BigInt.from(e);
  final half = bits ~/ 2;
  while (true) {
    final p = _randomPrime(half, eBig, rnd);
    final q = _randomPrime(half, eBig, rnd);
    if (p == q) continue;
    final n = p * q;
    if (n.bitLength != bits) continue;
    final p1 = p - BigInt.one;
    final q1 = q - BigInt.one;
    final lambda = _lcm(p1, q1);
    final d = eBig.modInverse(lambda);
    return RsaKeyPair(
      modulus: n,
      exponent: eBig,
      privateExponent: d,
      prime1: p,
      prime2: q,
    );
  }
}

BigInt _lcm(BigInt a, BigInt b) => a ~/ a.gcd(b) * b;

const List<int> _smallPrimes = <int>[
  3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67,
  71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137, 139,
  149, 151, 157, 163, 167, 173, 179, 181, 191, 193, 197, 199, 211, 223,
  227, 229, 233, 239, 241, 251, 257, 263, 269, 271, 277, 281, 283, 293,
  307, 311, 313, 317, 331, 337, 347, 349, 353, 359, 367, 373, 379, 383,
  389, 397, 401, 409, 419, 421, 431, 433, 439, 443, 449, 457, 461, 463,
  467, 479, 487, 491, 499, 503, 509, 521, 523, 541, 547, 557, 563, 569,
  571, 577, 587, 593, 599, 601, 607, 613, 617, 619, 631, 641, 643, 647,
  653, 659, 661, 673, 677, 683, 691, 701, 709, 719, 727, 733, 739, 743,
  751, 757, 761, 769, 773, 787, 797, 809, 811, 821, 823, 827, 829, 839,
  853, 857, 859, 863, 877, 881, 883, 887, 907, 911, 919, 929, 937, 941,
  947, 953, 967, 971, 977, 983, 991, 997,
];

BigInt _randomPrime(int bits, BigInt e, Random rnd) {
  final bytes = (bits + 7) >> 3;
  while (true) {
    final buf = Uint8List(bytes);
    for (var i = 0; i < bytes; i++) {
      buf[i] = rnd.nextInt(256);
    }
    buf[0] |= 0x80; // 保证位数
    buf[bytes - 1] |= 1; // 保证奇数
    final candidate = _bytesToBigInt(buf);
    if (candidate.gcd(e) != BigInt.one) continue;
    var composite = false;
    for (final p in _smallPrimes) {
      if (candidate % BigInt.from(p) == BigInt.zero) {
        composite = true;
        break;
      }
    }
    if (composite) continue;
    if (!_millerRabin(candidate, rnd)) continue;
    return candidate;
  }
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var hex = '0';
  for (final b in bytes) {
    hex += b.toRadixString(16).padLeft(2, '0');
  }
  return BigInt.parse(hex, radix: 16);
}

/// Miller-Rabin，轮数取 8：随机候选下误判概率 < 4^-8，与 OpenSSL 默认档位相当。
bool _millerRabin(BigInt n, Random rnd) {
  if (n < BigInt.two) return false;
  var d = n - BigInt.one;
  var s = 0;
  while (d.isEven) {
    d >>= 1;
    s++;
  }
  final nMinusOne = n - BigInt.one;
  for (var round = 0; round < 8; round++) {
    // 固定前几个小基数 + 一个随机基数，兼顾速度与可靠性。
    final a = round < 4
        ? BigInt.from(<int>[2, 3, 5, 7][round])
        : BigInt.from(2 + rnd.nextInt(1 << 20));
    var x = a.modPow(d, n);
    if (x == BigInt.one || x == nMinusOne) continue;
    var witness = true;
    for (var r = 1; r < s; r++) {
      x = x.modPow(BigInt.two, n);
      if (x == nMinusOne) {
        witness = false;
        break;
      }
    }
    if (witness) return false;
  }
  return true;
}

/// PKCS#1 v1.5 + SHA-256 签名。
Uint8List rsaSignSha256(RsaKeyPair key, List<int> data) {
  final digest = crypto.sha256.convert(data).bytes;
  final t = <int>[..._sha256DigestInfo, ...digest];
  final k = key.byteLength;
  if (t.length + 11 > k) {
    throw StateError('密钥太短，放不下 PKCS#1 填充');
  }
  final em = Uint8List(k);
  em[0] = 0x00;
  em[1] = 0x01;
  final padLen = k - t.length - 3;
  for (var i = 0; i < padLen; i++) {
    em[2 + i] = 0xFF;
  }
  em[2 + padLen] = 0x00;
  em.setRange(3 + padLen, k, t);
  final m = _bytesToBigInt(em);
  final s = m.modPow(key.privateExponent, key.modulus);
  final out = Uint8List(k);
  var v = s;
  for (var i = k - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xFF)).toInt();
    v >>= 8;
  }
  return out;
}

/// 公钥的 SubjectPublicKeyInfo（DER）。
Uint8List rsaPublicKeyInfo(RsaKeyPair key) {
  final rsaPublic = derSequence(<List<int>>[
    derInteger(key.modulus),
    derInteger(key.exponent),
  ]);
  return derSequence(<List<int>>[
    derSequence(<List<int>>[
      derOid('1.2.840.113549.1.1.1'),
      derNull(),
    ]),
    derBitString(rsaPublic),
  ]);
}

// ---------------------------------------------------------------------------
// 私钥的 PEM 编解码（PKCS#1 RSAPrivateKey）
// ---------------------------------------------------------------------------

const String _pemHeader = '-----BEGIN RSA PRIVATE KEY-----';
const String _pemFooter = '-----END RSA PRIVATE KEY-----';

String encodePrivateKeyPem(RsaKeyPair key) {
  final p = key.prime1;
  final q = key.prime2;
  final dp = key.privateExponent % (p - BigInt.one);
  final dq = key.privateExponent % (q - BigInt.one);
  final qInv = q.modInverse(p);
  final der = derSequence(<List<int>>[
    derSmallInt(0),
    derInteger(key.modulus),
    derInteger(key.exponent),
    derInteger(key.privateExponent),
    derInteger(p),
    derInteger(q),
    derInteger(dp),
    derInteger(dq),
    derInteger(qInv),
  ]);
  final b64 = _base64Wrap(der);
  return '$_pemHeader\n$b64\n$_pemFooter';
}

RsaKeyPair decodePrivateKeyPem(String pem) {
  final body = pem
      .split('\n')
      .where((l) => !l.startsWith('-----'))
      .join()
      .trim();
  final der = Uint8List.fromList(base64.decode(body));
  final root = parseDer(der);
  final items = root.children;
  if (items.length < 9) {
    throw const FormatException('私钥格式不被支持（需要 PKCS#1）');
  }
  return RsaKeyPair(
    modulus: items[1].asInteger,
    exponent: items[2].asInteger,
    privateExponent: items[3].asInteger,
    prime1: items[4].asInteger,
    prime2: items[5].asInteger,
  );
}

String encodePublicKeyPem(RsaKeyPair key) {
  final der = rsaPublicKeyInfo(key);
  return '-----BEGIN PUBLIC KEY-----\n${_base64Wrap(der)}\n-----END PUBLIC KEY-----';
}

String _base64Wrap(List<int> data) {
  final b64 = base64.encode(data);
  final out = StringBuffer();
  for (var i = 0; i < b64.length; i += 64) {
    final end = i + 64 > b64.length ? b64.length : i + 64;
    out.writeln(b64.substring(i, end));
  }
  return out.toString().trimRight();
}
