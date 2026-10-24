import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/di/injection.dart';
import '../../domain/entities/chat_message.dart';
import '../../native_view/bridge/native_chat_event.dart';
import '../../native_view/native_chat_view.dart';
import '../../native_view/render/chat_render_builder.dart';
import '../../native_view/render/chat_render_item.dart';
import '../cubit/chat_cubit.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/new_message_chip.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.roomId, required this.peer});

  final int roomId;
  final ChatPeer peer;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ChatCubit>(param1: roomId, param2: peer)..start(),
      child: const _ChatView(),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView();

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _listHandle = NativeChatViewHandle();
  final _inputFocus = FocusNode();
  bool _atBottom = true;

  // 렌더 아이템은 메시지 목록이 바뀔 때만 다시 만든다.
  // (같은 리스트 인스턴스면 NativeChatView 도 diff 를 건너뛴다)
  List<ChatMessage>? _builtFrom;
  List<ChatRenderItem> _items = const [];

  List<ChatRenderItem> _renderItems(List<ChatMessage> messages) {
    if (!identical(messages, _builtFrom)) {
      _builtFrom = messages;
      _items = ChatRenderBuilder.build(messages);
    }
    return _items;
  }

  @override
  void dispose() {
    _inputFocus.dispose();
    super.dispose();
  }

  void _onNativeEvent(NativeChatEvent event) {
    final cubit = context.read<ChatCubit>();
    switch (event) {
      case LoadOlderRequested():
        unawaited(cubit.loadOlder());
      case BackgroundTapped():
        _inputFocus.unfocus();
      case AtBottomChanged(:final atBottom):
        if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
      case RetryTapped(:final key):
        unawaited(cubit.retry(key));
      case LockedMessageTapped(:final key):
        unawaited(_confirmUnlock(key));
      case MessageTapped(:final key):
        _openMessage(key);
      case AvatarTapped():
        _showPeer();
    }
  }

  Future<void> _confirmUnlock(String key) async {
    final cubit = context.read<ChatCubit>();
    final content = cubit.state.byKey(key)?.content;
    if (content is! ImageContent) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('잠긴 사진'),
        content: Text('${content.price ?? 0} 포인트로 사진을 열어볼까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('열기'),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.unlock(key);
  }

  void _openMessage(String key) {
    final content = context.read<ChatCubit>().state.byKey(key)?.content;
    if (content is! ImageContent || content.locked) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
            body: Center(child: InteractiveViewer(child: Image.network(content.url))),
          ),
        ),
      ),
    );
  }

  void _showPeer() {
    final peer = context.read<ChatCubit>().state.peer;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => SafeArea(
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: peer.avatarUrl == null
                  ? null
                  : NetworkImage(peer.avatarUrl!),
            ),
            title: Text(peer.nickname),
            subtitle: const Text('프로필 화면 자리'),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChatCubit, ChatState>(
      listenWhen: (prev, curr) => curr.notice != null && prev.notice != curr.notice,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.notice!)));
        context.read<ChatCubit>().clearNotice();
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: Text(state.peer.nickname)),
          body: Column(
            children: [
              Expanded(
                child: state.loadingInitial
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                        children: [
                          NativeChatView(
                            config: NativeChatViewConfig(
                              peerNickname: state.peer.nickname,
                              peerAvatarUrl: state.peer.avatarUrl,
                            ),
                            items: _renderItems(state.messages),
                            loadingOlder: state.loadingOlder,
                            hasMoreOlder: state.hasMoreOlder,
                            handle: _listHandle,
                            onEvent: _onNativeEvent,
                          ),
                          if (!_atBottom)
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: NewMessageChip(
                                  onTap: () => _listHandle.scrollToBottom(),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              ChatInputBar(
                focusNode: _inputFocus,
                onSend: (text) => context.read<ChatCubit>().sendText(text),
              ),
            ],
          ),
        );
      },
    );
  }
}
