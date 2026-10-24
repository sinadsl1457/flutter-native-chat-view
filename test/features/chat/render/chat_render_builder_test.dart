import 'package:flutter_test/flutter_test.dart';
import 'package:native_chat_view/features/chat/domain/entities/chat_message.dart';
import 'package:native_chat_view/features/chat/native_view/render/chat_render_builder.dart';
import 'package:native_chat_view/features/chat/native_view/render/chat_render_item.dart';

const me = 0;
const peer = 7;
var _id = 0;

ChatMessage msg(
  DateTime at, {
  int sender = peer,
  MessageContent content = const MessageContent.text('hi'),
  bool read = false,
  MessageStatus status = MessageStatus.sent,
}) => ChatMessage(
  serverId: ++_id,
  senderId: sender,
  isMine: sender == me,
  createdAt: at,
  content: content,
  readByPeer: read,
  status: status,
);

/// 날짜 구분선을 빼고 오래된 → 최신 순으로 돌려 보기 쉽게.
List<ChatRenderItem> messagesOnly(List<ChatRenderItem> items) =>
    items.reversed.where((i) => i.kind != RenderKind.date).toList();

void main() {
  setUp(() => _id = 0);

  final t = DateTime(2026, 10, 24, 15, 7);

  test('출력은 최신 → 오래된 순, 첫 메시지 앞에 날짜 구분선', () {
    final items = ChatRenderBuilder.build([
      msg(t),
      msg(t.add(const Duration(minutes: 5))),
    ]);

    expect(items.first.key, 's:2'); // 최신
    expect(items.last.kind, RenderKind.date); // 화면 맨 위
    expect(items.last.text, '2026년 10월 24일 토요일');
  });

  test('날짜가 바뀌면 구분선이 하나 더', () {
    final items = ChatRenderBuilder.build([
      msg(DateTime(2026, 10, 23, 23, 59)),
      msg(DateTime(2026, 10, 24, 0, 1)),
    ]);

    final dates = items.where((i) => i.kind == RenderKind.date).map((i) => i.key);
    expect(dates, ['d:2026-10-24', 'd:2026-10-23']);
  });

  test('같은 사람·같은 분 → 한 묶음: 프로필은 첫 메시지, 시간은 마지막 메시지에만', () {
    final items = messagesOnly(
      ChatRenderBuilder.build([
        msg(t),
        msg(t.add(const Duration(seconds: 20))),
        msg(t.add(const Duration(seconds: 40))),
      ]),
    );

    expect(items.map((i) => i.showAvatar), [true, false, false]);
    expect(items.map((i) => i.groupStart), [true, false, false]);
    expect(items.map((i) => i.timeLabel), [null, null, '오후 3:07']);
  });

  test('분이 바뀌거나 보낸 사람이 바뀌면 새 묶음', () {
    final items = messagesOnly(
      ChatRenderBuilder.build([
        msg(t),
        msg(t.add(const Duration(minutes: 1))),
        msg(t.add(const Duration(minutes: 1)), sender: me),
      ]),
    );

    expect(items.map((i) => i.groupStart), [true, true, true]);
    expect(items.map((i) => i.timeLabel != null), [true, true, true]);
    // 내 메시지에는 프로필이 없다
    expect(items.last.showAvatar, isFalse);
  });

  test('공지 다음 메시지는 새 묶음으로 시작', () {
    final items = messagesOnly(
      ChatRenderBuilder.build([
        msg(t),
        msg(t, content: const MessageContent.notice('공지')),
        msg(t),
      ]),
    );

    expect(items[1].kind, RenderKind.notice);
    expect(items[2].showAvatar, isTrue);
  });

  test('읽음은 내 묶음의 마지막 메시지에만', () {
    final items = messagesOnly(
      ChatRenderBuilder.build([
        msg(t, sender: me, read: true),
        msg(t, sender: me, read: true),
      ]),
    );

    expect(items.map((i) => i.read), [false, true]);
  });

  test('전송 상태와 콘텐츠 매핑', () {
    final items = messagesOnly(
      ChatRenderBuilder.build([
        msg(t, sender: me, status: MessageStatus.failed),
        msg(
          t.add(const Duration(minutes: 1)),
          content: const MessageContent.image(
            url: 'u',
            aspectRatio: 0.75,
            locked: true,
            price: 300,
          ),
        ),
      ]),
    );

    expect(items[0].status, RenderStatus.failed);
    expect(items[1].kind, RenderKind.image);
    expect(items[1].locked, isTrue);
    expect(items[1].price, 300);
  });

  test('시간 표기', () {
    expect(ChatRenderBuilder.formatTimeLabel(DateTime(2026, 1, 1, 0, 5)), '오전 12:05');
    expect(ChatRenderBuilder.formatTimeLabel(DateTime(2026, 1, 1, 9, 0)), '오전 9:00');
    expect(ChatRenderBuilder.formatTimeLabel(DateTime(2026, 1, 1, 12, 30)), '오후 12:30');
    expect(ChatRenderBuilder.formatTimeLabel(DateTime(2026, 1, 1, 23, 59)), '오후 11:59');
  });
}
