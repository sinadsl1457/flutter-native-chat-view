import '../../domain/entities/chat_message.dart';
import 'chat_render_item.dart';

/// 도메인 메시지 목록 → 네이티브가 그릴 렌더 아이템 목록.
///
/// 출력은 **최신 → 오래된 순**이다. 네이티브 리스트가 뒤집힌(inverted) 리스트라서
/// index 0 이 화면 맨 아래에 그려진다. (Android `reverseLayout`, iOS 테이블 y축 반전)
/// 그래서 이전 메시지를 불러오면 배열 "끝"에 붙고, 새 메시지는 배열 "앞"에 붙는다.
///
/// 묶음 규칙 (실서비스 규칙 기반):
/// - 같은 사람이 같은 "분"에 연달아 보낸 메시지는 하나의 묶음
/// - 상대 묶음의 첫 메시지에만 프로필
/// - 묶음의 마지막 메시지에만 시간 (+ 내 메시지면 읽음)
/// - 공지 바로 다음 메시지는 새 묶음으로 시작
/// - 날짜가 바뀌면 날짜 구분선
abstract final class ChatRenderBuilder {
  static List<ChatRenderItem> build(List<ChatMessage> chronological) {
    final out = <ChatRenderItem>[];

    for (var i = 0; i < chronological.length; i++) {
      final current = chronological[i];
      final prev = i > 0 ? chronological[i - 1] : null;
      final next = i + 1 < chronological.length ? chronological[i + 1] : null;

      if (prev == null || !_sameDay(prev.createdAt, current.createdAt)) {
        out.add(
          ChatRenderItem(
            key: 'd:${_dayKey(current.createdAt)}',
            kind: RenderKind.date,
            text: formatDateLabel(current.createdAt),
          ),
        );
      }

      out.add(_item(current, prev: prev, next: next));
    }

    return out.reversed.toList(growable: false);
  }

  static ChatRenderItem _item(
    ChatMessage m, {
    required ChatMessage? prev,
    required ChatMessage? next,
  }) {
    final continuesPrev = prev != null && _sameGroup(prev, m);
    final continuesToNext = next != null && _sameGroup(m, next);
    final groupEnd = !continuesToNext;

    final status = switch (m.status) {
      MessageStatus.sending => RenderStatus.sending,
      MessageStatus.sent => RenderStatus.sent,
      MessageStatus.failed => RenderStatus.failed,
    };

    final base = ChatRenderItem(
      key: m.key,
      kind: RenderKind.text,
      isMine: m.isMine,
      groupStart: !continuesPrev,
      showAvatar: !m.isMine && !continuesPrev,
      timeLabel: groupEnd ? formatTimeLabel(m.createdAt) : null,
      status: status,
      read: m.isMine && m.readByPeer && groupEnd,
    );

    return switch (m.content) {
      TextContent(:final text) => base.copyWithContent(
        kind: RenderKind.text,
        text: text,
      ),
      ImageContent(:final url, :final aspectRatio, :final locked, :final price) =>
        base.copyWithContent(
          kind: RenderKind.image,
          imageUrl: url,
          aspectRatio: aspectRatio,
          locked: locked,
          price: price,
        ),
      GiftContent(:final name, :final imageUrl, :final amount) =>
        base.copyWithContent(
          kind: RenderKind.gift,
          imageUrl: imageUrl,
          giftName: name,
          giftAmount: amount,
        ),
      NoticeContent(:final text) => ChatRenderItem(
        key: m.key,
        kind: RenderKind.notice,
        text: text,
      ),
    };
  }

  static bool _sameGroup(ChatMessage a, ChatMessage b) =>
      a.content is! NoticeContent &&
      b.content is! NoticeContent &&
      a.senderId == b.senderId &&
      _sameMinute(a.createdAt, b.createdAt);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _sameMinute(DateTime a, DateTime b) =>
      _sameDay(a, b) && a.hour == b.hour && a.minute == b.minute;

  static String _dayKey(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String _two(int v) => v.toString().padLeft(2, '0');

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  /// 2026년 10월 24일 토요일
  static String formatDateLabel(DateTime d) =>
      '${d.year}년 ${d.month}월 ${d.day}일 ${_weekdays[d.weekday - 1]}요일';

  /// 오후 3:07
  static String formatTimeLabel(DateTime d) {
    final period = d.hour < 12 ? '오전' : '오후';
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$period $hour12:${_two(d.minute)}';
  }
}

extension on ChatRenderItem {
  ChatRenderItem copyWithContent({
    required RenderKind kind,
    String? text,
    String? imageUrl,
    double? aspectRatio,
    bool locked = false,
    int? price,
    String? giftName,
    int? giftAmount,
  }) => ChatRenderItem(
    key: key,
    kind: kind,
    isMine: isMine,
    groupStart: groupStart,
    showAvatar: showAvatar,
    timeLabel: timeLabel,
    status: status,
    read: read,
    text: text,
    imageUrl: imageUrl,
    aspectRatio: aspectRatio,
    locked: locked,
    price: price,
    giftName: giftName,
    giftAmount: giftAmount,
  );
}
