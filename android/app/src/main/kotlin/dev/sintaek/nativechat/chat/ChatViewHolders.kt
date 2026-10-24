package dev.sintaek.nativechat.chat

import android.content.res.ColorStateList
import android.graphics.Color
import android.util.TypedValue
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.view.updatePaddingRelative
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import dev.sintaek.nativechat.R

interface ChatItemListener {
    fun onTapMessage(item: ChatRenderItem)
    fun onTapLocked(item: ChatRenderItem)
    fun onTapRetry(item: ChatRenderItem)
    fun onTapAvatar()
}

/**
 * 말풍선 메시지 공통 ViewHolder.
 *
 * 뷰 트리는 ViewHolder 를 만들 때 한 번만 구성한다. [bind] 에서는 보이기/숨기기와 값만 바꾼다.
 * (실서비스 버전은 bind 마다 removeAllViews() 후 셀 내용을 새로 만들었다. 셀을 재사용해도 매번 뷰를
 * 새로 만드는 셈이라 RecyclerView 를 쓰는 이점이 줄어든다)
 */
abstract class MessageViewHolder(
    parent: ViewGroup,
    contentLayout: Int,
    protected val theme: ChatTheme,
    protected val listener: ChatItemListener,
) : RecyclerView.ViewHolder(
    LayoutInflater.from(parent.context).inflate(R.layout.item_chat_message, parent, false),
) {
    private val row: LinearLayout = itemView.findViewById(R.id.row)
    private val avatar: ImageView = itemView.findViewById(R.id.avatar)
    private val nickname: TextView = itemView.findViewById(R.id.nickname)
    private val metaStart: View = itemView.findViewById(R.id.meta_start)
    private val metaEnd: View = itemView.findViewById(R.id.meta_end)
    private val contentContainer: FrameLayout = itemView.findViewById(R.id.content_container)
    protected val content: View =
        LayoutInflater.from(parent.context).inflate(contentLayout, contentContainer, true)
            .let { contentContainer.getChildAt(0) }

    protected var current: ChatRenderItem? = null
        private set

    init {
        avatar.setOnClickListener { listener.onTapAvatar() }
        nickname.text = theme.peerNickname
        for (meta in listOf(metaStart, metaEnd)) {
            meta.findViewById<View>(R.id.retry).setOnClickListener {
                current?.let(listener::onTapRetry)
            }
            meta.findViewById<TextView>(R.id.read).apply {
                text = theme.readLabel
                setTextColor(theme.mineBubbleColor)
            }
        }
    }

    fun bind(item: ChatRenderItem) {
        current = item
        val mine = item.isMine

        row.gravity = if (mine) Gravity.END else Gravity.START
        row.updatePaddingRelative(top = dp(if (item.groupStart) 10 else 2), bottom = dp(2))

        // 상대 묶음의 첫 메시지에만 프로필. 나머지는 INVISIBLE 로 자리를 유지해 말풍선 정렬을 맞춘다.
        avatar.visibility = when {
            mine -> View.GONE
            item.showAvatar -> View.VISIBLE
            else -> View.INVISIBLE
        }
        if (item.showAvatar && !mine) {
            avatar.loadOnce(theme.peerAvatarUrl, circle = true)
        }
        nickname.visibility = if (item.showAvatar && !mine) View.VISIBLE else View.GONE

        metaStart.visibility = if (mine) View.VISIBLE else View.GONE
        metaEnd.visibility = if (mine) View.GONE else View.VISIBLE
        bindMeta(if (mine) metaStart else metaEnd, item)

        bindContent(item)
    }

    protected abstract fun bindContent(item: ChatRenderItem)

    protected fun bubbleColor(item: ChatRenderItem): Int =
        if (item.isMine) theme.mineBubbleColor else theme.peerBubbleColor

    protected fun tintBubble(view: View, color: Int) {
        ViewCompat.setBackgroundTintList(view, ColorStateList.valueOf(color))
    }

    protected fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), itemView.resources.displayMetrics,
        ).toInt()

    private fun bindMeta(meta: View, item: ChatRenderItem) {
        val sending = meta.findViewById<View>(R.id.sending)
        val retry = meta.findViewById<View>(R.id.retry)
        val read = meta.findViewById<View>(R.id.read)
        val time = meta.findViewById<TextView>(R.id.time)

        sending.visibility = if (item.status == ChatRenderItem.Status.SENDING) View.VISIBLE else View.GONE
        retry.visibility = if (item.status == ChatRenderItem.Status.FAILED) View.VISIBLE else View.GONE

        val sent = item.status == ChatRenderItem.Status.SENT
        read.visibility = if (sent && item.read) View.VISIBLE else View.GONE
        time.text = item.timeLabel
        time.visibility = if (sent && item.timeLabel != null) View.VISIBLE else View.GONE
    }
}

class TextMessageViewHolder(
    parent: ViewGroup,
    theme: ChatTheme,
    listener: ChatItemListener,
) : MessageViewHolder(parent, R.layout.content_text, theme, listener) {
    private val text = content as TextView

    init {
        text.setTextSize(TypedValue.COMPLEX_UNIT_SP, theme.fontSizeSp)
    }

    override fun bindContent(item: ChatRenderItem) {
        val color = bubbleColor(item)
        tintBubble(text, color)
        text.setTextColor(readableTextColor(color))
        text.text = item.text
    }
}

class ImageMessageViewHolder(
    parent: ViewGroup,
    theme: ChatTheme,
    listener: ChatItemListener,
) : MessageViewHolder(parent, R.layout.content_image, theme, listener) {
    private val frame = content
    private val image: ImageView = content.findViewById(R.id.image)
    private val lockDim: View = content.findViewById(R.id.lock_dim)
    private val lockLabel: TextView = content.findViewById(R.id.lock_label)

    init {
        frame.clipToOutline = true
        frame.setOnClickListener {
            val item = current ?: return@setOnClickListener
            if (item.locked) listener.onTapLocked(item) else listener.onTapMessage(item)
        }
    }

    override fun bindContent(item: ChatRenderItem) {
        // 비율에 맞춘 높이를 bind 시점에 확정한다. 이미지 로딩이 끝난 뒤 높이가 바뀌면
        // 위쪽 셀들이 밀리면서 스크롤이 튄다.
        val ratio = (item.aspectRatio ?: 1.0).coerceIn(0.6, 1.8)
        val width = frame.layoutParams.width
        frame.layoutParams = frame.layoutParams.apply { height = (width / ratio).toInt() }

        lockDim.visibility = if (item.locked) View.VISIBLE else View.GONE
        lockLabel.visibility = if (item.locked) View.VISIBLE else View.GONE
        lockLabel.text = item.price?.let { "${"%,d".format(it)}P" }

        // 잠긴 사진은 아주 작게 받아서 늘려 그린다 → 흐릿한 미리보기.
        // 실서비스라면 서버가 처음부터 미리보기용 URL 만 내려줘야 한다 (README 참고).
        image.loadOnce(item.imageUrl, thumbnailPx = if (item.locked) 24 else null)
    }
}

class GiftMessageViewHolder(
    parent: ViewGroup,
    theme: ChatTheme,
    listener: ChatItemListener,
) : MessageViewHolder(parent, R.layout.content_gift, theme, listener) {
    private val giftImage: ImageView = content.findViewById(R.id.gift_image)
    private val giftName: TextView = content.findViewById(R.id.gift_name)
    private val giftAmount: TextView = content.findViewById(R.id.gift_amount)

    init {
        content.setOnClickListener { current?.let(listener::onTapMessage) }
    }

    override fun bindContent(item: ChatRenderItem) {
        val color = bubbleColor(item)
        tintBubble(content, color)
        val textColor = readableTextColor(color)
        giftName.setTextColor(textColor)
        giftAmount.setTextColor(ColorUtils.setAlphaComponent(textColor, 0xB3))

        giftName.text = item.giftName
        giftAmount.text = item.giftAmount?.let { "${"%,d".format(it)}P" }
        giftImage.loadOnce(item.imageUrl)
    }
}

/** 날짜 구분선 / 공지. */
class CenterLabelViewHolder(parent: ViewGroup) : RecyclerView.ViewHolder(
    LayoutInflater.from(parent.context).inflate(R.layout.item_chat_center, parent, false),
) {
    private val label: TextView = itemView.findViewById(R.id.label)

    fun bind(item: ChatRenderItem) {
        label.text = item.text
        val notice = item.kind == ChatRenderItem.Kind.NOTICE
        label.setTextColor(
            ContextCompat.getColor(
                label.context,
                if (notice) R.color.chat_text_primary else R.color.chat_text_secondary,
            ),
        )
    }
}

class LoadingViewHolder(parent: ViewGroup) : RecyclerView.ViewHolder(
    LayoutInflater.from(parent.context).inflate(R.layout.item_chat_loading, parent, false),
)

// -----------------------------------------------------------------------------

/** 배경색 밝기에 따라 읽기 좋은 글자색. 테마 색이 Flutter 에서 오기 때문에 고정할 수 없다. */
private fun readableTextColor(background: Int): Int =
    if (ColorUtils.calculateLuminance(background) < 0.5) Color.WHITE else 0xFF1F2937.toInt()

/**
 * 같은 이미지를 다시 bind 할 때 로드를 건너뛴다.
 * ack·읽음 표시처럼 이미지와 무관한 변경으로 셀이 다시 bind 돼도 사진이 깜빡이지 않게 하기 위함.
 */
private fun ImageView.loadOnce(url: String?, circle: Boolean = false, thumbnailPx: Int? = null) {
    val key = "$url|$circle|$thumbnailPx"
    if (getTag(R.id.chat_loaded_image_key) == key) return
    setTag(R.id.chat_loaded_image_key, key)

    if (url == null) {
        Glide.with(this).clear(this)
        setImageDrawable(null)
        return
    }
    var request = Glide.with(this).load(url)
    if (circle) request = request.circleCrop()
    if (thumbnailPx != null) request = request.override(thumbnailPx).dontAnimate()
    request.into(this)
}
