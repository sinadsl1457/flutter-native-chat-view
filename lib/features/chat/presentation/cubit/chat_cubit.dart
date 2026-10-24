import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/log.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_room_event.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/usecases/chat_usecases.dart';

part 'chat_cubit.freezed.dart';
part 'chat_state.dart';

/// 로컬 메시지 생성에 필요한 id·시각. 테스트에서 고정값으로 바꾸기 위해 분리.
@lazySingleton
class LocalMessageFactory {
  String newClientId() => const Uuid().v4();

  DateTime now() => DateTime.now();
}

/// 채팅방 하나의 메시지 상태. **메시지 목록의 단일 출처는 Dart 다.**
///
/// 네이티브 리스트는 이 상태를 렌더 아이템으로 바꾼 결과를 diff 로 받아 그리기만 한다.
/// (실서비스 버전은 네이티브도 자체 메시지 배열을 들고 tempId 매칭·병합을 따로 했다)
@injectable
class ChatCubit extends Cubit<ChatState> {
  ChatCubit(
    this._loadLatest,
    this._loadOlder,
    this._sendText,
    this._unlock,
    this._repository,
    this._local,
    @factoryParam this.roomId,
    @factoryParam ChatPeer peer,
  ) : super(ChatState(peer: peer));

  static const _tag = 'ChatCubit';
  static const _unsent = 1 << 62;

  final LoadLatestMessages _loadLatest;
  final LoadOlderMessages _loadOlder;
  final SendTextMessage _sendText;
  final UnlockMessage _unlock;
  final ChatRepository _repository;
  final LocalMessageFactory _local;
  final int roomId;

  StreamSubscription<ChatRoomEvent>? _eventsSub;

  Future<void> start() async {
    // 최신 목록을 받는 사이에 들어온 실시간 메시지도 놓치지 않도록 구독을 먼저 건다.
    _eventsSub = _repository.events(roomId).listen(_onRoomEvent);

    final result = await _loadLatest(roomId);
    if (isClosed) return;
    result.fold(
      (failure) => emit(
        state.copyWith(
          loadingInitial: false,
          notice: '메시지를 불러오지 못했습니다.',
        ),
      ),
      (page) => emit(
        state.copyWith(
          loadingInitial: false,
          messages: _merge(state.messages, page.messages),
          hasMoreOlder: page.hasMore,
        ),
      ),
    );
  }

  Future<void> loadOlder() async {
    if (state.loadingInitial || state.loadingOlder || !state.hasMoreOlder) return;
    final oldestServerId = _oldestServerId();
    if (oldestServerId == null) return;

    emit(state.copyWith(loadingOlder: true));
    final result = await _loadOlder(
      LoadOlderParams(roomId: roomId, beforeServerId: oldestServerId),
    );
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(loadingOlder: false)),
      (page) => emit(
        state.copyWith(
          loadingOlder: false,
          hasMoreOlder: page.hasMore,
          messages: _merge(state.messages, page.messages),
        ),
      ),
    );
  }

  Future<void> sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;

    final message = ChatMessage(
      clientId: _local.newClientId(),
      senderId: _myId,
      isMine: true,
      createdAt: _local.now(),
      content: MessageContent.text(text),
      status: MessageStatus.sending,
    );
    // 서버 응답 전에 먼저 보여준다 (optimistic).
    emit(state.copyWith(messages: [...state.messages, message]));
    await _deliver(message.clientId!, text);
  }

  Future<void> retry(String key) async {
    final message = state.byKey(key);
    if (message == null || message.status != MessageStatus.failed) return;
    final content = message.content;
    if (content is! TextContent) return;

    _replace(message.copyWith(status: MessageStatus.sending));
    await _deliver(message.clientId!, content.text);
  }

  Future<void> unlock(String key) async {
    final serverId = state.byKey(key)?.serverId;
    if (serverId == null) return;

    final result = await _unlock(UnlockParams(roomId: roomId, serverId: serverId));
    if (isClosed) return;
    result.fold(
      (failure) => emit(
        state.copyWith(
          notice: failure is ServerFailure && failure.code == 'INSUFFICIENT_POINTS'
              ? '포인트가 부족합니다.'
              : '구매하지 못했습니다. 잠시 후 다시 시도해 주세요.',
        ),
      ),
      (updated) => _upsert(updated),
    );
  }

  void clearNotice() => emit(state.copyWith(notice: null));

  // ---------------------------------------------------------------------------

  /// 데모에서는 내 id 를 고정. 실서비스에서는 세션에서 가져온다.
  int get _myId => 0;

  Future<void> _deliver(String clientId, String text) async {
    final result = await _sendText(
      SendTextParams(roomId: roomId, clientId: clientId, text: text),
    );
    if (isClosed) return;

    final key = 'c:$clientId';
    result.fold(
      (failure) {
        Log.w(_tag, 'send failed: $failure');
        final current = state.byKey(key);
        if (current != null) {
          _replace(current.copyWith(status: MessageStatus.failed));
        }
      },
      // 서버가 확정한 메시지 (serverId, 서버 시각). clientId 가 같으므로 키도 같다 → 제자리 교체.
      (acked) => _upsert(acked.copyWith(status: MessageStatus.sent)),
    );
  }

  void _onRoomEvent(ChatRoomEvent event) {
    if (isClosed) return;
    switch (event) {
      case MessageReceived(:final message) || MessageUpdated(:final message):
        _upsert(message);
      case PeerReadUpTo(:final serverId):
        bool becomesRead(ChatMessage m) =>
            m.isMine &&
            !m.readByPeer &&
            m.serverId != null &&
            m.serverId! <= serverId;

        if (!state.messages.any(becomesRead)) return;
        emit(
          state.copyWith(
            messages: [
              for (final m in state.messages)
                becomesRead(m) ? m.copyWith(readByPeer: true) : m,
            ],
          ),
        );
    }
  }

  int? _oldestServerId() {
    for (final m in state.messages) {
      if (m.serverId != null) return m.serverId;
    }
    return null;
  }

  void _replace(ChatMessage message) {
    emit(
      state.copyWith(
        messages: [
          for (final m in state.messages) m.key == message.key ? message : m,
        ],
      ),
    );
  }

  void _upsert(ChatMessage message) =>
      emit(state.copyWith(messages: _merge(state.messages, [message])));

  /// 키 기준 병합 + 시간순 정렬. 같은 키면 새 값으로 교체한다.
  static List<ChatMessage> _merge(
    List<ChatMessage> current,
    List<ChatMessage> incoming,
  ) {
    final byKey = <String, ChatMessage>{
      for (final m in current) m.key: m,
      for (final m in incoming) m.key: m,
    };
    final merged = byKey.values.toList()..sort(_chronological);
    return merged;
  }

  static int _chronological(ChatMessage a, ChatMessage b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    if (byTime != 0) return byTime;
    // 같은 시각이면 서버 순서. 아직 서버 id 가 없는(전송 중) 메시지는 뒤로.
    return (a.serverId ?? _unsent).compareTo(b.serverId ?? _unsent);
  }

  @override
  Future<void> close() async {
    await _eventsSub?.cancel();
    return super.close();
  }
}
