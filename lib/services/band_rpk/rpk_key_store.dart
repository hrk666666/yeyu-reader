/// rpk 签名密钥的本地存放。
///
/// 「改包名共存」的包不该再用官方那套私钥：每个用户一套、只存在本机，
/// 才算真正与官方隔离。密钥与自签证书都放 Secure Storage（Android 走
/// Keystore 加密），首次使用时生成一次，之后一直复用 —— 重装 App 后
/// 旧包会因签名不同而无法覆盖，所以这里也提供导出/导入的能力。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'rpk_rsa.dart';
import 'rpk_x509.dart';

class RpkSigningIdentity {
  const RpkSigningIdentity({
    required this.privateKeyPem,
    required this.certificate,
  });

  final String privateKeyPem;

  /// 自签证书 DER。
  final Uint8List certificate;

  RsaKeyPair get keyPair => decodePrivateKeyPem(privateKeyPem);

  String get certificateBase64 => base64.encode(certificate);

  String get publicKeyPem => encodePublicKeyPem(keyPair);
}

class RpkKeyStore {
  RpkKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _keyPrivate = 'band_rpk_private_key_v1';
  static const String _keyCert = 'band_rpk_certificate_v1';

  final FlutterSecureStorage _storage;

  /// 读取本机密钥，没有就生成一套（约几十毫秒到几秒，视设备而定）。
  Future<RpkSigningIdentity> ensureIdentity() async {
    final pem = await _storage.read(key: _keyPrivate);
    final certB64 = await _storage.read(key: _keyCert);
    if (pem != null && certB64 != null) {
      try {
        return RpkSigningIdentity(
          privateKeyPem: pem,
          certificate: Uint8List.fromList(base64.decode(certB64)),
        );
      } catch (_) {
        // 存储内容坏了就重来一套，不要把用户卡在这里。
      }
    }
    final identity = await generateIdentity();
    await save(identity);
    return identity;
  }

  Future<void> save(RpkSigningIdentity identity) async {
    await _storage.write(key: _keyPrivate, value: identity.privateKeyPem);
    await _storage.write(key: _keyCert, value: identity.certificateBase64);
  }

  /// 生成一套新的自签身份。
  ///
  /// 找两个 1024 位素数在低端机上要几百毫秒到几秒，放 isolate 里跑，
  /// 免得首次打开工具页时界面卡住。
  static Future<RpkSigningIdentity> generateIdentity() async {
    final out = await compute(_generateInIsolate, null);
    return RpkSigningIdentity(
      privateKeyPem: out['pem'] as String,
      certificate: out['cert'] as Uint8List,
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyPrivate);
    await _storage.delete(key: _keyCert);
  }
}

Map<String, Object> _generateInIsolate(void _) {
  final key = generateRsaKey();
  return <String, Object>{
    'pem': encodePrivateKeyPem(key),
    'cert': buildSelfSignedCertificate(key),
  };
}
