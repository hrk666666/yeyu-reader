import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// 一只已连接的手环。
class BandDevice {
  const BandDevice({required this.id, required this.name});

  final String id;
  final String name;
}

/// 传书链路的可读异常，[message] 直接呈现在页面上。
class BandBookException implements Exception {
  const BandBookException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 平台侧上报的链路事件（不是手环端业务消息）。
enum BandLinkEvent {
  /// 发送失败／节点掉线，SDK 已解绑，需要重新 connect + 握手。
  broken,
}

/// 小米穿戴 SDK（xms-wearable）的 Dart 薄封装。
///
/// 平台侧 `BandBookPlugin` 只做 Binder 转发，握手与文件协议在
/// [BandBookTransfer]；两侧各有一份状态机会互相打架，所以不重复。
///
/// 通道：`fqapp/band-book`（方法）、`fqapp/band-book/events`（手环消息）。
/// EventChannel 上 `tag == "__link__"` 的帧被抽到 [linkEvents]，业务侧看不到。
class BandBookLink {
  BandBookLink({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methods = methodChannel ?? const MethodChannel('fqapp/band-book'),
      _events = eventChannel ?? const EventChannel('fqapp/band-book/events');

  /// 平台侧控制帧的保留 tag，与手环端 `__hs__` / `file` 不冲突。
  static const String linkTag = '__link__';

  final MethodChannel _methods;
  final EventChannel _events;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<Map<String, dynamic>> _incoming =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<BandLinkEvent> _linkEvents =
      StreamController<BandLinkEvent>.broadcast();

  Stream<Map<String, dynamic>> get incoming => _incoming.stream;

  /// 平台侧判断的链路异常，用于触发重连。
  Stream<BandLinkEvent> get linkEvents => _linkEvents.stream;

  /// 先订阅再连接：手环端接收页一打开就会主动发握手包，晚订阅会丢首包。
  void start() {
    _subscription ??= _events
        .receiveBroadcastStream()
        .listen(
          (dynamic raw) {
            final text = raw?.toString() ?? '';
            if (text.isEmpty) return;
            try {
              final decoded = jsonDecode(text);
              if (decoded is! Map) return;
              final message = Map<String, dynamic>.from(decoded);
              if (message['tag'] == linkTag) {
                if (message['event'] == 'broken') {
                  _linkEvents.add(BandLinkEvent.broken);
                }
                return;
              }
              _incoming.add(message);
            } on FormatException {
              // 一条坏包不该打断整场传输：丢掉继续等下一包。
            }
          },
          onError: (Object _) {},
        );
  }

  /// 取已连接设备 + 申请 DEVICE_MANAGER + 拉起手环接收页 `/pages/push`。
  ///
  /// 幂等：已绑定且设备仍在连接列表时直接复用，不会把用户手环上的页面
  /// 反复顶到前台（重连只重建监听，不需要重新 launchWearApp）。
  Future<BandDevice> connect() async {
    try {
      final result = await _methods.invokeMapMethod<String, dynamic>('connect');
      final id = result?['id'] as String? ?? '';
      final name = result?['name'] as String? ?? '手环';
      if (id.isEmpty) {
        throw const BandBookException('未能读取手环信息，请重试');
      }
      return BandDevice(id: id, name: name);
    } on PlatformException catch (error) {
      throw BandBookException(error.message ?? '连接手环失败');
    } on MissingPluginException {
      throw const BandBookException('当前平台不支持手环传书（仅 Android）');
    }
  }

  /// 链路探活：节点还在连接列表里才为 true。
  Future<bool> probe() async {
    try {
      return await _methods.invokeMethod<bool>('probe') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> send(Map<String, dynamic> message) async {
    try {
      await _methods.invokeMethod<void>('send', {'message': jsonEncode(message)});
    } on PlatformException catch (error) {
      throw BandBookException(error.message ?? '消息发送失败');
    } on MissingPluginException {
      throw const BandBookException('当前平台不支持手环传书（仅 Android）');
    }
  }

  Future<void> disconnect() async {
    try {
      await _methods.invokeMethod<void>('disconnect');
    } on PlatformException {
      // 断开失败不阻塞：下一次 connect 会重建监听。
    } on MissingPluginException {
      // 同上。
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _incoming.close();
    await _linkEvents.close();
  }
}
