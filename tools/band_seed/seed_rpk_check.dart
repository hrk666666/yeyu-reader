// 命令行校验：用真实 rpk + 真实书数据跑一遍「注入 → 重打包 → 重签」，
// 产物交给外部验签器核对（与 PC 端 seed_rpk.sh 的产物同一套规则）。
//
// 用法:
//   dart run tools/band_seed/seed_rpk_check.dart <in.rpk> <out.rpk> <books.json> [package]
//
// books.json 形如 [{"title":"书名","author":"作者","chapters":[{"title":"第一章","text":"正文"}]}]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fqapp/services/band_rpk/rpk_repack.dart';
import 'package:fqapp/services/band_rpk/rpk_rsa.dart';
import 'package:fqapp/services/band_rpk/rpk_sign.dart';
import 'package:fqapp/services/band_rpk/rpk_x509.dart';
import 'package:fqapp/services/band_rpk/rpk_zip.dart';
import 'package:fqapp/services/band_seed/seed_books.dart';
import 'package:fqapp/services/band_seed/seed_injector.dart';
import 'package:fqapp/services/band_seed/seed_payload.dart';

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('用法: dart run tools/band_seed/seed_rpk_check.dart '
        '<in.rpk> <out.rpk> <books.json> [package]');
    exit(2);
  }
  final source = File(args[0]).readAsBytesSync();
  final rawBooks = (jsonDecode(File(args[2]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final books = <SeedSourceBook>[
    for (final raw in rawBooks)
      SeedSourceBook(
        title: raw['title'] as String,
        author: (raw['author'] ?? '') as String,
        chapters: <SeedSourceChapter>[
          for (final chapter in (raw['chapters'] as List).cast<Map<String, dynamic>>())
            SeedSourceChapter(
              title: chapter['title'] as String,
              text: chapter['text'] as String,
            ),
        ],
      ),
  ];

  final names = rpkEntryNames(source);
  final kind = detectEntryKind(names);
  stdout.writeln('包内文件 ${names.length} 个，入口类型 ${kind.name}');
  if (kind != SeedEntryKind.plainJs) {
    stderr.writeln('这个包没有明文 app.js，塞不了书');
    exit(1);
  }

  final sw = Stopwatch()..start();
  final files = buildSeedFiles(books);
  final payload = buildSeedPayload(files);
  final seedMs = sw.elapsedMilliseconds;
  final chars = seedCharCount(files);
  sw.reset();

  final zip = RpkZip.parse(stripSignBlock(source));
  final injected = injectSeed(zip.readByName('app.js')!, payload);
  final injectMs = sw.elapsedMilliseconds;
  sw.reset();

  final key = generateRsaKey();
  final cert = buildSelfSignedCertificate(key);
  final result = repackRpk(
    source: source,
    key: key,
    certificate: cert,
    newPackage: args.length > 3 ? args[3] : null,
    replace: <String, Uint8List>{'app.js': injected},
  );
  final packMs = sw.elapsedMilliseconds;
  File(args[1]).writeAsBytesSync(result.bytes);

  final outNames = rpkEntryNames(result.bytes);
  final outApp = utf8.decode(
    RpkZip.parse(stripSignBlock(result.bytes)).readByName('app.js')!,
  );
  final pageJs = outNames.where((n) => n.endsWith('.jsc')).length;

  stdout.writeln('书 ${books.length} 本 / ${files.length} 个文件 / $chars 字符'
      '（payload ${(payload.length / 1024).toStringAsFixed(1)} KB）');
  stdout.writeln('生成 ${seedMs}ms，注入 ${injectMs}ms，重打包重签 ${packMs}ms');
  stdout.writeln('${result.oldPackage} -> ${result.newPackage}');
  stdout.writeln('体积 ${source.length} -> ${result.bytes.length} 字节');
  stdout.writeln('自检: 注入标记 ${outApp.contains(kSeedPayloadMarker)}, '
      '页面 jsc $pageJs 个, 无 app.jsc ${!outNames.contains('app.jsc')}, '
      '验签 ${verifySignedRpk(result.bytes)}');
  File('${args[1]}.pem').writeAsStringSync(encodePrivateKeyPem(key));
}
