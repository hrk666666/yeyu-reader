// 临时校验脚本：用真实 rpk 跑一遍改包名重签，产物交给外部验签。
// 用法: dart run tool/rpk_repack_check.dart <输入.rpk> <输出.rpk> [新包名]
import 'dart:io';

import 'package:fqapp/services/band_rpk/rpk_repack.dart';
import 'package:fqapp/services/band_rpk/rpk_rsa.dart';
import 'package:fqapp/services/band_rpk/rpk_x509.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('用法: dart run tool/rpk_repack_check.dart <in.rpk> <out.rpk> [package]');
    exit(2);
  }
  final source = File(args[0]).readAsBytesSync();
  final newPackage = args.length > 2 ? args[2] : 'com.yeyu.reader.seed';

  final sw = Stopwatch()..start();
  final key = generateRsaKey();
  final keyMs = sw.elapsedMilliseconds;
  final cert = buildSelfSignedCertificate(key);
  final certMs = sw.elapsedMilliseconds - keyMs;
  sw.reset();
  final result = repackRpk(
    source: source,
    key: key,
    certificate: cert,
    newPackage: newPackage,
  );
  final packMs = sw.elapsedMilliseconds;
  File(args[1]).writeAsBytesSync(result.bytes);
  stdout.writeln('密钥生成 ${keyMs}ms，证书 ${certMs}ms，重打包 ${packMs}ms');
  stdout.writeln('${result.oldPackage} -> ${result.newPackage}，${result.fileCount} 个文件，'
      '${source.length} -> ${result.bytes.length} 字节');
  File('${args[1]}.pem').writeAsStringSync(encodePrivateKeyPem(key));
}
