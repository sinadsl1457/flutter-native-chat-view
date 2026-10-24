import 'dart:async';

import 'package:flutter/services.dart';

import '../../../../core/logging/log.dart';
import '../render/chat_list_diff.dart';
import '../render/chat_render_item.dart';
import 'native_chat_event.dart';

/// PlatformView 인스턴스 하나와 1:1 로 연결된 채널.
///
/// 채널 이름에 viewId 를 붙인다 (`native_chat_view/<id>`).
/// 이름이 고정된 전역 채널을 쓰면 채팅 화면이 두 개 이상 생길 때(화면 전환 애니메이션 중,
/// 채팅방 → 다른 채팅방 push) 나중에 만든 쪽이 핸들러를 덮어써서 이벤트가 엉뚱한 화면으로 간다.
class NativeChatViewController {
  NativeChatViewController(
    int viewId, {
    required List<ChatRenderItem> initialItems,
    required void Function(NativeChatEvent event) onEvent,
  }) : _channel = MethodChannel('$channelPrefix$viewId'),
       _shown = initialItems,
       _onEvent = onEvent {
    _channel.setMethodCallHandler(_handleCall);
  }

  static const channelPrefix = 'native_chat_view/';
  static const _tag = 'NativeChatView';

  final MethodChannel _channel;
  final void Function(NativeChatEvent event) _onEvent;

  /// 네이티브가 현재 들고 있는 목록 (마지막으로 보낸 상태).
  List<ChatRenderItem> _shown;

  /// 명령은 반드시 보낸 순서대로 적용돼야 한다 (index 기반 op).
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// [items] 를 네이티브에 반영한다. 이전 상태와의 차이만 보낸다.
  ///
  /// [stickToBottom]: 맨 아래로 스크롤할지 여부를 네이티브에 강제한다 (내가 보낸 메시지).
  /// 상대 메시지는 네이티브가 "이미 맨 아래를 보고 있었을 때만" 따라 내려간다.
  Future<void> render(List<ChatRenderItem> items, {bool stickToBottom = false}) {
    final patch = ChatListDiff.compute(_shown, items);
    if (patch is OpsPatch && patch.isEmpty) return _queue;
    _shown = items;

    final Map<String, Object?> payload = switch (patch) {
      ResetPatch(:final items) => {
        'type': 'reset',
        'items': [for (final item in items) item.toWire()],
      },
      OpsPatch(:final ops) => {
        'type': 'ops',
        'ops': [for (final op in ops) op.toWire()],
      },
    };
    payload['stickToBottom'] = stickToBottom;

    return _enqueue('applyPatch', payload);
  }

  /// 이전 메시지 로딩 상태. 네이티브는 loading 동안 추가 요청을 보내지 않고 상단 로딩 표시를 한다.
  /// hasMore=false 면 더 이상 요청하지 않는다.
  Future<void> setOlderState({required bool loading, required bool hasMore}) =>
      _enqueue('setOlderState', {'loading': loading, 'hasMore': hasMore});

  Future<void> scrollToBottom({bool animated = true}) =>
      _enqueue('scrollToBottom', {'animated': animated});

  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _enqueue(String method, Map<String, Object?> args) {
    return _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await _channel.invokeMethod<void>(method, args);
      } on PlatformException catch (e) {
        Log.e(_tag, '$method failed: ${e.code} ${e.message}', e);
      } on MissingPluginException {
        Log.w(_tag, '$method: native view not available');
      }
    });
  }

  Future<void> _handleCall(MethodCall call) async {
    final event = NativeChatEvent.fromCall(call.method, call.arguments);
    if (event == null) {
      Log.w(_tag, 'unknown callback: ${call.method}');
      return;
    }
    _onEvent(event);
  }
}
