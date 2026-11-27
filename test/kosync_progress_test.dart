import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/kosync/kosync_progress.dart';

void main() {
  group('KosyncProgress 编码', () {
    test('编码成「y1:章节:偏移」', () {
      expect(
        KosyncProgress.encode(chapterIndex: 3, textOffset: 120),
        'y1:3:120',
      );
    });

    test('负值被夹到 0', () {
      expect(
        KosyncProgress.encode(chapterIndex: -2, textOffset: -9),
        'y1:0:0',
      );
    });
  });

  group('KosyncProgress 解码自有格式', () {
    test('精确还原章节与字符偏移', () {
      final position = KosyncProgress.decode(
        'y1:3:120',
        chapterCount: 10,
        percentage: 0.35,
      );
      expect(position, isNotNull);
      expect(position!.exact, isTrue);
      expect(position.chapterIndex, 3);
      expect(position.textOffset, 120);
    });

    test('前缀像但字段不合法时退回按百分比定位', () {
      final position = KosyncProgress.decode(
        'y1:abc',
        chapterCount: 10,
        percentage: 0.5,
      );
      expect(position, isNotNull);
      expect(position!.exact, isFalse);
    });
  });

  group('KosyncProgress 解码外来格式（KOReader XPointer）', () {
    test('无法精确解释时按百分比折算章节', () {
      final position = KosyncProgress.decode(
        '/body/DocFragment/body/p[12]/text().3',
        chapterCount: 10,
        percentage: 0.55,
      );
      expect(position, isNotNull);
      expect(position!.exact, isFalse);
      expect(position.textOffset, isNull);
      expect(position.chapterIndex, 5);
      expect(position.chapterFraction, closeTo(0.5, 1e-9));
    });

    test('百分比 0 落在第一章', () {
      final position = KosyncProgress.decode(
        '/body/DocFragment',
        chapterCount: 10,
        percentage: 0,
      );
      expect(position!.chapterIndex, 0);
    });

    test('百分比 1 落在最后一章', () {
      final position = KosyncProgress.decode(
        '/body/DocFragment',
        chapterCount: 10,
        percentage: 1,
      );
      expect(position!.chapterIndex, 9);
    });

    test('百分比 1 且只有一章时不会越界', () {
      final position = KosyncProgress.decode(
        '/body/DocFragment',
        chapterCount: 1,
        percentage: 1,
      );
      expect(position!.chapterIndex, 0);
    });

    test('章节数为 0 时退回第一章', () {
      final position = KosyncProgress.decode(
        '/body/DocFragment',
        chapterCount: 0,
        percentage: 0.5,
      );
      expect(position!.chapterIndex, 0);
      expect(position.exact, isFalse);
    });
  });

  group('KosyncProgress 空输入', () {
    test('空串返回 null', () {
      expect(
        KosyncProgress.decode('   ', chapterCount: 10, percentage: 0.5),
        isNull,
      );
    });
  });
}
