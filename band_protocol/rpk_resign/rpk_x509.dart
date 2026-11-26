/// 自签 X.509 证书（DER）。
///
/// rpk 的签名块里必须带一张证书：手环安装时用它核对「签名私钥」与
/// 「公钥」是否同一对。这里只需要一张自签证书，字段固定、有效期长，
/// 所以直接拼 DER，不引入证书库。
library;

import 'dart:typed_data';

import 'rpk_der.dart';
import 'rpk_rsa.dart';

const String _sha256WithRsa = '1.2.840.113549.1.1.11';

/// 生成自签证书，返回 DER 字节。
///
/// [commonName] 会同时写进 issuer 与 subject；[days] 是有效期。
Uint8List buildSelfSignedCertificate(
  RsaKeyPair key, {
  String commonName = 'YeYu RPK Signer',
  int days = 3650,
}) {
  final serial = _serialFrom(key);
  final name = derSequence(<List<int>>[
    derSet(<List<int>>[
      derSequence(<List<int>>[
        derOid('2.5.4.3'),
        derUtf8String(commonName),
      ]),
    ]),
  ]);
  final algo = derSequence(<List<int>>[
    derOid(_sha256WithRsa),
    derNull(),
  ]);
  final now = DateTime.now().toUtc();
  final tbs = derSequence(<List<int>>[
    derTlv(0xA0, derSmallInt(2)), // version [0] EXPLICIT v3
    derInteger(serial),
    algo,
    name,
    derSequence(<List<int>>[
      derUtcTime(now.subtract(const Duration(days: 1))),
      derUtcTime(now.add(Duration(days: days))),
    ]),
    name,
    rsaPublicKeyInfo(key),
  ]);
  final signature = rsaSignSha256(key, tbs);
  return derSequence(<List<int>>[tbs, algo, derBitString(signature)]);
}

BigInt _serialFrom(RsaKeyPair key) {
  // 用公钥模数的高位截一段当序列号：稳定、不重复、正数。
  final raw = key.modulus >> (key.modulus.bitLength - 64);
  return raw.abs();
}
