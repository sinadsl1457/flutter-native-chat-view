package dev.sintaek.nativechat.chat

import android.annotation.SuppressLint
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView

/**
 * Dart 가 계산해 보낸 op(insert/remove/update)를 그대로 적용하는 어댑터.
 *
 * DiffUtil 을 쓰지 않는다. 비교는 이미 Dart(ChatListDiff)에서 끝났고, 여기서 또 비교하면
 * 같은 일을 두 번 하는 것이다. op 의 index 는 "앞선 op 적용 직후" 기준이라 순서대로 적용하면 된다.
 *
 * 데이터는 최신 → 오래된 순. LinearLayoutManager(reverseLayout = true) 와 함께 쓰면
 * index 0 이 화면 맨 아래에 그려진다.
 */
class ChatAdapter(
    private val theme: ChatTheme,
    private val listener: ChatItemListener,
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private val items = ArrayList<ChatRenderItem>()

    /** 이전 메시지 로딩 표시. 목록 끝(= 화면 맨 위)에 붙는다. */
    var showOlderLoader: Boolean = false
        private set

    val messageCount: Int get() = items.size

    // 첫 표시나 순서가 뒤바뀐 경우에만 오는 명령 — 전체 갱신이 맞다.
    @SuppressLint("NotifyDataSetChanged")
    fun reset(newItems: List<ChatRenderItem>) {
        items.clear()
        items.addAll(newItems)
        notifyDataSetChanged()
    }

    fun insert(index: Int, newItems: List<ChatRenderItem>) {
        if (newItems.isEmpty()) return
        items.addAll(index, newItems)
        notifyItemRangeInserted(index, newItems.size)
    }

    fun remove(index: Int, count: Int) {
        if (count <= 0) return
        items.subList(index, index + count).clear()
        notifyItemRangeRemoved(index, count)
    }

    fun update(index: Int, item: ChatRenderItem) {
        items[index] = item
        notifyItemChanged(index)
    }

    fun setOlderLoader(show: Boolean) {
        if (show == showOlderLoader) return
        showOlderLoader = show
        if (show) notifyItemInserted(items.size) else notifyItemRemoved(items.size)
    }

    override fun getItemCount(): Int = items.size + if (showOlderLoader) 1 else 0

    override fun getItemViewType(position: Int): Int {
        if (position >= items.size) return TYPE_LOADING
        return when (items[position].kind) {
            ChatRenderItem.Kind.TEXT -> TYPE_TEXT
            ChatRenderItem.Kind.IMAGE -> TYPE_IMAGE
            ChatRenderItem.Kind.GIFT -> TYPE_GIFT
            ChatRenderItem.Kind.NOTICE, ChatRenderItem.Kind.DATE -> TYPE_CENTER
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder =
        when (viewType) {
            TYPE_TEXT -> TextMessageViewHolder(parent, theme, listener)
            TYPE_IMAGE -> ImageMessageViewHolder(parent, theme, listener)
            TYPE_GIFT -> GiftMessageViewHolder(parent, theme, listener)
            TYPE_CENTER -> CenterLabelViewHolder(parent)
            else -> LoadingViewHolder(parent)
        }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (holder) {
            is MessageViewHolder -> holder.bind(items[position])
            is CenterLabelViewHolder -> holder.bind(items[position])
        }
    }

    private companion object {
        const val TYPE_TEXT = 1
        const val TYPE_IMAGE = 2
        const val TYPE_GIFT = 3
        const val TYPE_CENTER = 4
        const val TYPE_LOADING = 5
    }
}
