part of 'chat_cubit.dart';

@freezed
abstract class ChatState with _$ChatState {
  const ChatState._();

  const factory ChatState({
    required ChatPeer peer,

    /// 오래된 것 → 최신 순.
    @Default(<ChatMessage>[]) List<ChatMessage> messages,
    @Default(true) bool loadingInitial,
    @Default(false) bool loadingOlder,
    @Default(true) bool hasMoreOlder,

    /// 한 번만 보여줄 안내 (스낵바). 보여준 뒤 [ChatCubit.clearNotice].
    String? notice,
  }) = _ChatState;

  ChatMessage? byKey(String key) {
    for (final m in messages) {
      if (m.key == key) return m;
    }
    return null;
  }
}
