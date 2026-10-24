package dev.sintaek.nativechat.chat

/**
 * Dart `ChatRenderItem.toWire()` 와 1:1.
 * 묶음/시간/읽음 판단은 Dart 에서 끝난 값이다. 여기서는 그리기만 한다.
 */
data class ChatRenderItem(
    val key: String,
    val kind: Kind,
    val isMine: Boolean,
    val groupStart: Boolean,
    val showAvatar: Boolean,
    val timeLabel: String?,
    val status: Status,
    val read: Boolean,
    val text: String?,
    val imageUrl: String?,
    val aspectRatio: Double?,
    val locked: Boolean,
    val price: Int?,
    val giftName: String?,
    val giftAmount: Int?,
) {
    enum class Kind { TEXT, IMAGE, GIFT, NOTICE, DATE }

    enum class Status { SENDING, SENT, FAILED }

    companion object {
        fun fromWire(map: Map<*, *>): ChatRenderItem? {
            val key = map["key"] as? String ?: return null
            val kind = (map["kind"] as? String)?.let { raw ->
                Kind.entries.firstOrNull { it.name.equals(raw, ignoreCase = true) }
            } ?: return null

            return ChatRenderItem(
                key = key,
                kind = kind,
                isMine = map["isMine"] == true,
                groupStart = map["groupStart"] == true,
                showAvatar = map["showAvatar"] == true,
                timeLabel = map["timeLabel"] as? String,
                status = (map["status"] as? String)?.let { raw ->
                    Status.entries.firstOrNull { it.name.equals(raw, ignoreCase = true) }
                } ?: Status.SENT,
                read = map["read"] == true,
                text = map["text"] as? String,
                imageUrl = map["imageUrl"] as? String,
                aspectRatio = (map["aspectRatio"] as? Number)?.toDouble(),
                locked = map["locked"] == true,
                price = (map["price"] as? Number)?.toInt(),
                giftName = map["giftName"] as? String,
                giftAmount = (map["giftAmount"] as? Number)?.toInt(),
            )
        }

        fun listFromWire(raw: Any?): List<ChatRenderItem> =
            (raw as? List<*>).orEmpty().mapNotNull { (it as? Map<*, *>)?.let(::fromWire) }
    }
}

/** NativeChatViewConfig.toWire() */
data class ChatTheme(
    val peerNickname: String,
    val peerAvatarUrl: String?,
    val fontSizeSp: Float,
    val mineBubbleColor: Int,
    val peerBubbleColor: Int,
    val backgroundColor: Int,
    val readLabel: String,
    val failedLabel: String,
) {
    companion object {
        fun fromWire(map: Map<*, *>?): ChatTheme = ChatTheme(
            peerNickname = map?.get("peerNickname") as? String ?: "",
            peerAvatarUrl = map?.get("peerAvatarUrl") as? String,
            fontSizeSp = (map?.get("fontSize") as? Number)?.toFloat() ?: 15f,
            // Dart 의 ARGB32 는 Int 범위를 넘을 수 있어 Long 으로 온다 → 하위 32비트만 사용
            mineBubbleColor = (map?.get("mineBubbleColor") as? Number)?.toLong()?.toInt() ?: 0xFFE6007E.toInt(),
            peerBubbleColor = (map?.get("peerBubbleColor") as? Number)?.toLong()?.toInt() ?: 0xFFFFFFFF.toInt(),
            backgroundColor = (map?.get("backgroundColor") as? Number)?.toLong()?.toInt() ?: 0xFFF1F1F3.toInt(),
            readLabel = map?.get("readLabel") as? String ?: "읽음",
            failedLabel = map?.get("failedLabel") as? String ?: "전송 실패",
        )
    }
}
