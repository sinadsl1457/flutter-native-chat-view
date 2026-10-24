import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/chat_message.dart';
import '../entities/chat_room_event.dart';

/// 실서비스에서는 REST(이전 메시지) + 소켓(실시간 이벤트)으로 구현한다.
/// 이 저장소는 `FakeChatRepository` 로 서버 없이 동작한다.
abstract interface class ChatRepository {
  Stream<ChatRoomEvent> events(int roomId);

  Future<Either<Failure, MessagePage>> fetchLatest(int roomId, {int limit = 30});

  Future<Either<Failure, MessagePage>> fetchOlder(
    int roomId, {
    required int beforeServerId,
    int limit = 30,
  });

  /// 성공하면 서버가 확정한 메시지(serverId 포함, clientId 그대로)를 돌려준다.
  Future<Either<Failure, ChatMessage>> sendText(
    int roomId, {
    required String clientId,
    required String text,
  });

  /// 잠긴 사진 구매. 성공하면 잠금이 풀린 메시지를 돌려준다.
  Future<Either<Failure, ChatMessage>> unlock(int roomId, int serverId);
}
