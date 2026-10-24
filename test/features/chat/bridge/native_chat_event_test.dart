import 'package:flutter_test/flutter_test.dart';
import 'package:native_chat_view/features/chat/native_view/bridge/native_chat_event.dart';

void main() {
  test('콜백 이름 → 이벤트', () {
    expect(NativeChatEvent.fromCall('onLoadOlder', null), isA<LoadOlderRequested>());
    expect(NativeChatEvent.fromCall('onTapBackground', null), isA<BackgroundTapped>());
    expect(NativeChatEvent.fromCall('onTapAvatar', null), isA<AvatarTapped>());

    final locked = NativeChatEvent.fromCall('onTapLocked', {'key': 's:3'});
    expect(locked, isA<LockedMessageTapped>().having((e) => e.key, 'key', 's:3'));

    final bottom = NativeChatEvent.fromCall('onAtBottomChanged', {'atBottom': false});
    expect(bottom, isA<AtBottomChanged>().having((e) => e.atBottom, 'atBottom', false));
  });

  test('key 가 필요한 이벤트에 key 가 없으면 무시', () {
    expect(NativeChatEvent.fromCall('onTapMessage', {}), isNull);
    expect(NativeChatEvent.fromCall('onTapRetry', null), isNull);
  });

  test('모르는 콜백은 무시', () {
    expect(NativeChatEvent.fromCall('somethingNew', {'key': 'a'}), isNull);
  });
}
