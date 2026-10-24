import 'chat_message.dart';

/// 서버(소켓)에서 실시간으로 들어오는 방 이벤트.
sealed class ChatRoomEvent {
  const ChatRoomEvent();
}

final class MessageReceived extends ChatRoomEvent {
  const MessageReceived(this.message);

  final ChatMessage message;
}

/// 기존 메시지 변경 (잠금 해제, 숨김 처리 등).
final class MessageUpdated extends ChatRoomEvent {
  const MessageUpdated(this.message);

  final ChatMessage message;
}

/// 상대가 [serverId] 까지 읽음.
final class PeerReadUpTo extends ChatRoomEvent {
  const PeerReadUpTo(this.serverId);

  final int serverId;
}

class MessagePage {
  const MessagePage({required this.messages, required this.hasMore});

  /// 오래된 것 → 최신 순.
  final List<ChatMessage> messages;
  final bool hasMore;
}
