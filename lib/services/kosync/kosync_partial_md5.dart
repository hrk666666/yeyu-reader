import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// KOReader `util.partialMD5` 的等价实现。
///
/// KOReader 用它给一本打开着的书算一个「内容指纹」，当作 kosync 协议里的
/// `document` 标识，从而让两台设备认出「这是同一本书」。
///
/// 算法（KOReader `frontend/util.lua`）：
/// 1. 从文件偏移 0 开始，每步把偏移量乘 4，共取 12 个采样点；
/// 2. 每个采样点读 1024 字节，读到文件末尾就停（不足 1024 字节按实际长度
///    计入，不再补零）；
/// 3. 把这 12 段（最多 12 KiB）按顺序拼起来，整体算一次 MD5。
///
/// 关键细节：**偏移量是 32 位溢出运算**。KOReader 用 LuaJIT 的 `bit.lshift`，
/// 而 `bit.lshift` 的移位数按 5 bit 掩码、结果按 32 位截断。第一步的移位
/// 计数是 `-2`，掩码后等于 30，`1024 << 30` 溢出 32 位后正好是 0——所以第一个
/// 采样点是文件开头，而不是 1 TiB 之后的某个位置。照字面写 `1024 << (4*i)`
/// 会让每一本书都算出错误的哈希，两端永远对不上。
///
/// 这里显式保留 32 位语义：Dart 的 int 是 64 位，不做掩码就会得到完全不同的
/// 偏移表。
class KosyncPartialMd5 {
  const KosyncPartialMd5._();

  /// 每个采样点读取的字节数。
  static const int sampleSize = 1024;

  /// 采样点数量：i 从 -1 到 10。
  static const int sampleCount = 12;

  /// 第 [i] 个采样点的文件偏移。
  ///
  /// 移位数按 5 bit 掩码（LuaJIT `bit` 语义），结果按 32 位截断。
  static int offsetAt(int i) {
    final shift = (2 * i) & 31;
    return (sampleSize << shift) & 0xFFFFFFFF;
  }

  /// 全部采样点的偏移，供测试与调试查看。
  ///
  /// 注意公式里的采样序号 i 从 -1 起（第一个采样点落在文件开头），而列表
  /// 下标从 0 起，两者相差 1。
  static List<int> offsets() =>
      List<int>.generate(sampleCount, (index) => offsetAt(index - 1));

  /// 对内存字节序列计算 partial MD5。
  ///
  /// 与文件版等价：偏移越界处视为结束。
  static ({String digest, int samples}) digestBytesDetailed(List<int> bytes) {
    final builder = BytesBuilder(copy: false);
    var samples = 0;
    for (final offset in offsets()) {
      if (offset >= bytes.length) break;
      final end = offset + sampleSize;
      builder.add(
        end <= bytes.length ? bytes.sublist(offset, end) : bytes.sublist(offset),
      );
      samples++;
    }
    return (digest: md5.convert(builder.takeBytes()).toString(), samples: samples);
  }

  /// 对内存字节序列计算 partial MD5。
  static String digestBytes(List<int> bytes) => digestBytesDetailed(bytes).digest;

  /// 对文件计算 partial MD5。
  ///
  /// 只读最多 12 KiB，与文件大小无关；文件不存在或不可读时返回 null，
  /// 调用方据此回退到别的标识方式。
  static Future<({String digest, int samples})?> digestFileDetailed(
    String path,
  ) async {
    final file = File(path);
    if (!await file.exists()) return null;
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final builder = BytesBuilder(copy: false);
      var samples = 0;
      for (final offset in offsets()) {
        await handle.setPosition(offset);
        // 读到 EOF 时 RandomAccessFile 返回空列表，与 Lua `file:read(n)`
        // 返回 nil 的语义一致：停止，不再补零。
        final chunk = await handle.read(sampleSize);
        if (chunk.isEmpty) break;
        builder.add(chunk);
        samples++;
      }
      return (
        digest: md5.convert(builder.takeBytes()).toString(),
        samples: samples,
      );
    } catch (_) {
      // A book that cannot be hashed must not break the sync path; the caller
      // falls back to a different document id.
      return null;
    } finally {
      try {
        await handle?.close();
      } catch (_) {
        // Closing a handle that was never opened is not an error worth raising.
      }
    }
  }

  /// 对文件计算 partial MD5。
  static Future<String?> digestFile(String path) async =>
      (await digestFileDetailed(path))?.digest;
}
