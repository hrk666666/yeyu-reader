/// 把种子片段以纯文本方式插进 app.js。
///
/// 插入点是框架入口函数体里的 `var org_app_require = $app_require$;` 之后：
/// 只有函数体内部才拿得到真正的 `global`（页面沙箱与模块顶层作用域不是
/// 同一个对象），而 `__seedBusy__` / `__bookshelf_cache__` 都挂在它上面。
/// 这里只做文本替换，不触碰原有任何字节。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'seed_payload.dart';

/// 注入失败的原因。
enum SeedInjectError {
  /// 包里没有 app.js（多半是纯 jsc 构建，注入无从下手）。
  noAppJs,

  /// 已经塞过书，拒绝重复注入。
  alreadyInjected,

  /// 找不到注入点，或注入点不唯一。
  anchorMissing,
}

class SeedInjectException implements Exception {
  const SeedInjectException(this.reason, this.detail);

  final SeedInjectError reason;
  final String detail;

  @override
  String toString() => 'SeedInjectException(${reason.name}): $detail';
}

/// 注入点。缩进不写死，兼容不同构建产物的排版。
final RegExp _anchor = RegExp(
  r'^([ \t]*)var org_app_require = \$app_require\$;',
  multiLine: true,
);

/// 返回注入后的字节。
///
/// [appJs] 是包内 `app.js` 的原始内容，[payload] 是 [buildSeedPayload] 的产物。
Uint8List injectSeed(Uint8List appJs, String payload) {
  final source = utf8.decode(appJs, allowMalformed: true);
  if (source.contains(kSeedPayloadMarker)) {
    throw const SeedInjectException(
      SeedInjectError.alreadyInjected,
      '这个包的 app.js 里已经有内置书数据',
    );
  }
  final matches = _anchor.allMatches(source).toList();
  if (matches.isEmpty) {
    throw const SeedInjectException(
      SeedInjectError.anchorMissing,
      '找不到注入点（var org_app_require = \$app_require\$;）',
    );
  }
  if (matches.length > 1) {
    throw SeedInjectException(
      SeedInjectError.anchorMissing,
      '注入点出现了 ${matches.length} 次，不能确定插哪儿',
    );
  }
  final match = matches.single;
  final injected = source.replaceRange(
    match.end,
    match.end,
    '\n$payload',
  );
  return Uint8List.fromList(utf8.encode(injected));
}

/// 包里的入口脚本是明文还是字节码。
enum SeedEntryKind {
  /// 有 `app.js`，可以注入。
  plainJs,

  /// 只有 `app.jsc`，是编译过的字节码，没法改。
  bytecode,

  /// 两者都没有，多半不是页屿手环端。
  unknown,
}

/// 按包内文件清单判断入口类型。
SeedEntryKind detectEntryKind(Iterable<String> names) {
  final set = names.toSet();
  if (set.contains('app.js')) return SeedEntryKind.plainJs;
  if (set.contains('app.jsc')) return SeedEntryKind.bytecode;
  return SeedEntryKind.unknown;
}
