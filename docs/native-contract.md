# Dart ↔ 네이티브 계약

`NativeChatView` 하나 = PlatformView 하나 = 채널 하나.

| 항목 | 값 |
|---|---|
| viewType | `native_chat_view` |
| MethodChannel | `native_chat_view/<viewId>` (Dart 는 `onPlatformViewCreated` 의 id 로 생성) |
| creationParams codec | `StandardMessageCodec` — iOS 는 팩토리의 `createArgsCodec()` 를 구현해야 params 가 전달된다 |

## creationParams

```jsonc
{
  "config": {
    "peerNickname": "하린",
    "peerAvatarUrl": "https://…",
    "fontSize": 15,
    "mineBubbleColor": 4293263486,   // Color.toARGB32() — Android 에선 Long 으로 온다
    "peerBubbleColor": 4294967295,
    "backgroundColor": 4294046195,
    "readLabel": "읽음",
    "failedLabel": "전송 실패"
  },
  "initialItems": [ /* RenderItem[] 최신 → 오래된 순 */ ],
  "hasMoreOlder": true
}
```

## RenderItem

```jsonc
{
  "key": "c:3f2a…",          // 내 메시지: c:<clientId> / 받은 메시지: s:<serverId> / 날짜: d:2026-10-24
  "kind": "text",            // text | image | gift | notice | date
  "isMine": true,
  "groupStart": true,        // 묶음 첫 메시지 → 위쪽 간격 넓게
  "showAvatar": false,       // 상대 묶음 첫 메시지만 true
  "timeLabel": "오후 3:07",   // null 이면 숨김 (묶음 마지막만 값이 있음)
  "status": "sent",          // sending | sent | failed
  "read": true,
  "text": "안녕",             // text / notice 본문, date 라벨
  "imageUrl": null, "aspectRatio": null, "locked": false, "price": null,
  "giftName": null, "giftAmount": null
}
```

## Dart → 네이티브

| method | args | 설명 |
|---|---|---|
| `applyPatch` | `{type: "reset", items, stickToBottom}` | 전체 교체 |
| `applyPatch` | `{type: "ops", ops, stickToBottom}` | 아래 op 를 **순서대로** 적용 |
| `setOlderState` | `{loading, hasMore}` | 상단 로딩 표시 / 추가 요청 중단 |
| `scrollToBottom` | `{animated}` | |

op (index 는 앞선 op 가 적용된 직후 목록 기준):

```jsonc
{"op": "insert", "index": 0, "items": [RenderItem, …]}
{"op": "remove", "index": 3, "count": 2}
{"op": "update", "index": 1, "item": RenderItem}
```

`stickToBottom: true` 면 무조건 맨 아래로. 아니면 네이티브가 "이미 맨 아래를 보고 있었고 index 0 에 삽입된 경우"에만 따라 내려간다.

## 네이티브 → Dart

| method | args |
|---|---|
| `onLoadOlder` | – |
| `onAtBottomChanged` | `{atBottom: bool}` |
| `onTapMessage` | `{key}` |
| `onTapLocked` | `{key}` |
| `onTapRetry` | `{key}` |
| `onTapAvatar` | – |
| `onTapBackground` | – |

이벤트에는 index 가 아니라 **key** 를 담는다. index 는 이후 삽입/삭제로 바뀌기 때문.
