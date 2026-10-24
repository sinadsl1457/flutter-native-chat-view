import 'package:flutter_test/flutter_test.dart';
import 'package:native_chat_view/features/chat/native_view/render/chat_list_diff.dart';
import 'package:native_chat_view/features/chat/native_view/render/chat_render_item.dart';

ChatRenderItem item(String key, {String? text, String? time}) => ChatRenderItem(
  key: key,
  kind: RenderKind.text,
  text: text ?? key,
  timeLabel: time,
);

List<String> keys(List<ChatRenderItem> items) => [for (final i in items) i.key];

void main() {
  void expectRoundTrip(List<ChatRenderItem> before, List<ChatRenderItem> after) {
    final patch = ChatListDiff.compute(before, after);
    expect(ChatListDiff.apply(before, patch), after);
  }

  test('변경이 없으면 op 도 없다', () {
    final list = [item('a'), item('b')];
    final patch = ChatListDiff.compute(list, List.of(list));

    expect(patch, isA<OpsPatch>());
    expect((patch as OpsPatch).isEmpty, isTrue);
  });

  test('새 메시지(index 0) + 직전 메시지의 시간 표시가 사라지는 경우', () {
    // 최신 → 오래된 순. 같은 분에 연달아 보내면 이전 메시지의 시간이 숨겨진다.
    final before = [item('m2', time: '오후 3:00'), item('m1')];
    final after = [item('m3', time: '오후 3:00'), item('m2'), item('m1')];

    final patch = ChatListDiff.compute(before, after) as OpsPatch;

    expect(patch.ops, hasLength(2));
    expect(patch.ops[0], isA<InsertOp>().having((o) => o.index, 'index', 0));
    expect(patch.ops[1], isA<UpdateOp>().having((o) => o.index, 'index', 1));
    expectRoundTrip(before, after);
  });

  test('이전 메시지 불러오기는 끝에 삽입 하나로 끝난다', () {
    final before = [item('m3'), item('m2')];
    final after = [item('m3'), item('m2'), item('m1'), item('m0')];

    final patch = ChatListDiff.compute(before, after) as OpsPatch;

    expect(patch.ops, hasLength(1));
    final insert = patch.ops.single as InsertOp;
    expect(insert.index, 2);
    expect(keys(insert.items), ['m1', 'm0']);
  });

  test('전송 확인(ack)은 키가 같으므로 제자리 update', () {
    final before = [item('c:1', text: '안녕')];
    final after = [item('c:1', text: '안녕', time: '오전 9:00')];

    final patch = ChatListDiff.compute(before, after) as OpsPatch;

    expect(patch.ops.single, isA<UpdateOp>().having((o) => o.index, 'index', 0));
  });

  test('연속 삭제는 범위 하나로 묶는다', () {
    final before = [item('a'), item('b'), item('c'), item('d')];
    final after = [item('a'), item('d')];

    final patch = ChatListDiff.compute(before, after) as OpsPatch;

    expect(patch.ops.single, isA<RemoveOp>()
        .having((o) => o.index, 'index', 1)
        .having((o) => o.count, 'count', 2));
  });

  test('삭제·삽입·변경이 섞여도 순서대로 적용하면 결과가 같다', () {
    final before = [item('n1'), item('a'), item('b'), item('c'), item('d')];
    final after = [
      item('n3'),
      item('n2'),
      item('a', text: 'changed'),
      item('c'),
      item('x'),
      item('d'),
      item('o1'),
    ];

    expectRoundTrip(before, after);
    expect(ChatListDiff.compute(before, after), isA<OpsPatch>());
  });

  test('공통 키의 순서가 바뀌면 증분 적용이 불가능 — reset', () {
    final patch = ChatListDiff.compute(
      [item('a'), item('b')],
      [item('b'), item('a')],
    );

    expect(patch, isA<ResetPatch>());
  });

  test('키가 중복되면 reset', () {
    final patch = ChatListDiff.compute([item('a')], [item('a'), item('a')]);

    expect(patch, isA<ResetPatch>());
  });

  test('빈 목록에서 시작 / 빈 목록으로 끝', () {
    expectRoundTrip([], [item('a'), item('b')]);
    expectRoundTrip([item('a'), item('b')], []);
  });

  test('wire 형식', () {
    final patch = ChatListDiff.compute([item('a')], [item('b'), item('a')]) as OpsPatch;

    expect(patch.ops.single.toWire(), {
      'op': 'insert',
      'index': 0,
      'items': [item('b').toWire()],
    });
  });
}
