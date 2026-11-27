part of '../reader_page.dart';

/// 与 kosync 服务器之间的阅读进度同步。
///
/// 协议是 KOReader 用的那一套：服务端按书籍标识存一条「读到哪」的记录，
/// 只做覆盖写，新旧由客户端比较时间戳决定。
///
/// 这里的接入原则是**默认不参与**：用户没打开同步开关时，下面所有方法
/// 都在第一行就返回，阅读流程与没有这个功能时完全一致。
///
/// 定位用的是章节序号加章节内字符偏移，不是像素位置——像素位置随字号、
/// 行距、屏幕宽度变化，换台设备同一个像素根本不是同一段文字；字符偏移
/// 只跟正文有关，两台设备读到同一段文字时算出的值一致。
extension _ReaderPageKosync on _ReaderPageState {
  bool get _kosyncEnabled => KosyncSyncService.instance.isEnabled;

  /// 拉一次远端进度，并在远端确实更新时把阅读位置带过去。
  ///
  /// 只在打开这本书时拉一次：换章不必每次都问服务器。
  Future<void> _kosyncPull() async {
    if (!_kosyncEnabled || _kosyncPulled) return;
    _kosyncPulled = true;
    try {
      final remote = await KosyncSyncService.instance.pullProgress(
        widget.bookId,
        chapterCount: widget.chapters.length,
      );
      if (remote == null || !mounted) return;

      final local = await _history.load(widget.bookId);
      if (!mounted) return;
      final localTime = (local?['time'] as num?)?.toInt() ?? 0;
      // 服务端记的是秒，本地记的是毫秒。
      final remoteMillis = remote.timestamp * 1000;
      // 本地没有记录时以「现在」为基准：远端那条可能是很久以前留下的，
      // 甚至来自一台时钟不准的设备，不该把用户拽回老位置。
      final baseline = localTime > 0
          ? localTime
          : DateTime.now().millisecondsSinceEpoch;
      if (remoteMillis <= baseline) return;

      _applyKosyncRemote(remote);
    } catch (_) {
      // A sync failure must never interrupt reading.
    }
  }

  /// 把远端位置落到阅读器上。
  void _applyKosyncRemote(KosyncRemoteProgress remote) {
    final position = remote.position;
    if (widget.chapters.isEmpty) return;
    final targetIndex = position.chapterIndex.clamp(
      0,
      widget.chapters.length - 1,
    );
    final targetChapter = widget.chapters[targetIndex];
    final restore = <String, dynamic>{
      'chapterId': targetChapter.itemId,
      'kind': 'book',
    };
    if (position.exact && position.textOffset != null) {
      // source offset：与排版无关，跨设备可比。
      restore['textOffset'] = position.textOffset;
      restore['positionVersion'] = 2;
    }

    if (targetIndex == _index) {
      // 同一章：让下一次排版按远端位置恢复。
      _savedPosition = restore;
      _needsRestore = true;
      _chapterLayout = null;
      _setState(() {});
      return;
    }
    // 跨章：先记住位置，切章时由 [_load] 取用。
    _pendingKosyncRestore = restore;
    _index = targetIndex;
    _load();
  }

  /// 推送本地进度。
  ///
  /// [force] 用于换章这类必须立刻上行的时机；其余情况由服务层按间隔
  /// 节流，翻页太频繁没必要每一页都打一次网络。
  Future<void> _kosyncPush(Map<String, dynamic> entry, {required bool force}) {
    if (!_kosyncEnabled) return Future<void>.value();
    final index = (entry['episode'] as num?)?.toInt() ?? 0;
    final textOffset = (entry['textOffset'] as num?)?.toInt() ?? 0;
    final progress = (entry['progress'] as num?)?.toDouble() ?? 0;
    return KosyncSyncService.instance.pushProgress(
      bookId: widget.bookId,
      chapterIndex: index,
      textOffset: textOffset,
      percentage: progress,
      force: force,
    );
  }

  /// 保存进度后调用：换章、离开这一本书时立即上行，其余交给节流。
  ///
  /// [force] 是离开书籍的场合：节流窗口里最后读到的位置必须送出去，
  /// 否则服务器上留的是几十秒前的位置。
  Future<void> _kosyncPushAfterSave(
    Map<String, dynamic> entry, {
    bool force = false,
  }) async {
    if (!_kosyncEnabled) return;
    final index = (entry['episode'] as num?)?.toInt() ?? 0;
    final chapterChanged = index != _kosyncLastPushedChapter;
    _kosyncLastPushedChapter = index;
    await _kosyncPush(entry, force: force || chapterChanged);
  }
}
