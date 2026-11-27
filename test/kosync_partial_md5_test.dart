import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/kosync/kosync_partial_md5.dart';

/// KOReader partial MD5 的黄金向量。
///
/// 合成向量来自 KOReader 协议规范 `pid1/kosync-conformance` 的 SPEC.md §8.6，
/// 序列定义 `P(n)[i] = (i * 31 + (i >> 8)) mod 256`。这些值由 KOReader 自身
/// 的单元测试断言，属于跨实现的固定基准，不是本页屿自己算出来的。
void main() {
  List<int> synth(int n) {
    return List<int>.generate(
      n,
      (i) => (i * 31 + (i >> 8)) % 256 & 0xFF,
    );
  }

  group('KosyncPartialMd5 采样点偏移', () {
    test('偏移表与 KOReader 一致，首个采样点是文件开头', () {
      expect(KosyncPartialMd5.offsets(), <int>[
        0, //
        1024,
        4096,
        16384,
        65536,
        262144,
        1048576,
        4194304,
        16777216,
        67108864,
        268435456,
        1073741824,
      ]);
    });

    test('首个采样点是 0 而不是 1 TiB（32 位溢出语义）', () {
      // 掩码后的移位数是 30，`1024 << 30` 溢出 32 位后归零。
      expect(KosyncPartialMd5.offsetAt(-1), 0);
      expect(KosyncPartialMd5.offsetAt(0), 1024);
      expect(KosyncPartialMd5.offsetAt(10), 1073741824);
    });

    test('采样点数量为 12', () {
      expect(KosyncPartialMd5.sampleCount, 12);
      expect(KosyncPartialMd5.offsets().length, 12);
    });
  });

  group('KosyncPartialMd5 黄金向量（SPEC §8.6）', () {
    const cases = <(int, String, int)>[
      (500, '21f0df72cce9bc7da8dae2512ee5feed', 1),
      (1024, 'f4cd1641040a17288bb6104d9e66bdb5', 1),
      (1025, '170a888db01c00d8fc3e5d8d84de5838', 2),
      (2048, 'd0e59a0c7b893c3b8d6a9bddbd64e631', 2),
      (3000, 'd0e59a0c7b893c3b8d6a9bddbd64e631', 2),
      (200000, '1784b150454ef4cf6780ceb94af0386f', 5),
      (1050000, '0fca5c751677ecbc2dcfe80ea75ace32', 7),
    ];

    for (final (size, expected, samples) in cases) {
      test('P($size) 摘要与采样数一致', () {
        final result = KosyncPartialMd5.digestBytesDetailed(synth(size));
        expect(result.digest, expected);
        expect(result.samples, samples);
      });
    }
  });

  group('KosyncPartialMd5 文件版与内存版一致', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kosync_md5');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('同一份字节，两条路径给出相同摘要', () async {
      final bytes = synth(3000);
      final file = File('${dir.path}/book.bin');
      await file.writeAsBytes(bytes);
      final fromFile = await KosyncPartialMd5.digestFileDetailed(
        file.path,
      );
      expect(fromFile, isNotNull);
      expect(fromFile!.digest, KosyncPartialMd5.digestBytes(bytes));
      expect(fromFile.samples, 2);
    });

    test('文件不存在时返回 null 而不是抛错', () async {
      expect(await KosyncPartialMd5.digestFile('${dir.path}/missing.bin'), isNull);
    });

    test('空文件没有任何采样点', () async {
      final file = File('${dir.path}/empty.bin');
      await file.writeAsBytes(const <int>[]);
      final result = await KosyncPartialMd5.digestFileDetailed(file.path);
      expect(result, isNotNull);
      expect(result!.samples, 0);
      expect(result.digest, 'd41d8cd98f00b204e9800998ecf8427e'); // md5("")
    });
  });
}
