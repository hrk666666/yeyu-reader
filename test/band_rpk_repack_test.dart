import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/band_rpk/rpk_repack.dart';
import 'package:fqapp/services/band_rpk/rpk_rsa.dart';
import 'package:fqapp/services/band_rpk/rpk_sign.dart';
import 'package:fqapp/services/band_rpk/rpk_x509.dart';
import 'package:fqapp/services/band_rpk/rpk_zip.dart';

void main() {
  late RsaKeyPair key;
  late Uint8List certificate;

  setUpAll(() {
    key = generateRsaKey(bits: 1024);
    certificate = buildSelfSignedCertificate(key);
  });

  group('包名规则', () {
    test('接受常见的多段包名', () {
      expect(validatePackageName('com.yeyu.reader.seed'), isNull);
      expect(validatePackageName('com.a.b1'), isNull);
    });

    test('拒绝空、单段、非法字符、连续点', () {
      expect(validatePackageName(''), isNotNull);
      expect(validatePackageName('reader'), isNotNull);
      expect(validatePackageName('com..reader'), isNotNull);
      expect(validatePackageName('com.1reader'), isNotNull);
      expect(validatePackageName('com.yeyu-reader'), isNotNull);
      expect(validatePackageName('com.yeyu.读者'), isNotNull);
    });
  });

  group('改包名重签', () {
    test('manifest 换包名，其余文件原样，签名自检通过', () {
      final source = _makePackage('com.yeyu.reader', 'V1.0.0');
      final result = repackRpk(
        source: source,
        key: key,
        certificate: certificate,
        newPackage: 'com.yeyu.reader.seed',
      );

      final zip = RpkZip.parse(stripSignBlock(result.bytes));
      final manifest = utf8.decode(zip.readByName('manifest.json')!);
      expect(manifest, contains('"package": "com.yeyu.reader.seed"'));
      // 其它字段不能被重写
      expect(manifest, contains('"name": "页屿"'));
      expect(zip.readByName('app.jsc'), _appBytes);
      expect(result.oldPackage, 'com.yeyu.reader');
      expect(result.newPackage, 'com.yeyu.reader.seed');
      expect(verifySignedRpk(result.bytes), isTrue);
    });

    test('对已签名的包再改一次不会叠加签名块', () {
      final source = _makePackage('com.yeyu.reader', 'V1.0.0');
      final first = repackRpk(
        source: source,
        key: key,
        certificate: certificate,
        newPackage: 'com.yeyu.seed.one',
      );
      final second = repackRpk(
        source: first.bytes,
        key: key,
        certificate: certificate,
        newPackage: 'com.yeyu.seed.two',
      );
      // 包名等长，体积只应因压缩差异浮动，绝不能多出一个签名块（>6 KB）
      expect((second.bytes.length - first.bytes.length).abs(), lessThan(512));
      expect(verifySignedRpk(second.bytes), isTrue);
      final zip = RpkZip.parse(stripSignBlock(second.bytes));
      expect(utf8.decode(zip.readByName('manifest.json')!), contains('com.yeyu.seed.two'));
    });

    test('不带 manifest 的包直接报错', () {
      final bogus = buildZip(<RpkBuildEntry>[
        RpkBuildEntry(
          name: 'readme.txt',
          method: 8,
          mtime: 0,
          mdate: 0,
          eattr: 0,
          verMade: 20,
          verNeed: 20,
          data: Uint8List.fromList(utf8.encode('not a package')),
        ),
      ]);
      expect(
        () => repackRpk(
          source: bogus,
          key: key,
          certificate: certificate,
          newPackage: 'com.yeyu.reader.seed',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('包名不合法时由界面层拦下（validatePackageName）', () {
      expect(validatePackageName('bad'), isNotNull);
    });
  });
}

final Uint8List _appBytes = Uint8List.fromList(
  utf8.encode('export default function () { return 1; }' * 40),
);

Uint8List _makePackage(String package, String version) {
  final manifest = utf8.encode('{\n'
      '  "package": "$package",\n'
      '  "name": "页屿",\n'
      '  "versionName": "$version",\n'
      '  "versionCode": 1,\n'
      '  "router": {"entry": "pages/index", "pages": {"pages/index": {}}}\n'
      '}\n');
  return buildZip(<RpkBuildEntry>[
    RpkBuildEntry(
      name: 'META-INF/',
      method: 0,
      mtime: 0,
      mdate: 0,
      eattr: 0,
      verMade: 20,
      verNeed: 20,
      data: Uint8List(0),
    ),
    RpkBuildEntry(
      name: 'manifest.json',
      method: 8,
      mtime: 0,
      mdate: 0,
      eattr: 0,
      verMade: 20,
      verNeed: 20,
      data: Uint8List.fromList(manifest),
    ),
    RpkBuildEntry(
      name: 'app.jsc',
      method: 8,
      mtime: 0,
      mdate: 0,
      eattr: 0,
      verMade: 20,
      verNeed: 20,
      data: _appBytes,
    ),
  ]);
}
