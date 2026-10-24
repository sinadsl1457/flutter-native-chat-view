import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge/native_chat_event.dart';
import 'bridge/native_chat_view_controller.dart';
import 'render/chat_render_item.dart';

/// 네이티브 채팅 리스트의 생성 시점 설정. 통화 중 바뀌지 않는 값만 둔다.
class NativeChatViewConfig {
  const NativeChatViewConfig({
    required this.peerNickname,
    this.peerAvatarUrl,
    this.fontSize = 15,
    this.mineBubbleColor = const Color(0xFFE6007E),
    this.peerBubbleColor = const Color(0xFFFFFFFF),
    this.backgroundColor = const Color(0xFFF1F1F3),
    this.readLabel = '읽음',
    this.failedLabel = '전송 실패',
  });

  final String peerNickname;
  final String? peerAvatarUrl;
  final double fontSize;
  final Color mineBubbleColor;
  final Color peerBubbleColor;
  final Color backgroundColor;
  final String readLabel;
  final String failedLabel;

  Map<String, Object?> toWire() => {
    'peerNickname': peerNickname,
    'peerAvatarUrl': peerAvatarUrl,
    'fontSize': fontSize,
    'mineBubbleColor': mineBubbleColor.toARGB32(),
    'peerBubbleColor': peerBubbleColor.toARGB32(),
    'backgroundColor': backgroundColor.toARGB32(),
    'readLabel': readLabel,
    'failedLabel': failedLabel,
  };
}

/// 채팅 메시지 목록을 네이티브 리스트(Android RecyclerView / iOS UITableView)로 그리는 위젯.
///
/// 사용법은 ListView 와 비슷하게 선언적이다. [items] 를 새로 넘기면 위젯이 이전 목록과 비교해
/// 바뀐 부분만 네이티브에 보낸다. 스크롤·셀 재사용·높이 계산은 전부 네이티브가 한다.
///
/// [items] 는 최신 → 오래된 순 (ChatRenderBuilder 의 출력).
class NativeChatView extends StatefulWidget {
  const NativeChatView({
    super.key,
    required this.config,
    required this.items,
    required this.onEvent,
    this.loadingOlder = false,
    this.hasMoreOlder = true,
    this.handle,
  });

  final NativeChatViewConfig config;
  final List<ChatRenderItem> items;
  final void Function(NativeChatEvent event) onEvent;
  final bool loadingOlder;
  final bool hasMoreOlder;

  /// 바깥에서 "맨 아래로" 같은 명령을 내릴 때.
  final NativeChatViewHandle? handle;

  static const viewType = 'native_chat_view';

  @override
  State<NativeChatView> createState() => _NativeChatViewState();
}

class NativeChatViewHandle {
  _NativeChatViewState? _state;

  Future<void> scrollToBottom({bool animated = true}) async =>
      _state?._controller?.scrollToBottom(animated: animated);
}

class _NativeChatViewState extends State<NativeChatView> {
  NativeChatViewController? _controller;

  /// creationParams 로 넘긴 첫 목록. 네이티브 뷰가 만들어지면서 바로 그리므로
  /// 생성 직후 별도 왕복 없이 첫 화면이 채워진다.
  late final List<ChatRenderItem> _initialItems = widget.items;

  @override
  void initState() {
    super.initState();
    widget.handle?._state = this;
  }

  @override
  void didUpdateWidget(covariant NativeChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handle != widget.handle) {
      oldWidget.handle?._state = null;
      widget.handle?._state = this;
    }

    final controller = _controller;
    if (controller == null) return; // 생성 완료 시 최신 items 를 한 번 더 맞춘다 (_onCreated)

    if (!identical(oldWidget.items, widget.items)) {
      unawaited(
        controller.render(
          widget.items,
          stickToBottom: _newestIsMineAndNew(oldWidget.items, widget.items),
        ),
      );
    }
    if (oldWidget.loadingOlder != widget.loadingOlder ||
        oldWidget.hasMoreOlder != widget.hasMoreOlder) {
      unawaited(_syncOlderState(controller));
    }
  }

  @override
  void dispose() {
    widget.handle?._state = null;
    _controller?.dispose();
    super.dispose();
  }

  void _onCreated(int viewId) {
    final controller = NativeChatViewController(
      viewId,
      initialItems: _initialItems,
      // 부모가 rebuild 되며 콜백이 바뀌어도 항상 최신 콜백을 부르도록.
      onEvent: (event) => widget.onEvent(event),
    );
    _controller = controller;
    // 뷰가 만들어지는 사이에 items 가 바뀌었을 수 있다.
    unawaited(controller.render(widget.items));
    unawaited(_syncOlderState(controller));
  }

  Future<void> _syncOlderState(NativeChatViewController controller) =>
      controller.setOlderState(
        loading: widget.loadingOlder,
        hasMore: widget.hasMoreOlder,
      );

  /// 맨 앞(가장 최신)에 새로 생긴 아이템이 내 메시지면 무조건 맨 아래로.
  static bool _newestIsMineAndNew(
    List<ChatRenderItem> before,
    List<ChatRenderItem> after,
  ) {
    if (after.isEmpty) return false;
    final newest = after.first;
    if (!newest.isMine) return false;
    return before.isEmpty || before.first.key != newest.key;
  }

  @override
  Widget build(BuildContext context) {
    final params = {
      'config': widget.config.toWire(),
      'initialItems': [for (final item in _initialItems) item.toWire()],
      'hasMoreOlder': widget.hasMoreOlder,
    };

    // 네이티브 리스트가 세로 드래그를 전부 받도록 한다.
    // 이게 없으면 상위에 스크롤/드래그 제스처가 있을 때 Flutter 제스처 경쟁에서 져서 스크롤이 끊긴다.
    final gestures = <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
    };

    if (Platform.isAndroid) {
      return AndroidView(
        viewType: NativeChatView.viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: gestures,
        onPlatformViewCreated: _onCreated,
      );
    }
    if (Platform.isIOS) {
      return UiKitView(
        viewType: NativeChatView.viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: gestures,
        onPlatformViewCreated: _onCreated,
      );
    }
    return const Center(child: Text('Android / iOS 에서만 지원합니다.'));
  }
}
