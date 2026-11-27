/// 重打包：改包名 + 重算摘要 + 重签名。
///
/// 全流程等价于 aiot 工具链的 `createRpk`：先给 hash.json 单独打包并签名
/// （META-INF/CERT），再把所有文件连同这个 CERT 打成外层包并签一次。
/// 改包名只动 manifest.json，其余文件的压缩流原样搬运。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'rpk_rsa.dart';
import 'rpk_sign.dart';
import 'rpk_zip.dart';

/// 从 manifest.json 里读出来的展示信息。
class RpkManifest {
  const RpkManifest({
    required this.package,
    required this.name,
    required this.versionName,
    required this.versionCode,
    required this.entry,
    required this.pageCount,
    required this.raw,
  });

  final String package;
  final String name;
  final String versionName;
  final int versionCode;
  final String entry;
  final int pageCount;
  final Map<String, dynamic> raw;

  static RpkManifest parse(Uint8List manifestBytes) {
    final map = json.decode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    final router = map['router'];
    final pages = router is Map ? router['pages'] : null;
    return RpkManifest(
      package: (map['package'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      versionName: (map['versionName'] ?? '').toString(),
      versionCode: (map['versionCode'] is int) ? map['versionCode'] as int : 0,
      entry: router is Map ? (router['entry'] ?? '').toString() : '',
      pageCount: pages is Map ? pages.length : 0,
      raw: map,
    );
  }
}

/// 重打包结果。
class RpkRepackResult {
  const RpkRepackResult({
    required this.bytes,
    required this.oldPackage,
    required this.newPackage,
    required this.manifest,
    required this.fileCount,
  });

  final Uint8List bytes;
  final String oldPackage;
  final String newPackage;
  final RpkManifest manifest;
  final int fileCount;
}

/// 校验包名：与快应用/Android 的包名规则一致，至少两段。
String? validatePackageName(String name) {
  if (name.isEmpty) return '包名不能为空';
  if (name.length > 120) return '包名过长';
  final re = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$');
  if (!re.hasMatch(name)) {
    return '只能包含字母、数字、下划线，用点分段，且每段以字母开头';
  }
  if (name.split('.').any((s) => s.isEmpty)) return '不能出现连续的点';
  return null;
}

/// 解析 rpk 的 manifest（不重签，只读）。
RpkManifest readManifest(Uint8List bytes) {
  final zip = RpkZip.parse(stripSignBlock(bytes));
  final manifest = zip.readByName('manifest.json');
  if (manifest == null) {
    throw const FormatException('这个包里没有 manifest.json，可能不是手环快应用包');
  }
  return RpkManifest.parse(manifest);
}

/// 改包名并重新签名。
///
/// [newPackage] 为空时保持原包名（只重签，用于换一套密钥的场合）。
/// [replace] 按文件名替换包内内容（内置书就是替换掉 `app.js`），键必须在
/// 包里存在，拼错会直接报错而不是静默忽略。
RpkRepackResult repackRpk({
  required Uint8List source,
  required RsaKeyPair key,
  required Uint8List certificate,
  String? newPackage,
  Map<String, Uint8List>? replace,
  bool selfCheck = true,
}) {
  final clean = stripSignBlock(source);
  final zip = RpkZip.parse(clean);
  final manifestBytes = zip.readByName('manifest.json');
  if (manifestBytes == null) {
    throw const FormatException('这个包里没有 manifest.json，可能不是手环快应用包');
  }
  final manifest = RpkManifest.parse(manifestBytes);
  final targetPackage = (newPackage == null || newPackage.isEmpty)
      ? manifest.package
      : newPackage;
  final overrides = replace ?? const <String, Uint8List>{};
  final present = <String>{
    for (final entry in zip.entries)
      if (!entry.isDirectory) entry.name,
  };
  final missing = overrides.keys.where((name) => !present.contains(name)).toList();
  if (missing.isNotEmpty) {
    throw FormatException('要替换的文件不在包里：${missing.join('、')}');
  }

  // 1. 改包名：只替换第一个 "package" 的值，其余字节保持原样。
  final pattern = RegExp(r'("package"\s*:\s*")([^"]*)(")');
  final match = pattern.firstMatch(utf8.decode(manifestBytes, allowMalformed: true));
  if (match == null) {
    throw const FormatException('manifest.json 里没有 package 字段');
  }
  final text = utf8.decode(manifestBytes, allowMalformed: true);
  final patchedManifest = Uint8List.fromList(utf8.encode(
    text.replaceRange(match.start, match.end, '${match.group(1)}$targetPackage${match.group(3)}'),
  ));

  // 2. 读出所有文件内容（算摘要用），并沿用旧 hash.json 的键集合。
  final contents = <String, Uint8List>{};
  for (final entry in zip.entries) {
    if (entry.isDirectory) continue;
    final override = overrides[entry.name];
    contents[entry.name] = override ??
        (entry.name == 'manifest.json' ? patchedManifest : zip.read(entry));
  }
  final oldHash = _readOldHashJson(zip);
  final hashJson = _buildHashJson(oldHash, contents);

  // 3. hash.json 单独打包并签名 -> 新的 META-INF/CERT
  final first = zip.entries.first;
  final newCert = _buildCert(hashJson, first.mtime, first.mdate, key, certificate);

  // 4. 组装外层包：只有 manifest.json 与 CERT 重新压缩，其余原样搬运。
  final items = <RpkBuildEntry>[];
  var certWritten = false;
  for (final entry in zip.entries) {
    if (entry.isDirectory) {
      items.add(RpkBuildEntry(
        name: entry.name,
        method: 0,
        mtime: entry.mtime,
        mdate: entry.mdate,
        eattr: entry.eattr,
        verMade: entry.verMade,
        verNeed: entry.verNeed,
        data: Uint8List(0),
      ));
      continue;
    }
    if (entry.name == 'META-INF/CERT') {
      items.add(_rebuildFromData(entry, newCert));
      certWritten = true;
    } else if (entry.name == 'manifest.json') {
      items.add(_rebuildFromData(entry, patchedManifest));
    } else if (overrides.containsKey(entry.name) || (entry.flag & 0x08 != 0)) {
      // 替换过的条目必须重新压缩；带 data descriptor 的条目也没法整段搬运。
      items.add(_rebuildFromData(entry, contents[entry.name]!));
    } else {
      items.add(RpkBuildEntry(
        name: entry.name,
        method: entry.method,
        mtime: entry.mtime,
        mdate: entry.mdate,
        eattr: entry.eattr,
        verMade: entry.verMade,
        verNeed: entry.verNeed,
        raw: zip.rawCompressed(entry),
        rawHeader: zip.rawLocalHeader(entry),
        crc: entry.crc,
        csize: entry.csize,
        usize: entry.usize,
        flag: entry.flag,
        extra: entry.extra,
      ));
    }
  }
  if (!certWritten) {
    // 输入本身就是未签名的包（例如自己构建出来的），补上 CERT，
    // 否则产物会因为缺签名文件而装不上。
    items.add(RpkBuildEntry(
      name: 'META-INF/CERT',
      method: 8,
      mtime: first.mtime,
      mdate: first.mdate,
      eattr: 0,
      verMade: first.verMade,
      verNeed: first.verNeed,
      data: newCert,
    ));
  }
  final packaged = buildZip(items, comment: zip.comment);

  // 5. 外层签名：CERT 排第一，其余按包内顺序。
  final names = <String>[
    'META-INF/CERT',
    ...contents.keys.where((n) => n != 'META-INF/CERT'),
  ];
  final digests = <RpkFileDigest>[
    for (final name in names)
      RpkFileDigest(name, _sha256(name == 'META-INF/CERT' ? newCert : contents[name]!)),
  ];
  final signed = signZip(packaged, digests, key, certificate);
  // 生成的包必须能被同一套规则验回来：手环不会给第二次机会。
  if (selfCheck && !verifySignedRpk(signed)) {
    throw StateError('签名自检未通过，已中止（不会产出装不上的包）');
  }

  return RpkRepackResult(
    bytes: signed,
    oldPackage: manifest.package,
    newPackage: targetPackage,
    manifest: manifest,
    fileCount: contents.length,
  );
}

RpkBuildEntry _rebuildFromData(RpkEntry entry, Uint8List data) {
  return RpkBuildEntry(
    name: entry.name,
    method: entry.method,
    mtime: entry.mtime,
    mdate: entry.mdate,
    eattr: entry.eattr,
    verMade: entry.verMade,
    verNeed: entry.verNeed,
    data: data,
  );
}

Map<String, dynamic>? _readOldHashJson(RpkZip zip) {
  final cert = zip.readByName('META-INF/CERT');
  if (cert == null) return null;
  try {
    final inner = RpkZip.parse(stripSignBlock(cert));
    final bytes = inner.readByName('hash.json');
    if (bytes == null) return null;
    return json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// 生成 hash.json。
///
/// 官方打 jsc 包时会把编译前的 `.js` 路径写进 hash.json，这些键在包里
/// 找不到对应文件；沿用旧键并保留它们的旧值，能让产物与官方包保持同样的
/// 形态，也避免动到无关条目。
Uint8List _buildHashJson(Map<String, dynamic>? old, Map<String, Uint8List> contents) {
  final digests = <String, String>{};
  final oldDigests = old?['digests'];
  if (oldDigests is Map) {
    // 沿用原键集合：官方打 jsc 包时写的是编译前的 .js 路径，这些键在包里
    // 找不到对应文件；补齐它们会让 hash.json 与官方包长出 40 多行差异，
    // 而手环并不需要这些条目。
    for (final entry in oldDigests.entries) {
      final name = entry.key.toString();
      final content = contents[name];
      digests[name] = content != null
          ? crypto.sha256.convert(content).toString()
          : entry.value.toString();
    }
  } else {
    for (final entry in contents.entries) {
      if (entry.key == 'META-INF/CERT') continue;
      digests[entry.key] = crypto.sha256.convert(entry.value).toString();
    }
  }
  return Uint8List.fromList(utf8.encode(json.encode(<String, dynamic>{
    'algorithm': 'SHA-256',
    'digests': digests,
  })));
}

Uint8List _buildCert(
  Uint8List hashJson,
  int mtime,
  int mdate,
  RsaKeyPair key,
  Uint8List certificate,
) {
  final meta = buildZip(<RpkBuildEntry>[
    RpkBuildEntry(
      name: 'hash.json',
      method: 8,
      mtime: mtime,
      mdate: mdate,
      eattr: 0,
      verMade: 20,
      verNeed: 20,
      data: hashJson,
    ),
  ]);
  return signZip(
    meta,
    <RpkFileDigest>[RpkFileDigest('hash.json', _sha256(meta))],
    key,
    certificate,
  );
}

Uint8List _sha256(Uint8List data) =>
    Uint8List.fromList(crypto.sha256.convert(data).bytes);

/// 包内文件清单（不含签名块），用来判断入口脚本是明文还是字节码。
List<String> rpkEntryNames(Uint8List bytes) {
  final zip = RpkZip.parse(stripSignBlock(bytes));
  return <String>[
    for (final entry in zip.entries)
      if (!entry.isDirectory) entry.name,
  ];
}
