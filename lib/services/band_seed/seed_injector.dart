/// 判断 rpk 的入口脚本形态。
///
/// 现在任何手环包装都能塞书：入口是被**整体替换**成手写壳，页面字节码一个不动。
/// 保留这套判断只是为了在界面上说清「这个包原本长什么样」，不再作为拒绝理由。
library;

/// 包里的入口脚本形态。
enum SeedEntryKind {
  /// 有 `app.js`，原本就是明文（开发构建或混合包）。
  plainJs,

  /// 只有 `app.jsc`，是编译过的字节码。会被壳替换掉，不影响塞书。
  bytecode,

  /// 两者都没有，多半不是手环快应用。
  unknown,
}

/// 塞书失败的原因。
enum SeedInjectError {
  /// 包里缺 manifest.json 或入口脚本，不是能改的手环包。
  unsupportedPackage,
}

class SeedInjectException implements Exception {
  const SeedInjectException(this.reason, this.detail);

  final SeedInjectError reason;
  final String detail;

  @override
  String toString() => 'SeedInjectException(${reason.name}): $detail';
}

/// 按包内文件清单判断入口类型。
SeedEntryKind detectEntryKind(Iterable<String> names) {
  final set = names.toSet();
  if (set.contains('app.js')) return SeedEntryKind.plainJs;
  if (set.contains('app.jsc')) return SeedEntryKind.bytecode;
  return SeedEntryKind.unknown;
}
