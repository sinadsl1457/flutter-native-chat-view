import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../entities/chat_message.dart';
import '../entities/chat_room_event.dart';
import '../repositories/chat_repository.dart';

@injectable
class LoadLatestMessages implements UseCase<int, MessagePage> {
  LoadLatestMessages(this._repository);

  final ChatRepository _repository;

  @override
  Future<Either<Failure, MessagePage>> call(int roomId) =>
      _repository.fetchLatest(roomId, limit: 30);
}

class LoadOlderParams {
  const LoadOlderParams({required this.roomId, required this.beforeServerId});

  final int roomId;
  final int beforeServerId;
}

@injectable
class LoadOlderMessages implements UseCase<LoadOlderParams, MessagePage> {
  LoadOlderMessages(this._repository);

  final ChatRepository _repository;

  @override
  Future<Either<Failure, MessagePage>> call(LoadOlderParams input) =>
      _repository.fetchOlder(
        input.roomId,
        beforeServerId: input.beforeServerId,
        limit: 30,
      );
}

class SendTextParams {
  const SendTextParams({
    required this.roomId,
    required this.clientId,
    required this.text,
  });

  final int roomId;
  final String clientId;
  final String text;
}

@injectable
class SendTextMessage implements UseCase<SendTextParams, ChatMessage> {
  SendTextMessage(this._repository);

  final ChatRepository _repository;

  @override
  Future<Either<Failure, ChatMessage>> call(SendTextParams input) =>
      _repository.sendText(
        input.roomId,
        clientId: input.clientId,
        text: input.text,
      );
}

class UnlockParams {
  const UnlockParams({required this.roomId, required this.serverId});

  final int roomId;
  final int serverId;
}

@injectable
class UnlockMessage implements UseCase<UnlockParams, ChatMessage> {
  UnlockMessage(this._repository);

  final ChatRepository _repository;

  @override
  Future<Either<Failure, ChatMessage>> call(UnlockParams input) =>
      _repository.unlock(input.roomId, input.serverId);
}
