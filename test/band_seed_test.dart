import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/band_rpk/rpk_repack.dart';
import 'package:fqapp/services/band_rpk/rpk_rsa.dart';
import 'package:fqapp/services/band_rpk/rpk_sign.dart';
import 'package:fqapp/services/band_rpk/rpk_x509.dart';
import 'package:fqapp/services/band_rpk/rpk_zip.dart';
import 'package:fqapp/services/band_seed/seed_books.dart';
import 'package:fqapp/services/band_seed/seed_injector.dart';
import 'package:fqapp/services/band_seed/seed_payload.dart';

void main() {
  group('书目录结构', () {
    test('书架版本号是 3，字段与手环端一致', () {
      final files = buildSeedFiles(<SeedSourceBook>[
        SeedSourceBook(
          title: '测试书',
          author: '某人',
          chapters: const <SeedSourceChapter>[
            SeedSourceChapter(title: '第一章', text: '正文一'),
            SeedSourceChapter(title: '第二章', text: '正文二'),
          ],
        ),
      ], now: DateTime.fromMillisecondsSinceEpoch(1795359807193));

      final shelf = jsonDecode(files['books/bookshelf.json']!) as Map<String, dynamic>;
      expect(shelf['version'], 3);
      final books = shelf['books'] as List;
      expect(books, hasLength(1));
      final book = books.single as Map<String, dynamic>;
      expect(book['name'], '测试书');
      expect(book['chapterCount'], 2);
      expect(book['dirName'], hasLength(8));
      expect((book['progress'] as Map)['lastReadTimestamp'], 1795359807193);
    });

    test('lindex 两行头 + 每个分片一行范围', () {
      final files = buildSeedFiles(<SeedSourceBook>[
        SeedSourceBook(
          title: '一百二十章',
          author: '',
          chapters: <SeedSourceChapter>[
            for (var i = 0; i < 120; i++)
              SeedSourceChapter(title: '第$i章', text: 'x' * 10),
          ],
        ),
      ]);
      final dir = _dirOf(files);
      final lines = files['books/$dir/lindex.txt']!.split('\n');
      expect(lines[0], '120');
      // 内置书是整本写入，已同步数等于总章数
      expect(lines[1], '120');
      expect(lines[2], '0,99');
      expect(lines[3], '100,119');
    });

    test('索引按 100 章一片，行是「序号 \\t 标题 \\t 字数」', () {
      final files = buildSeedFiles(<SeedSourceBook>[
        SeedSourceBook(
          title: '分片',
          author: '',
          chapters: <SeedSourceChapter>[
            for (var i = 0; i < 120; i++)
              SeedSourceChapter(title: '第$i章', text: '一二三'),
          ],
        ),
      ]);
      final dir = _dirOf(files);
      expect(files.keys.where((k) => k.contains('/indexes/')), hasLength(2));
      final first = files['books/$dir/indexes/1.txt']!.split('\n');
      expect(first.where((l) => l.isNotEmpty), hasLength(100));
      expect(first.first, '0\t第0章\t3');
      final second = files['books/$dir/indexes/2.txt']!.split('\n');
      expect(second.where((l) => l.isNotEmpty), hasLength(20));
    });

    test('每章一个 content 文件，正文原样', () {
      final files = buildSeedFiles(<SeedSourceBook>[
        SeedSourceBook(
          title: '两章',
          author: '',
          chapters: const <SeedSourceChapter>[
            SeedSourceChapter(title: '一', text: '甲\n乙'),
            SeedSourceChapter(title: '二', text: '丙'),
          ],
        ),
      ]);
      final dir = _dirOf(files);
      expect(files['books/$dir/content/0.txt'], '甲\n乙');
      expect(files['books/$dir/content/1.txt'], '丙');
    });

    test('没选书 / 空章节直接报错', () {
      expect(() => buildSeedFiles(const <SeedSourceBook>[]), throwsFormatException);
      expect(
        () => buildSeedFiles(const <SeedSourceBook>[
          SeedSourceBook(title: '空', author: '', chapters: <SeedSourceChapter>[]),
        ]),
        throwsFormatException,
      );
    });
  });

  group('内置书入口', () {
    Map<String, String> oneBook() => buildSeedFiles(<SeedSourceBook>[
          SeedSourceBook(
            title: '书',
            author: '',
            chapters: const <SeedSourceChapter>[
              SeedSourceChapter(title: '一', text: '正文'),
            ],
          ),
        ]);

    test('是一份完整入口：导出函数 + manifest + 生命周期', () {
      final shell = buildShellAppJs(
        manifest: const <String, dynamic>{'package': 'com.yeyu.reader', 'name': '页屿'},
        files: oneBook(),
      );
      expect(shell, contains('export default function'));
      expect(shell, contains(r'$app_exports$.default.manifest = MANIFEST'));
      expect(shell, contains(r'$app_exports$.default.onShow'));
      expect(shell, contains(kSeedPayloadMarker));
      // manifest 原样内联，包名等信息不丢
      expect(shell, contains('com.yeyu.reader'));
      expect(shell, contains('页屿'));
    });

    test('SEED 是可解析的 JSON，键是 books/ 相对路径', () {
      final shell = buildShellAppJs(
        manifest: const <String, dynamic>{'package': 'p.q'},
        files: oneBook(),
      );
      final match =
          RegExp(r'var SEED = (\{.*\});\n  var MARK', dotAll: true).firstMatch(shell)!;
      final parsed = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      expect(parsed.keys, contains('books/bookshelf.json'));
      expect(parsed.values.every((v) => v is String), isTrue);
    });

    test('正文里的 U+2028 被转义，不会把 JS 字符串截断', () {
      final shell = buildShellAppJs(
        manifest: const <String, dynamic>{'package': 'p.q'},
        files: <String, String>{'books/x.txt': '前\u2028后'},
      );
      expect(shell.contains('\u2028'), isFalse);
      expect(shell, contains(r'\u2028'));
    });

    test('没有书直接报错', () {
      expect(
        () => buildShellAppJs(
          manifest: const <String, dynamic>{'package': 'p.q'},
          files: const <String, String>{},
        ),
        throwsFormatException,
      );
    });
  });

  group('入口类型判断', () {
    test('按文件清单判断', () {
      expect(
        detectEntryKind(<String>['app.js', 'pages/index/index.jsc']),
        SeedEntryKind.plainJs,
      );
      expect(detectEntryKind(<String>['app.jsc']), SeedEntryKind.bytecode);
      expect(detectEntryKind(<String>['manifest.json']), SeedEntryKind.unknown);
    });
  });

  group('出包', () {
    late RsaKeyPair key;
    late Uint8List certificate;

    setUpAll(() {
      key = generateRsaKey(bits: 1024);
      certificate = buildSelfSignedCertificate(key);
    });

    test('纯 jsc 包：删入口、写壳、页面不动、签名自检通过', () {
      final books = <SeedSourceBook>[
        SeedSourceBook(
          title: '内置书',
          author: '某人',
          chapters: const <SeedSourceChapter>[
            SeedSourceChapter(title: '第一章', text: '正文'),
          ],
        ),
      ];
      final shell = buildShellAppJs(
        manifest: const <String, dynamic>{'package': 'com.yeyu.reader'},
        files: buildSeedFiles(books),
      );
      final result = repackRpk(
        source: _makeBytecodePackage('com.yeyu.reader'),
        key: key,
        certificate: certificate,
        newPackage: 'com.yeyu.reader.seed',
        write: <String, Uint8List>{'app.js': Uint8List.fromList(utf8.encode(shell))},
        drop: <String>{'app.jsc'},
      );

      expect(verifySignedRpk(result.bytes), isTrue);
      final zip = RpkZip.parse(stripSignBlock(result.bytes));
      final names = <String>[
        for (final e in zip.entries)
          if (!e.isDirectory) e.name,
      ];
      expect(names, isNot(contains('app.jsc')));
      expect(names, contains('app.js'));
      final appJs = utf8.decode(zip.readByName('app.js')!);
      expect(appJs, contains(kSeedPayloadMarker));
      expect(appJs, contains('books/bookshelf.json'));
      expect(utf8.decode(zip.readByName('pages/index/index.jsc')!), _pageJs);
      expect(
        utf8.decode(zip.readByName('manifest.json')!),
        contains('"package": "com.yeyu.reader.seed"'),
      );
    });

    test('hash.json 不留下已删文件的条目', () {
      final first = repackRpk(
        source: _makeBytecodePackage('com.yeyu.reader'),
        key: key,
        certificate: certificate,
      );
      final result = repackRpk(
        source: first.bytes,
        key: key,
        certificate: certificate,
        write: <String, Uint8List>{
          'app.js': Uint8List.fromList(utf8.encode('export default function(){}')),
        },
        drop: <String>{'app.jsc'},
      );
      final zip = RpkZip.parse(stripSignBlock(result.bytes));
      final inner = RpkZip.parse(stripSignBlock(zip.readByName('META-INF/CERT')!));
      final hashJson =
          jsonDecode(utf8.decode(inner.readByName('hash.json')!)) as Map<String, dynamic>;
      final digests = hashJson['digests'] as Map<String, dynamic>;
      expect(digests.keys, isNot(contains('app.jsc')));
      expect(digests.keys, contains('app.js'));
    });

    test('删不存在的文件直接报错', () {
      expect(
        () => repackRpk(
          source: _makeBytecodePackage('com.yeyu.reader'),
          key: key,
          certificate: certificate,
          drop: <String>{'app.typo.jsc'},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('同一个文件既删又写直接报错', () {
      expect(
        () => repackRpk(
          source: _makeBytecodePackage('com.yeyu.reader'),
          key: key,
          certificate: certificate,
          drop: <String>{'app.jsc'},
          write: <String, Uint8List>{'app.jsc': Uint8List.fromList(utf8.encode('x'))},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('replace 拼错文件名仍然报错', () {
      expect(
        () => repackRpk(
          source: _makeBytecodePackage('com.yeyu.reader'),
          key: key,
          certificate: certificate,
          replace: <String, Uint8List>{'app.typo.js': Uint8List.fromList(utf8.encode('x'))},
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

String _dirOf(Map<String, String> files) {
  final key = files.keys.firstWhere(
    (k) => k.endsWith('/lindex.txt'),
  );
  return key.split('/')[1];
}

const String _pageJs = 'this is compiled bytecode stand-in';
const String _appJsc = 'compiled entry bytecode stand-in';

/// 正式发布包的形态：只有 app.jsc，没有 app.js。
Uint8List _makeBytecodePackage(String package) {
  final manifest = utf8.encode('{\n'
      '  "package": "$package",\n'
      '  "name": "页屿",\n'
      '  "versionName": "V1.0.0",\n'
      '  "versionCode": 1,\n'
      '  "router": {"entry": "pages/index", "pages": {"pages/index": {}}}\n'
      '}\n');
  return buildZip(<RpkBuildEntry>[
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
      data: Uint8List.fromList(utf8.encode(_appJsc)),
    ),
    RpkBuildEntry(
      name: 'pages/index/index.jsc',
      method: 8,
      mtime: 0,
      mdate: 0,
      eattr: 0,
      verMade: 20,
      verNeed: 20,
      data: Uint8List.fromList(utf8.encode(_pageJs)),
    ),
  ]);
}
