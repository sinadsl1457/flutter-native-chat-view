import 'package:equatable/equatable.dart';

enum RenderKind { text, image, gift, notice, date }

enum RenderStatus { sending, sent, failed }

/// 네이티브 셀 하나에 그대로 대응하는 "그릴 준비가 끝난" 데이터.
///
/// 날짜 구분선, 프로필 생략, 시간 생략, 읽음 표시 같은 판단은 모두 Dart 에서 끝내고 결과만 넘긴다.
/// 네이티브(Kotlin/Swift)는 이 값을 그대로 그리기만 한다 — 같은 규칙을 세 언어로 중복 구현하지 않기 위해.
///
/// 값 비교([Equatable])가 곧 "셀을 다시 그려야 하는가"의 기준이 된다. (ChatListDiff 참고)
class ChatRenderItem extends Equatable {
  const ChatRenderItem({
    required this.key,
    required this.kind,
    this.isMine = false,
    this.groupStart = false,
    this.showAvatar = false,
    this.timeLabel,
    this.status = RenderStatus.sent,
    this.read = false,
    this.text,
    this.imageUrl,
    this.aspectRatio,
    this.locked = false,
    this.price,
    this.giftName,
    this.giftAmount,
  });

  final String key;
  final RenderKind kind;

  final bool isMine;

  /// 묶음의 첫 메시지 — 네이티브는 이 경우에만 위쪽 간격을 넓힌다.
  final bool groupStart;

  /// 상대 메시지 묶음의 첫 메시지에만 프로필 사진/닉네임을 그린다.
  final bool showAvatar;

  /// 같은 사람이 같은 분에 보낸 묶음의 마지막 메시지에만 시간을 그린다. null 이면 숨김.
  final String? timeLabel;

  final RenderStatus status;
  final bool read;

  /// text / notice 본문, date 구분선 라벨
  final String? text;

  final String? imageUrl;
  final double? aspectRatio;
  final bool locked;
  final int? price;

  final String? giftName;
  final int? giftAmount;

  Map<String, Object?> toWire() => {
    'key': key,
    'kind': kind.name,
    'isMine': isMine,
    'groupStart': groupStart,
    'showAvatar': showAvatar,
    'timeLabel': timeLabel,
    'status': status.name,
    'read': read,
    'text': text,
    'imageUrl': imageUrl,
    'aspectRatio': aspectRatio,
    'locked': locked,
    'price': price,
    'giftName': giftName,
    'giftAmount': giftAmount,
  };

  @override
  List<Object?> get props => [
    key,
    kind,
    isMine,
    groupStart,
    showAvatar,
    timeLabel,
    status,
    read,
    text,
    imageUrl,
    aspectRatio,
    locked,
    price,
    giftName,
    giftAmount,
  ];
}
