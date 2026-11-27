import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/band_book/band_book_link.dart';
import 'package:fqapp/services/band_book/band_book_transfer.dart';

/// 按手环端（弦电子书 Vela 客户端）的实际应答节奏回包的假链路。
///
/// 握手、分片流控、章节落地、增量查询都照着 `utils/interconnfile.js` 与
/// `utils/handshake.js` 的真实行为走，方便测试在不连硬件的前提下验证
/// 状态机。可注入的故障点用于验证断线续传。
class _FakeBandLink implements BandBookLink {
  /// 手环端回报的版本号：V26.5.1（≥ 手环端最低要求 251231）。
  int bandVersion = 260510;

  /// 回报的 dotted 版本名（a.b.c 可续段）；非空时握手回包带上 versionName。
  String? bandVersionName;

  final List<Map<String, dynamic>> sent = [];
  final StreamController<Map<String, dynamic>> _incoming =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<BandLinkEvent> _link = StreamController<BandLinkEvent>.broadcast();

  int totalChapters = 0;
  bool cancelled = false;

  /// 手环上「已经存在」的章节索引，`get_book_status` 会返回它。
  Set<int> syncedChapters = {};

  /// 落盘成功的章节数（含重连前后累计）。
  final Set<int> savedChapters = {};

  /// 传满 N 章后第一次回 error，用于触发断线续传。
  int? failAfterChapters;
  bool _failedOnce = false;

  int connectCount = 0;

  /// 手环端回包延迟，用来制造「传输在途」的窗口。
  Duration replyDelay = Duration.zero;

  /// 正文加载顺序，用于验证「边下边传」的重叠程度。
  final List<int> loadOrder = [];

  @override
  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  @override
  Stream<BandLinkEvent> get linkEvents => _link.stream;

  @override
  void start() {}

  @override
  Future<BandDevice> connect() async {
    connectCount += 1;
    return const BandDevice(id: 'node-1', name: '小米手环 10');
  }

  @override
  Future<bool> probe() async => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _incoming.close();
    await _link.close();
  }

  void _reply(Map<String, dynamic> message) {
    void emit() {
      if (!_incoming.isClosed) _incoming.add(message);
    }

    if (replyDelay == Duration.zero) {
      scheduleMicrotask(emit);
    } else {
      Timer(replyDelay, emit);
    }
  }

  /// 测试用：主动推一条手环端消息（例如 error）。
  void push(Map<String, dynamic> message) => _reply(message);

  /// 测试用：模拟平台侧判定链路失效。
  void breakLink() => _link.add(BandLinkEvent.broken);

  @override
  Future<void> send(Map<String, dynamic> message) async {
    sent.add(message);
    if (cancelled) return;

    final tag = message['tag'];
    if (tag == '__hs__') {
      final count = (message['count'] as num).toInt();
      if (count == 0) {
        _reply({
          'tag': '__hs__',
          'count': 1,
          'version': bandVersion,
          if (bandVersionName != null) 'versionName': bandVersionName,
        });
      }
      return;
    }
    if (tag != 'file') return;

    switch (message['stat']) {
      case 'get_book_status':
        _reply({
          'tag': 'file',
          'type': 'book_status',
          'syncedChapters': syncedChapters.toList()..sort(),
          'hasCover': false,
        });
      case 'startTransfer':
        totalChapters = (message['total'] as num).toInt();
        _reply({'tag': 'file', 'type': 'ready', 'usage': 0, 'count': 0});
      case 'd':
        final data = jsonDecode(message['data'] as String) as Map<String, dynamic>;
        final last =
            (data['chunkNum'] as num).toInt() == (data['totalChunks'] as num).toInt() - 1;
        _reply({
          'tag': 'file',
          'type': last ? 'chapter_chunk_complete' : 'next_chunk',
        });
      case 'chapter_complete':
        final index = (message['count'] as num).toInt();
        savedChapters.add(index);
        final limit = failAfterChapters;
        if (limit != null && !_failedOnce && savedChapters.length >= limit) {
          _failedOnce = true;
          _reply({'tag': 'file', 'type': 'error', 'message': '手环端写入失败', 'count': index});
          return;
        }
        _reply({
          'tag': 'file',
          'type': 'chapter_saved',
          'count': index,
          'syncedCount': savedChapters.length,
          'totalCount': totalChapters,
          'progress': 100.0,
        });
      case 'transfer_complete':
        _reply({'tag': 'file', 'type': 'transfer_finished'});
      case 'cancel':
        _reply({'tag': 'file', 'type': 'cancel'});
    }
  }

  /// 只保留文件协议消息，过滤握手包。
  List<String> get fileStats => [
    for (final message in sent)
      if (message['tag'] == 'file') message['stat'] as String,
  ];

  /// 所有 startTransfer 的入参，用于验证续传点。
  List<Map<String, dynamic>> get starts => [
    for (final message in sent)
      if (message['stat'] == 'startTransfer') message,
  ];
}

void main() {
  test('connect completes handshake after the band replies', () async {
    final link = _FakeBandLink();
    final transfer = BandBookTransfer(link: link);
    addTearDown(transfer.dispose);

    await transfer.connect();

    expect(transfer.state.phase, BandTransferPhase.ready);
    expect(transfer.state.device?.name, '小米手环 10');
    expect(transfer.state.bandVersion, 260510);
    expect(link.sent.first, {
      'tag': '__hs__',
      'count': 0,
      'version': BandBookTransfer.phoneVersion,
      'versionName': BandBookTransfer.phoneVersionName,
    });
    // 手环回 count:1 之后手机还要回 count:2，与手环端 `count++ < 2` 对齐。
    expect(
      link.sent.where((m) => m['tag'] == '__hs__').map((m) => m['count']),
      [0, 2],
    );
  });

  group('版本 a.b.c 兼容规则（强制 a.b 一致，其余段不限）', () {
    test('a.b 一致时连接成功（26.6.1 ↔ 26.6.1.n67，c/机型码不限）', () async {
      final link = _FakeBandLink()..bandVersionName = '26.6.1.n67';
      final transfer = BandBookTransfer(link: link);
      addTearDown(transfer.dispose);

      await transfer.connect();
      expect(transfer.state.phase, BandTransferPhase.ready);
    });

    test('a.b 一致但 c 不同也放行（26.6.1 ↔ 26.6.9）', () async {
      final link = _FakeBandLink()..bandVersionName = '26.6.9';
      final transfer = BandBookTransfer(link: link);
      addTearDown(transfer.dispose);

      await transfer.connect();
      expect(transfer.state.phase, BandTransferPhase.ready);
    });

    test('a.b 不一致时拒绝连接并报版本不兼容（26.6.x ↔ 25.12.x）', () async {
      final link = _FakeBandLink()..bandVersionName = '25.12.31';
      final transfer = BandBookTransfer(link: link);
      addTearDown(transfer.dispose);

      await transfer.connect();
      expect(transfer.state.phase, BandTransferPhase.failed);
      expect(transfer.state.error, contains('版本不兼容'));
    });

    test('majorMinor 只取前两段（忽略 V 前缀与后续段）', () {
      expect(BandBookTransfer.majorMinor('26.6.1'), '26.6');
      expect(BandBookTransfer.majorMinor('V26.6.1.n67'), '26.6');
      expect(BandBookTransfer.majorMinor('25.12.31'), '25.12');
    });

    test('旧手环（无 versionName）走数值版本下限检查：低于下限拒绝', () async {
      final link = _FakeBandLink()..bandVersion = 251230; // < minBandVersion
      final transfer = BandBookTransfer(link: link);
      addTearDown(transfer.dispose);

      await transfer.connect();
      expect(transfer.state.phase, BandTransferPhase.failed);
      expect(transfer.state.error, contains('版本过低'));
    });
  });

  test('sendBook walks startTransfer → chunks → chapter_complete → transfer_complete', () async {
    final link = _FakeBandLink();
    final transfer = BandBookTransfer(link: link);
    addTearDown(transfer.dispose);

    final bodies = ['第一章正文', '第二章正文'];
    final ok = await transfer.sendBook(
      title: '测试书',
      chapterTitles: const ['第一章', '第二章'],
      loadChapter: (index) async => bodies[index],
    );

    expect(ok, isTrue);
    expect(transfer.state.phase, BandTransferPhase.finished);
    expect(link.fileStats, [
      'startTransfer',
      'd',
      'chapter_complete',
      'd',
      'chapter_complete',
      'transfer_complete',
    ]);

    final start = link.sent.firstWhere((m) => m['stat'] == 'startTransfer');
    expect(start['total'], 2);
    expect(start['chapterIndices'], [0, 1]);
    expect(start['startFrom'], 0);
    expect(start['filename'], '测试书');

    final chunk = link.sent.firstWhere((m) => m['stat'] == 'd');
    final data = jsonDecode(chunk['data'] as String) as Map<String, dynamic>;
    expect(data['index'], 0);
    expect(data['name'], '第一章');
    expect(data['content'], '第一章正文');
    expect(data['chunkNum'], 0);
    expect(data['totalChunks'], 1);
  });

  test('long chapters are split into 10k-character chunks with flow control', () async {
    final link = _FakeBandLink();
    final transfer = BandBookTransfer(link: link);
    addTearDown(transfer.dispose);

    final long = '字' * (BandBookTransfer.chunkSize * 2 + 100);
    await transfer.sendBook(
      title: '长书',
      chapterTitles: const ['长章'],
      loadChapter: (_) async => long,
    );

    final chunks = link.sent.where((m) => m['stat'] == 'd').toList();
    expect(chunks.length, 3);
    final lengths = [
      for (final message in chunks)
        ((jsonDecode(message['data'] as String) as Map)['content'] as String).length,
    ];
    expect(lengths, [BandBookTransfer.chunkSize, BandBookTransfer.chunkSize, 100]);
  });

  test('band error message surfaces as a failed state', () async {
    final link = _FakeBandLink();
    final transfer = BandBookTransfer(link: link);
    addTearDown(transfer.dispose);
    await transfer.connect();

    // 手环端存储不足等错误：会话应立即失败，而不是干等超时。
    link.push({'tag': 'file', 'type': 'error', 'message': '存储空间不足', 'count': 0});
    await Future<void>.delayed(Duration.zero);

    expect(transfer.state.phase, BandTransferPhase.failed);
    expect(transfer.state.error, '存储空间不足');
  });

  test('fetchStatus parses syncedChapters to drive incremental sync', () async {
    final link = _FakeBandLink()..syncedChapters = {0, 1, 3};
    final transfer = BandBookTransfer(link: link);
    addTearDown(transfer.dispose);

    final status = await transfer.fetchStatus('增量书');

    expect(status.syncedChapters, {0, 1, 3});
    expect(status.missingFrom(5), [2, 4]);
    expect(status.missingFrom(3), [2]);
  });

  test('incremental send only ships the missing chapters', () async {
    final link = _FakeBandLink()..syncedChapters = {0, 1, 3};
    final transfer = BandBookTransfer(link: link);
    addTearDown(transfer.dispose);

    final bodies = ['a', 'b', 'c', 'd', 'e'];
    final ok = await transfer.sendBook(
      title: '增量书',
      chapterTitles: const ['一', '二', '三', '四', '五'],
      loadChapter: (index) async => bodies[index],
      chapters: [2, 4],
      totalChapters: 5,
    );

    expect(ok, isTrue);
    final start = link.starts.single;
    // startFrom 取子集首个索引；chapterIndices 是本次要传的绝对索引子集。
    expect(start['startFrom'], 2);
    expect(start['chapterIndices'], [2, 4]);
    // total 仍是全书章数，手环端据此写 lindex.txt。
    expect(start['total'], 5);

    final indices = [
      for (final message in link.sent)
        if (message['stat'] == 'chapter_complete') (message['count'] as num).toInt(),
    ];
    expect(indices, [2, 4]);
    expect(transfer.state.sentChapters, 2);
  });

  test('missing-only queue is a no-op when the band already has every chapter', () async {
    final link = _FakeBandLink()..syncedChapters = {0, 1};
    final transfer = BandBookTransfer(link: link);
    addTearDown(transfer.dispose);

    final ok = await transfer.sendBook(
      title: '齐全书',
      chapterTitles: const ['一', '二'],
      loadChapter: (_) async => 'x',
      chapters: const [],
    );

    expect(ok, isFalse);
    expect(transfer.state.error, '没有需要同步的章节');
    expect(link.fileStats, isEmpty);
  });

  test('a dropped session reconnects and resumes from the last chapter', () async {
    final link = _FakeBandLink()..failAfterChapters = 2;
    final transfer = BandBookTransfer(link: link, retryDelay: Duration.zero);
    addTearDown(transfer.dispose);

    final ok = await transfer.sendBook(
      title: '断线书',
      chapterTitles: const ['一', '二', '三'],
      loadChapter: (index) async => '正文$index',
    );

    expect(ok, isTrue);
    // sendBook 首次只靠握手起链，不调 link.connect；重试时才真正重连一次。
    expect(link.connectCount, 1);
    expect(link.starts.length, 2);
    // 游标停在第 2 章（索引 1）这个写失败的章节上，续传从它重发，
    // 已落地的第 1 章不重来。
    expect(link.starts.first['startFrom'], 0);
    expect(link.starts.last['startFrom'], 1);
    expect(link.starts.last['chapterIndices'], [0, 1, 2]);
    expect(transfer.state.retries, 1);
    expect(link.savedChapters, {0, 1, 2});
  });

  test('download and upload overlap instead of serialising', () async {
    final link = _FakeBandLink();
    final transfer = BandBookTransfer(link: link);
    addTearDown(transfer.dispose);

    final started = <int>[];
    await transfer.sendBook(
      title: '流式书',
      chapterTitles: const ['一', '二', '三'],
      loadChapter: (index) async {
        started.add(index);
        // 取正文比发分片慢，串行实现会严格按 0,1,2 顺序开始。
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return '正文$index';
      },
    );

    // 第 0 章还没开始发，第 1 章的正文就已在取：这就是「边下边传」。
    expect(started.first, 1);
    expect(started.toSet(), {0, 1, 2});
  });

  test('slow chapter loading keeps the link alive instead of tripping the watchdog', () {
    fakeAsync((async) {
      final link = _FakeBandLink();
      final transfer = BandBookTransfer(link: link);
      final gate = Completer<String>();

      var done = false;
      unawaited(
        transfer
            .sendBook(
              title: '慢书',
              chapterTitles: const ['一'],
              loadChapter: (_) => gate.future,
            )
            .then((value) => done = value),
      );

      // 握手 + startTransfer 走完，随后正文迟迟不来。
      async.elapse(const Duration(seconds: 1));
      expect(link.starts, hasLength(1));

      // 超过两端 10s/15s 看门狗都不该断线：中途应已发出保活包。
      async.elapse(const Duration(seconds: 20));
      expect(
        link.fileStats.where((stat) => stat == 'get_storage_info'),
        isNotEmpty,
        reason: '边下边传静默期间必须靠保活续命',
      );
      expect(transfer.state.phase, BandTransferPhase.sending);

      gate.complete('正文');
      async.elapse(const Duration(seconds: 2));
      expect(done, isTrue);
      expect(transfer.state.phase, BandTransferPhase.finished);

      transfer.dispose();
      async.flushMicrotasks();
    });
  });

  test('platform link break fails the session instead of hanging', () async {
    final link = _FakeBandLink()
      ..replyDelay = const Duration(milliseconds: 200);
    final transfer = BandBookTransfer(link: link, retryDelay: Duration.zero);
    addTearDown(transfer.dispose);

    final future = transfer.sendBook(
      title: '掉线书',
      chapterTitles: const ['一'],
      loadChapter: (_) async => '正文',
      autoRetry: false,
    );
    // 握手与 startTransfer 已回，此刻正卡在分片回包等待里。
    await Future<void>.delayed(const Duration(milliseconds: 60));
    link.breakLink();

    // 不靠 25s 分片超时收尾，平台一报断链就要立刻失败。
    final ok = await future.timeout(const Duration(seconds: 3));
    expect(ok, isFalse);
    expect(transfer.state.phase, BandTransferPhase.failed);
  });
}
