import 'chat_render_item.dart';

/// 네이티브 리스트에 순서대로 적용할 변경 명령.
///
/// index 는 **앞선 명령이 적용된 직후의 리스트 기준**이다. 네이티브는 받은 순서대로
/// 배열을 고치고 같은 위치로 notifyItemRange*/insertRows 를 호출하면 된다.
sealed class ChatListOp {
  const ChatListOp();

  Map<String, Object?> toWire();
}

final class InsertOp extends ChatListOp {
  const InsertOp(this.index, this.items);

  final int index;
  final List<ChatRenderItem> items;

  @override
  Map<String, Object?> toWire() => {
    'op': 'insert',
    'index': index,
    'items': [for (final item in items) item.toWire()],
  };

  @override
  String toString() => 'Insert($index, ${items.map((e) => e.key).toList()})';
}

final class RemoveOp extends ChatListOp {
  const RemoveOp(this.index, this.count);

  final int index;
  final int count;

  @override
  Map<String, Object?> toWire() => {'op': 'remove', 'index': index, 'count': count};

  @override
  String toString() => 'Remove($index, $count)';
}

final class UpdateOp extends ChatListOp {
  const UpdateOp(this.index, this.item);

  final int index;
  final ChatRenderItem item;

  @override
  Map<String, Object?> toWire() => {
    'op': 'update',
    'index': index,
    'item': item.toWire(),
  };

  @override
  String toString() => 'Update($index, ${item.key})';
}

sealed class ChatListPatch {
  const ChatListPatch();
}

/// 순서가 뒤바뀐 경우 등 증분 적용이 불가능할 때 — 전체 교체.
final class ResetPatch extends ChatListPatch {
  const ResetPatch(this.items);

  final List<ChatRenderItem> items;
}

final class OpsPatch extends ChatListPatch {
  const OpsPatch(this.ops);

  final List<ChatListOp> ops;

  bool get isEmpty => ops.isEmpty;
}

/// 이전에 네이티브로 보낸 목록과 새 목록을 비교해 최소한의 변경만 만든다.
///
/// 채팅 목록의 특성을 이용한 O(n) 비교다:
/// 메시지는 삽입·삭제·내용 변경은 있어도, 서로의 **상대 순서가 바뀌지 않는다.**
/// (새 메시지는 앞에, 이전 메시지는 뒤에, ack·읽음·잠금 해제는 제자리에서 내용만 변경)
/// 그래서 두 목록을 앞에서부터 한 번씩만 훑으면 된다. 일반적인 LCS(O(n·m))가 필요 없다.
///
/// 만약 공통 키의 순서가 다르면(정렬 기준 변경 등) 가정이 깨진 것이므로 [ResetPatch] 를 낸다.
abstract final class ChatListDiff {
  static ChatListPatch compute(
    List<ChatRenderItem> previous,
    List<ChatRenderItem> next,
  ) {
    final previousKeys = {for (final item in previous) item.key};
    final nextKeys = {for (final item in next) item.key};
    if (previousKeys.length != previous.length || nextKeys.length != next.length) {
      // 키 중복 — 증분 적용 시 위치를 특정할 수 없다.
      return ResetPatch(next);
    }
    if (!_commonOrderPreserved(previous, next, previousKeys, nextKeys)) {
      return ResetPatch(next);
    }

    final ops = <ChatListOp>[];
    var i = 0; // previous
    var j = 0; // next
    var cursor = 0; // 변경이 적용되고 있는 리스트에서의 현재 위치

    while (i < previous.length || j < next.length) {
      if (i < previous.length && !nextKeys.contains(previous[i].key)) {
        final start = i;
        while (i < previous.length && !nextKeys.contains(previous[i].key)) {
          i++;
        }
        ops.add(RemoveOp(cursor, i - start));
        continue;
      }

      if (j < next.length && !previousKeys.contains(next[j].key)) {
        final start = j;
        while (j < next.length && !previousKeys.contains(next[j].key)) {
          j++;
        }
        ops.add(InsertOp(cursor, next.sublist(start, j)));
        cursor += j - start;
        continue;
      }

      // 여기 오면 previous[i], next[j] 는 같은 키다 (순서 보존을 위에서 확인했으므로).
      if (previous[i] != next[j]) {
        ops.add(UpdateOp(cursor, next[j]));
      }
      i++;
      j++;
      cursor++;
    }

    return OpsPatch(ops);
  }

  static bool _commonOrderPreserved(
    List<ChatRenderItem> previous,
    List<ChatRenderItem> next,
    Set<String> previousKeys,
    Set<String> nextKeys,
  ) {
    final a = [for (final item in previous) if (nextKeys.contains(item.key)) item.key];
    final b = [for (final item in next) if (previousKeys.contains(item.key)) item.key];
    if (a.length != b.length) return false;
    for (var k = 0; k < a.length; k++) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  /// 테스트/디버깅용: [ops] 를 [previous] 에 적용한 결과.
  /// 네이티브가 하는 일과 똑같은 순서로 적용한다.
  static List<ChatRenderItem> apply(
    List<ChatRenderItem> previous,
    ChatListPatch patch,
  ) {
    switch (patch) {
      case ResetPatch(:final items):
        return List.of(items);
      case OpsPatch(:final ops):
        final list = List.of(previous);
        for (final op in ops) {
          switch (op) {
            case InsertOp(:final index, :final items):
              list.insertAll(index, items);
            case RemoveOp(:final index, :final count):
              list.removeRange(index, index + count);
            case UpdateOp(:final index, :final item):
              list[index] = item;
          }
        }
        return list;
    }
  }
}
