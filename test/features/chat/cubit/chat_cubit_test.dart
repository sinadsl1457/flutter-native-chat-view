import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:native_chat_view/core/error/failure.dart';
import 'package:native_chat_view/features/chat/domain/entities/chat_message.dart';
import 'package:native_chat_view/features/chat/domain/entities/chat_room_event.dart';
import 'package:native_chat_view/features/chat/domain/repositories/chat_repository.dart';
import 'package:native_chat_view/features/chat/domain/usecases/chat_usecases.dart';
import 'package:native_chat_view/features/chat/presentation/cubit/chat_cubit.dart';

class _MockLoadLatest extends Mock implements LoadLatestMessages {}

class _MockLoadOlder extends Mock implements LoadOlderMessages {}

class _MockSendText extends Mock implements SendTextMessage {}

class _MockUnlock extends Mock implements UnlockMessage {}

class _MockRepository extends Mock implements ChatRepository {}

class _FixedLocal implements LocalMessageFactory {
  var _n = 0;

  @override
  String newClientId() => 'local-${++_n}';

  @override
  DateTime now() => DateTime(2026, 10, 24, 12);
}

const peer = ChatPeer(id: 7, nickname: '하린');

ChatMessage server(int id, {bool mine = false, int minute = 0, MessageContent? content}) =>
    ChatMessage(
      serverId: id,
      senderId: mine ? 0 : 7,
      isMine: mine,
      createdAt: DateTime(2026, 10, 24, 11, minute),
      content: content ?? MessageContent.text('m$id'),
    );

void main() {
  late _MockLoadLatest loadLatest;
  late _MockLoadOlder loadOlder;
  late _MockSendText sendText;
  late _MockUnlock unlock;
  late _MockRepository repository;
  late StreamController<ChatRoomEvent> events;

  setUpAll(() {
    registerFallbackValue(const LoadOlderParams(roomId: 0, beforeServerId: 0));
    registerFallbackValue(const SendTextParams(roomId: 0, clientId: '', text: ''));
    registerFallbackValue(const UnlockParams(roomId: 0, serverId: 0));
  });

  setUp(() {
    loadLatest = _MockLoadLatest();
    loadOlder = _MockLoadOlder();
    sendText = _MockSendText();
    unlock = _MockUnlock();
    repository = _MockRepository();
    events = StreamController<ChatRoomEvent>.broadcast();

    when(() => repository.events(any())).thenAnswer((_) => events.stream);
    when(() => loadLatest.call(any())).thenAnswer(
      (_) async => Right(MessagePage(messages: [server(1), server(2, minute: 1)], hasMore: true)),
    );
  });

  tearDown(() => events.close());

  ChatCubit build() => ChatCubit(
    loadLatest,
    loadOlder,
    sendText,
    unlock,
    repository,
    _FixedLocal(),
    1,
    peer,
  );

  List<String> keysOf(ChatState s) => [for (final m in s.messages) m.key];

  blocTest<ChatCubit, ChatState>(
    'start: 최신 메시지를 불러온다',
    build: build,
    act: (cubit) => cubit.start(),
    expect: () => [
      isA<ChatState>()
          .having((s) => s.loadingInitial, 'loadingInitial', false)
          .having(keysOf, 'keys', ['s:1', 's:2'])
          .having((s) => s.hasMoreOlder, 'hasMoreOlder', true),
    ],
  );

  blocTest<ChatCubit, ChatState>(
    '보내기: 먼저 sending 으로 보이고, ack 후 같은 키로 sent',
    setUp: () => when(() => sendText.call(any())).thenAnswer(
      (_) async => Right(
        ChatMessage(
          clientId: 'local-1',
          serverId: 3,
          senderId: 0,
          isMine: true,
          createdAt: DateTime(2026, 10, 24, 12),
          content: const MessageContent.text('안녕'),
        ),
      ),
    ),
    build: build,
    act: (cubit) async {
      await cubit.start();
      await cubit.sendText('  안녕  ');
    },
    skip: 1,
    expect: () => [
      isA<ChatState>()
          .having((s) => s.messages.last.key, 'key', 'c:local-1')
          .having((s) => s.messages.last.status, 'status', MessageStatus.sending),
      isA<ChatState>()
          .having((s) => s.messages.last.key, 'key', 'c:local-1')
          .having((s) => s.messages.last.serverId, 'serverId', 3)
          .having((s) => s.messages.last.status, 'status', MessageStatus.sent),
    ],
    verify: (_) {
      final params = verify(() => sendText.call(captureAny())).captured.single as SendTextParams;
      expect(params.text, '안녕');
    },
  );

  blocTest<ChatCubit, ChatState>(
    '전송 실패 → failed, 재전송 → 같은 clientId 로 다시 시도',
    setUp: () {
      var attempt = 0;
      when(() => sendText.call(any())).thenAnswer((invocation) async {
        attempt++;
        if (attempt == 1) return const Left(NetworkFailure('offline'));
        final p = invocation.positionalArguments.first as SendTextParams;
        return Right(
          ChatMessage(
            clientId: p.clientId,
            serverId: 3,
            senderId: 0,
            isMine: true,
            createdAt: DateTime(2026, 10, 24, 12),
            content: MessageContent.text(p.text),
          ),
        );
      });
    },
    build: build,
    act: (cubit) async {
      await cubit.start();
      await cubit.sendText('hi');
      await cubit.retry('c:local-1');
    },
    skip: 1,
    expect: () => [
      isA<ChatState>().having((s) => s.messages.last.status, 'status', MessageStatus.sending),
      isA<ChatState>().having((s) => s.messages.last.status, 'status', MessageStatus.failed),
      isA<ChatState>().having((s) => s.messages.last.status, 'status', MessageStatus.sending),
      isA<ChatState>()
          .having((s) => s.messages.last.status, 'status', MessageStatus.sent)
          .having((s) => s.messages.length, 'length', 3),
    ],
  );

  blocTest<ChatCubit, ChatState>(
    '이전 메시지는 앞에 붙고, 더 없으면 hasMoreOlder=false',
    setUp: () => when(() => loadOlder.call(any())).thenAnswer(
      (_) async => Right(MessagePage(messages: [server(0)], hasMore: false)),
    ),
    build: build,
    act: (cubit) async {
      await cubit.start();
      await cubit.loadOlder();
      await cubit.loadOlder(); // hasMore=false 이므로 무시
    },
    skip: 1,
    expect: () => [
      isA<ChatState>().having((s) => s.loadingOlder, 'loadingOlder', true),
      isA<ChatState>()
          .having((s) => s.loadingOlder, 'loadingOlder', false)
          .having(keysOf, 'keys', ['s:0', 's:1', 's:2'])
          .having((s) => s.hasMoreOlder, 'hasMoreOlder', false),
    ],
    verify: (_) {
      final params = verify(() => loadOlder.call(captureAny())).captured.single as LoadOlderParams;
      expect(params.beforeServerId, 1);
    },
  );

  blocTest<ChatCubit, ChatState>(
    '실시간 수신 + 상대 읽음',
    setUp: () => when(() => loadLatest.call(any())).thenAnswer(
      (_) async => Right(
        MessagePage(messages: [server(1, mine: true), server(2, mine: true, minute: 1)], hasMore: false),
      ),
    ),
    build: build,
    act: (cubit) async {
      await cubit.start();
      events.add(const PeerReadUpTo(1));
      await pumpEventQueue();
      events.add(MessageReceived(server(3, minute: 2)));
    },
    skip: 1,
    expect: () => [
      isA<ChatState>().having(
        (s) => s.messages.map((m) => m.readByPeer).toList(),
        'read',
        [true, false],
      ),
      isA<ChatState>().having(keysOf, 'keys', ['s:1', 's:2', 's:3']),
    ],
  );

  blocTest<ChatCubit, ChatState>(
    '잠긴 사진 구매 실패(포인트 부족) → 안내',
    setUp: () {
      when(() => loadLatest.call(any())).thenAnswer(
        (_) async => Right(
          MessagePage(
            messages: [
              server(1, content: const MessageContent.image(url: 'u', aspectRatio: 1, locked: true, price: 5000)),
            ],
            hasMore: false,
          ),
        ),
      );
      when(() => unlock.call(any())).thenAnswer(
        (_) async => const Left(ServerFailure('no', code: 'INSUFFICIENT_POINTS')),
      );
    },
    build: build,
    act: (cubit) async {
      await cubit.start();
      await cubit.unlock('s:1');
    },
    skip: 1,
    expect: () => [
      isA<ChatState>().having((s) => s.notice, 'notice', '포인트가 부족합니다.'),
    ],
  );
}
