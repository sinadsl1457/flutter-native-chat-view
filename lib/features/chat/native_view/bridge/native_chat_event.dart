/// 네이티브 리스트 → Dart 이벤트.
sealed class NativeChatEvent {
  const NativeChatEvent();

  static NativeChatEvent? fromCall(String method, Object? arguments) {
    final args = arguments is Map ? arguments : const {};
    final key = args['key'] as String?;

    return switch (method) {
      'onLoadOlder' => const LoadOlderRequested(),
      'onTapAvatar' => const AvatarTapped(),
      'onTapBackground' => const BackgroundTapped(),
      'onAtBottomChanged' => AtBottomChanged(args['atBottom'] == true),
      'onTapMessage' when key != null => MessageTapped(key),
      'onTapLocked' when key != null => LockedMessageTapped(key),
      'onTapRetry' when key != null => RetryTapped(key),
      _ => null,
    };
  }
}

/// 화면 맨 위(가장 오래된 메시지) 근처까지 스크롤됨.
final class LoadOlderRequested extends NativeChatEvent {
  const LoadOlderRequested();
}

final class AvatarTapped extends NativeChatEvent {
  const AvatarTapped();
}

/// 메시지가 아닌 빈 영역 탭 — 키보드 내리기 용도.
final class BackgroundTapped extends NativeChatEvent {
  const BackgroundTapped();
}

/// 사용자가 위로 스크롤해 최신 메시지가 안 보이는 상태인지. "새 메시지" 버튼 표시에 쓴다.
final class AtBottomChanged extends NativeChatEvent {
  const AtBottomChanged(this.atBottom);

  final bool atBottom;
}

final class MessageTapped extends NativeChatEvent {
  const MessageTapped(this.key);

  final String key;
}

final class LockedMessageTapped extends NativeChatEvent {
  const LockedMessageTapped(this.key);

  final String key;
}

final class RetryTapped extends NativeChatEvent {
  const RetryTapped(this.key);

  final String key;
}
