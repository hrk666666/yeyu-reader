// 命令行校验：用真实 rpk + 真实书数据跑一遍「生成入口 → 删原入口 → 重打包 → 重签」，
// 产物交给外部验签器核对。任意手环包都能跑，包括纯 jsc 的正式发布包。
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
  if (kind == SeedEntryKind.unknown) {
    stderr.writeln('这个包既没有 app.js 也没有 app.jsc，不像是手环快应用包');
    exit(1);
  }

  final zip = RpkZip.parse(stripSignBlock(source));
  final manifestBytes = zip.readByName('manifest.json');
  if (manifestBytes == null) {
    stderr.writeln('这个包里没有 manifest.json');
    exit(1);
  }
  final manifest =
      jsonDecode(utf8.decode(manifestBytes, allowMalformed: true)) as Map<String, dynamic>;
  final target = args.length > 3 ? args[3] : null;
  if (target != null && target.isNotEmpty) {
    manifest['package'] = target;
  }

  final sw = Stopwatch()..start();
  final files = buildSeedFiles(books);
  final shell = buildShellAppJs(manifest: manifest, files: files);
  final shellMs = sw.elapsedMilliseconds;
  final chars = seedCharCount(files);
  sw.reset();

  final key = generateRsaKey();
  final cert = buildSelfSignedCertificate(key);
  final dropped = <String>{
    for (final name in const <String>['app.js', 'app.jsc'])
      if (zip.readByName(name) != null) name,
  };
  final result = repackRpk(
    source: source,
    key: key,
    certificate: cert,
    newPackage: target,
    write: <String, Uint8List>{'app.js': Uint8List.fromList(utf8.encode(shell))},
    drop: dropped,
  );
  final packMs = sw.elapsedMilliseconds;
  File(args[1]).writeAsBytesSync(result.bytes);

  final outNames = rpkEntryNames(result.bytes);
  final outApp = utf8.decode(
    RpkZip.parse(stripSignBlock(result.bytes)).readByName('app.js')!,
  );
  final pageJs = outNames.where((n) => n.endsWith('.jsc')).length;
  final appJscGone = !outNames.contains('app.jsc');

  stdout.writeln('书 ${books.length} 本 / ${files.length} 个文件 / $chars 字符');
  stdout.writeln('生成入口 ${shellMs}ms（${(shell.length / 1024).toStringAsFixed(1)} KB），'
      '重打包重签 ${packMs}ms');
  stdout.writeln('${result.oldPackage} -> ${result.newPackage}');
  stdout.writeln('体积 ${source.length} -> ${result.bytes.length} 字节');
  stdout.writeln('自检: 入口标记 ${outApp.contains(kSeedPayloadMarker)}, '
      '页面 jsc $pageJs 个, 原入口已删 $appJscGone（删了 ${dropped.join('、')}）, '
      '验签 ${verifySignedRpk(result.bytes)}');
  File('${args[1]}.pem').writeAsStringSync(encodePrivateKeyPem(key));
}
