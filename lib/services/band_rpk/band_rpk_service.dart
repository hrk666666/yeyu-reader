/// 手环安装包（rpk）的导入、改包名重签、另存与分享。
///
/// 现场：官方 rpk 与「内置书」版本的包名相同，装一个就会顶掉另一个。
/// 把包名改掉再重签，两个包就能共存；签名用本机生成的密钥，不碰官方私钥。
library;

import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../book_txt_export.dart' show ExportTarget, ExportWriteException;
import '../platform_channel.dart';
import '../band_seed/seed_books.dart';
import '../band_seed/seed_injector.dart';
import '../band_seed/seed_payload.dart';
import 'rpk_key_store.dart';
import 'rpk_repack.dart';
import 'rpk_rsa.dart';
import 'rpk_sign.dart';
import 'rpk_zip.dart';

/// 选中的 rpk 文件。
class RpkSource {
  const RpkSource({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// 生成好、等待落盘或分享的包。
class RpkArtifact {
  const RpkArtifact({
    required this.fileName,
    required this.bytes,
    required this.oldPackage,
    required this.newPackage,
    required this.fileCount,
    required this.renamed,
  });

  final String fileName;
  final Uint8List bytes;
  final String oldPackage;
  final String newPackage;
  final int fileCount;

  /// 是否真的改了包名（关掉开关时只是原样重签或直接复制）。
  final bool renamed;

  int get sizeBytes => bytes.length;
}

class BandRpkService {
  BandRpkService({RpkKeyStore? keys}) : _keys = keys ?? RpkKeyStore();

  static final BandRpkService shared = BandRpkService();

  final RpkKeyStore _keys;
  static const AppMethodChannel _downloads = AppMethodChannel('fqapp/downloads');
  static const AppMethodChannel _share = AppMethodChannel('fqapp/share');

  /// 让用户挑一个 rpk。返回 null 表示取消。
  Future<RpkSource?> pick() async {
    const group = XTypeGroup(label: '手环安装包', extensions: <String>['rpk', 'zip']);
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('这个文件是空的');
    }
    return RpkSource(name: file.name, bytes: bytes);
  }

  /// 读 manifest，判断是不是手环包。
  RpkManifest inspect(RpkSource source) => readManifest(source.bytes);

  /// 生成新包。[newPackage] 为 null 或空串时保持原包名。
  ///
  /// 重签名放在 isolate 里跑：650 KB 的包要解压全部条目再压两遍，
  /// 主线程会掉帧。
  Future<RpkArtifact> build({
    required RpkSource source,
    String? newPackage,
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('准备签名密钥');
    final identity = await _keys.ensureIdentity();
    onStage?.call('重新打包并签名');
    final manifest = inspect(source);
    final target = (newPackage == null || newPackage.isEmpty)
        ? null
        : newPackage;
    final result = await compute(_repackInIsolate, <String, Object?>{
      'bytes': source.bytes,
      'pem': identity.privateKeyPem,
      'cert': identity.certificate,
      'package': target,
    });
    final package = result['package'] as String;
    return RpkArtifact(
      fileName: _fileNameFor(manifest.name, package),
      bytes: result['bytes'] as Uint8List,
      oldPackage: result['oldPackage'] as String,
      newPackage: package,
      fileCount: result['fileCount'] as int,
      renamed: package != manifest.package,
    );
  }

  /// 往包里塞书：删掉原入口、写一份带书数据的手写入口 → 重打包 → 重签。
  ///
  /// 任何手环包都能塞，包括纯 jsc 的正式发布包：入口是整体替换，不是文本注入，
  /// 页面字节码一个字节都不动。
  Future<RpkArtifact> buildSeeded({
    required RpkSource source,
    required List<SeedSourceBook> books,
    String? newPackage,
    void Function(String stage)? onStage,
  }) async {
    final manifest = inspect(source);
    final kind = detectEntryKind(rpkEntryNames(source.bytes));
    if (kind == SeedEntryKind.unknown) {
      throw const SeedInjectException(
        SeedInjectError.unsupportedPackage,
        '这个包里既没有 app.js 也没有 app.jsc，不像是手环快应用包。',
      );
    }
    onStage?.call('准备签名密钥');
    final identity = await _keys.ensureIdentity();
    onStage?.call('生成入口并重签');
    final target = (newPackage == null || newPackage.isEmpty) ? null : newPackage;
    final result = await compute(_seedInIsolate, <String, Object?>{
      'bytes': source.bytes,
      'pem': identity.privateKeyPem,
      'cert': identity.certificate,
      'package': target,
      'books': <Object?>[
        for (final book in books)
          <String, Object?>{
            'title': book.title,
            'author': book.author,
            'chapters': <Object?>[
              for (final chapter in book.chapters)
                <String, Object?>{'title': chapter.title, 'text': chapter.text},
            ],
          },
      ],
    });
    final package = result['package'] as String;
    final count = result['bookCount'] as int;
    return RpkArtifact(
      fileName: _seedFileNameFor(manifest.name, package, count),
      bytes: result['bytes'] as Uint8List,
      oldPackage: result['oldPackage'] as String,
      newPackage: package,
      fileCount: result['fileCount'] as int,
      renamed: package != manifest.package,
    );
  }

  /// 把原包原样交出去（不改包名、不重签）。
  RpkArtifact passthrough(RpkSource source) {
    final manifest = inspect(source);
    return RpkArtifact(
      fileName: _fileNameFor(manifest.name, manifest.package),
      bytes: source.bytes,
      oldPackage: manifest.package,
      newPackage: manifest.package,
      fileCount: 0,
      renamed: false,
    );
  }

  /// 另存到系统「下载」目录。
  Future<ExportTarget> saveToDownloads(RpkArtifact artifact) async {
    final Map<String, Object?>? result;
    try {
      result = await _downloads.invokeMapMethod<String, Object?>('saveBytes', {
        'fileName': artifact.fileName,
        'bytes': artifact.bytes,
        'mime': 'application/octet-stream',
      });
    } on PlatformException catch (error) {
      throw ExportWriteException(error.message ?? '写入失败');
    } on MissingPluginException {
      throw const ExportWriteException('当前平台不支持导出到下载目录');
    }
    final path = result?['path'];
    if (path is! String || path.isEmpty) {
      throw const ExportWriteException('系统未返回保存路径');
    }
    return ExportTarget(path: path, isPublic: result?['public'] == true);
  }

  /// 调系统分享面板把文件发出去。返回 false 表示没有应用能接。
  Future<bool> shareFile(RpkArtifact artifact) async {
    try {
      final ok = await _share.invokeMethod<bool>('shareFile', {
        'fileName': artifact.fileName,
        'bytes': artifact.bytes,
        'mime': 'application/octet-stream',
        'title': artifact.fileName,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static String _fileNameFor(String appName, String package) {
    final safeApp = appName.isEmpty ? 'rpk' : appName;
    return '$safeApp-$package.rpk';
  }

  /// 内置书包的文件名带本数，下载目录里一眼能分清是哪个包。
  static String _seedFileNameFor(String appName, String package, int books) {
    final safeApp = appName.isEmpty ? 'rpk' : appName;
    return '$safeApp-内置$books本-$package.rpk';
  }
}

/// isolate 入口：参数与返回值都必须是可跨 isolate 传输的类型。
Map<String, Object?> _repackInIsolate(Map<String, Object?> args) {
  final key = decodePrivateKeyPem(args['pem'] as String);
  final result = repackRpk(
    source: args['bytes'] as Uint8List,
    key: key,
    certificate: args['cert'] as Uint8List,
    newPackage: args['package'] as String?,
  );
  return <String, Object?>{
    'bytes': result.bytes,
    'oldPackage': result.oldPackage,
    'package': result.newPackage,
    'fileCount': result.fileCount,
  };
}

/// isolate 入口：生成书数据 → 注入 app.js → 重打包重签。
Map<String, Object?> _seedInIsolate(Map<String, Object?> args) {
  final key = decodePrivateKeyPem(args['pem'] as String);
  final rawBooks = (args['books'] as List).cast<Map<Object?, Object?>>();
  final books = <SeedSourceBook>[
    for (final raw in rawBooks)
      SeedSourceBook(
        title: raw['title'] as String,
        author: raw['author'] as String,
        chapters: <SeedSourceChapter>[
          for (final chapter in (raw['chapters'] as List).cast<Map<Object?, Object?>>())
            SeedSourceChapter(
              title: chapter['title'] as String,
              text: chapter['text'] as String,
            ),
        ],
      ),
  ];
  final files = buildSeedFiles(books);

  final source = args['bytes'] as Uint8List;
  final zip = RpkZip.parse(stripSignBlock(source));
  final manifestBytes = zip.readByName('manifest.json');
  if (manifestBytes == null) {
    throw const SeedInjectException(
      SeedInjectError.unsupportedPackage,
      '这个包里没有 manifest.json，不像是手环快应用包',
    );
  }
  final manifest =
      json.decode(utf8.decode(manifestBytes, allowMalformed: true)) as Map<String, dynamic>;

  // 壳里内联的那份 manifest 必须用目标包名，否则改包名后应用自报的身份
  // 与安装包对不上（存储隔离、台标都会按它走）。
  final target = (args['package'] as String?)?.trim();
  if (target != null && target.isNotEmpty) {
    manifest['package'] = target;
  }
  final shell = buildShellAppJs(manifest: manifest, files: files);

  // 入口只留一份：原包不管是 app.js 还是 app.jsc 都删掉，换成手写壳。
  // 两份并存时运行时用哪一份没有保证，删干净才确定。
  final drop = <String>{
    for (final name in const <String>['app.js', 'app.jsc'])
      if (zip.readByName(name) != null) name,
  };
  final result = repackRpk(
    source: source,
    key: key,
    certificate: args['cert'] as Uint8List,
    newPackage: args['package'] as String?,
    write: <String, Uint8List>{
      'app.js': Uint8List.fromList(utf8.encode(shell)),
    },
    drop: drop,
  );
  return <String, Object?>{
    'bytes': result.bytes,
    'oldPackage': result.oldPackage,
    'package': result.newPackage,
    'fileCount': result.fileCount,
    'bookCount': books.length,
    'shellBytes': shell.length,
    'dropped': drop.join(','),
  };
}

