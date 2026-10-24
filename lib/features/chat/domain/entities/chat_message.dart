import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';

@freezed
sealed class MessageContent with _$MessageContent {
  const factory MessageContent.text(String text) = TextContent;

  /// [locked]: 유료(잠긴) 사진. 구매 전에는 흐리게 + 가격 표시.
  const factory MessageContent.image({
    required String url,
    required double aspectRatio,
    @Default(false) bool locked,
    int? price,
  }) = ImageContent;

  const factory MessageContent.gift({
    required String name,
    required String imageUrl,
    required int amount,
  }) = GiftContent;

  /// 운영 공지 / 시스템 메시지. 가운데 정렬로 표시.
  const factory MessageContent.notice(String text) = NoticeContent;
}

enum MessageStatus { sending, sent, failed }

@freezed
abstract class ChatMessage with _$ChatMessage {
  const ChatMessage._();

  @Assert('clientId != null || serverId != null', 'clientId 또는 serverId 가 필요')
  const factory ChatMessage({
    /// 내가 보낸 메시지의 로컬 id. 서버에 tempId 로 보내고, 서버 응답에 그대로 돌아온다.
    String? clientId,
    int? serverId,
    required int senderId,
    required bool isMine,
    required DateTime createdAt,
    required MessageContent content,
    @Default(MessageStatus.sent) MessageStatus status,

    /// 내 메시지를 상대가 읽었는지.
    @Default(false) bool readByPeer,
  }) = _ChatMessage;

  /// 목록에서 메시지를 식별하는 키. 서버 확인(ack) 전후로 바뀌면 안 된다.
  ///
  /// 내가 보낸 메시지는 ack 로 serverId 가 생겨도 clientId 기반 키를 유지한다.
  /// 키가 바뀌면 네이티브 리스트 입장에서는 "삭제 + 삽입"이 되어 셀이 깜빡인다.
  String get key => clientId != null ? 'c:$clientId' : 's:$serverId';
}

class ChatPeer {
  const ChatPeer({required this.id, required this.nickname, this.avatarUrl});

  final int id;
  final String nickname;
  final String? avatarUrl;
}
