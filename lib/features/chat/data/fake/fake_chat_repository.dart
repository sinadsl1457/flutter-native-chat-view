import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_room_event.dart';
import '../../domain/repositories/chat_repository.dart';

/// 서버 없이 실행해 볼 수 있는 가짜 채팅 서버.
///
/// - 지난 사흘치 대화 150개 (텍스트·사진·잠긴 사진·선물·공지)
/// - 이전 메시지는 30개씩, 0.7초 지연
/// - 메시지를 보내면 0.5초 뒤 확정, 1초 뒤 상대가 읽음, 2초 뒤 상대 답장
/// - 본문에 "실패" 가 들어가면 전송 실패 (재전송 동작 확인용)
/// - 잠긴 사진 구매는 포인트 1,000 안에서만 성공
@LazySingleton(as: ChatRepository)
class FakeChatRepository implements ChatRepository {
  FakeChatRepository() {
    _history.addAll(_seed());
  }

  static const peerId = 7;
  static const myId = 0;

  final _history = <ChatMessage>[];
  final _events = StreamController<ChatRoomEvent>.broadcast();
  int _nextServerId = 10000;
  int _points = 1000;
  int _replyIndex = 0;

  @override
  Stream<ChatRoomEvent> events(int roomId) => _events.stream;

  @override
  Future<Either<Failure, MessagePage>> fetchLatest(
    int roomId, {
    int limit = 30,
  }) async {
    await _delay(400);
    final start = (_history.length - limit).clamp(0, _history.length);
    return Right(
      MessagePage(messages: _history.sublist(start), hasMore: start > 0),
    );
  }

  @override
  Future<Either<Failure, MessagePage>> fetchOlder(
    int roomId, {
    required int beforeServerId,
    int limit = 30,
  }) async {
    await _delay(700);
    final end = _history.indexWhere((m) => m.serverId == beforeServerId);
    if (end <= 0) return const Right(MessagePage(messages: [], hasMore: false));
    final start = (end - limit).clamp(0, end);
    return Right(
      MessagePage(messages: _history.sublist(start, end), hasMore: start > 0),
    );
  }

  @override
  Future<Either<Failure, ChatMessage>> sendText(
    int roomId, {
    required String clientId,
    required String text,
  }) async {
    await _delay(500);
    if (text.contains('실패')) {
      return const Left(NetworkFailure('simulated failure'));
    }

    final acked = ChatMessage(
      clientId: clientId,
      serverId: _nextServerId++,
      senderId: myId,
      isMine: true,
      createdAt: DateTime.now(),
      content: MessageContent.text(text),
    );
    _history.add(acked);

    Timer(const Duration(seconds: 1), () {
      _events.add(PeerReadUpTo(acked.serverId!));
    });
    Timer(const Duration(seconds: 2), _reply);
    return Right(acked);
  }

  @override
  Future<Either<Failure, ChatMessage>> unlock(int roomId, int serverId) async {
    await _delay(600);
    final index = _history.indexWhere((m) => m.serverId == serverId);
    if (index < 0) return const Left(ServerFailure('not found'));

    final message = _history[index];
    final content = message.content;
    if (content is! ImageContent || !content.locked) return Right(message);

    final price = content.price ?? 0;
    if (price > _points) {
      return const Left(
        ServerFailure('insufficient', code: 'INSUFFICIENT_POINTS'),
      );
    }
    _points -= price;
    final unlocked = message.copyWith(content: content.copyWith(locked: false));
    _history[index] = unlocked;
    return Right(unlocked);
  }

  // ---------------------------------------------------------------------------

  static const _replies = [
    '오 진짜요? ㅋㅋ',
    '오늘 촬영 끝나고 사진 보내드릴게요!',
    '고마워요!',
    '방금 라이브 끝났어요',
    '그거 저도 좋아해요',
  ];

  void _reply() {
    final text = _replies[_replyIndex++ % _replies.length];
    final message = ChatMessage(
      serverId: _nextServerId++,
      senderId: peerId,
      isMine: false,
      createdAt: DateTime.now(),
      content: MessageContent.text(text),
    );
    _history.add(message);
    _events.add(MessageReceived(message));
  }

  static Future<void> _delay(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  /// 결정적인(매번 같은) 대화 기록.
  static List<ChatMessage> _seed() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 2, 9);
    const lines = [
      '안녕하세요! 오늘도 응원해 주셔서 감사해요',
      '어제 방송 너무 재밌었어요',
      '다음 주 일정 나오면 제일 먼저 알려드릴게요',
      '점심 뭐 드셨어요?',
      '저는 방금 연습 끝났어요. 오늘은 좀 길었네요 ㅠㅠ 그래도 다음 무대 준비는 거의 다 됐어요',
      'ㅋㅋㅋㅋ',
      '네네',
    ];

    final messages = <ChatMessage>[];
    var time = start;
    var serverId = 1;

    ChatMessage make(MessageContent content, {required bool mine}) =>
        ChatMessage(
          serverId: serverId++,
          senderId: mine ? myId : peerId,
          isMine: mine,
          createdAt: time,
          content: content,
          readByPeer: mine,
        );

    messages.add(make(const MessageContent.notice('운영 정책상 외부 연락처 공유는 제한됩니다.'), mine: false));

    for (var i = 0; i < 150; i++) {
      // 같은 사람이 짧은 간격으로 2~3개 보내는 패턴을 섞어서 묶음 규칙이 드러나게 한다.
      final mine = (i ~/ 3).isOdd;
      time = time.add(Duration(minutes: i % 3 == 0 ? 17 : 0, seconds: 20));

      final MessageContent content;
      if (i % 23 == 5) {
        content = MessageContent.image(
          url: 'https://picsum.photos/seed/chat$i/600/800',
          aspectRatio: 0.75,
          locked: !mine,
          price: mine ? null : 300,
        );
      } else if (i % 31 == 12) {
        content = MessageContent.image(
          url: 'https://picsum.photos/seed/chat$i/800/600',
          aspectRatio: 4 / 3,
        );
      } else if (i % 37 == 20 && mine) {
        content = const MessageContent.gift(
          name: '커피 한 잔',
          imageUrl: 'https://picsum.photos/seed/gift/200/200',
          amount: 100,
        );
      } else {
        content = MessageContent.text(lines[i % lines.length]);
      }
      messages.add(make(content, mine: mine));
    }
    return messages;
  }
}
