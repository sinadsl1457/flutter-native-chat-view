package dev.sintaek.nativechat.chat

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.SimpleItemAnimator
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * Flutter 화면 안에 끼워 넣는 네이티브 채팅 목록 (PlatformView).
 *
 * ## 뒤집힌 리스트
 * `reverseLayout = true` 로 index 0(최신)을 화면 맨 아래에 그린다.
 * - 이전 메시지를 불러오면 목록 "끝"에 붙는다 → 지금 보고 있는 셀들의 위치가 그대로라 스크롤이 튀지 않는다.
 * - 새 메시지는 index 0 에 붙는다 → 맨 아래를 보고 있었다면 그대로 맨 아래를 따라간다.
 *
 * 실서비스 버전은 `stackFromEnd` + 앞쪽 삽입이라, 이전 메시지를 불러올 때마다
 * 첫 번째 보이는 셀의 위치/오프셋을 저장했다가 다시 스크롤해서 복원해야 했다.
 *
 * ## 채널
 * viewId 별 채널(`native_chat_view/<viewId>`). 화면이 두 개 떠도 서로의 이벤트를 가로채지 않는다.
 */
class NativeChatView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    args: Map<*, *>?,
) : PlatformView, MethodChannel.MethodCallHandler, ChatItemListener {

    private val channel = MethodChannel(messenger, "native_chat_view/$viewId")
    private val theme = ChatTheme.fromWire(args?.get("config") as? Map<*, *>)
    private val adapter = ChatAdapter(theme, this)
    private val layoutManager = LinearLayoutManager(context, RecyclerView.VERTICAL, true)
    private val recycler = RecyclerView(context)

    private var hasMoreOlder = args?.get("hasMoreOlder") != false
    private var loadingOlder = false
    private var lastOlderRequestAt = 0L
    private var atBottom = true

    // init 보다 위에 선언해야 한다 (Kotlin 프로퍼티는 선언 순서대로 초기화된다).
    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
            notifyAtBottomIfChanged()
            // dy < 0: 화면 위쪽(과거 메시지 쪽)으로 이동 중
            if (dy < 0) requestOlderIfNearTop()
        }
    }

    init {
        recycler.layoutManager = layoutManager
        recycler.adapter = adapter
        recycler.setBackgroundColor(theme.backgroundColor)
        recycler.clipToPadding = false
        recycler.setPadding(0, dp(8), 0, dp(8))
        // 내용만 바뀐 셀(ack, 읽음, 잠금 해제)은 교차 페이드 없이 바로 바꾼다. 페이드가 있으면 깜빡여 보인다.
        // 삽입/삭제 애니메이션은 유지한다.
        (recycler.itemAnimator as? SimpleItemAnimator)?.supportsChangeAnimations = false

        adapter.reset(ChatRenderItem.listFromWire(args?.get("initialItems")))

        recycler.addOnScrollListener(scrollListener)
        recycler.addOnItemTouchListener(backgroundTapListener(context))
        channel.setMethodCallHandler(this)

        // 첫 화면이 짧으면(메시지가 적으면) 스크롤이 생기지 않아 이전 메시지 요청이 안 나간다.
        recycler.post { requestOlderIfViewportNotFilled() }
    }

    override fun getView(): View = recycler

    override fun dispose() {
        channel.setMethodCallHandler(null)
        recycler.clearOnScrollListeners()
        recycler.adapter = null
    }

    // ---------------------------------------------------------------------------------------------
    // Dart → Native

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            "applyPatch" -> {
                if (args == null) return result.error("INVALID_ARGS", "patch required", null)
                applyPatch(args)
                result.success(null)
            }

            "setOlderState" -> {
                loadingOlder = args?.get("loading") == true
                hasMoreOlder = args?.get("hasMore") != false
                adapter.setOlderLoader(loadingOlder && hasMoreOlder)
                if (!loadingOlder) recycler.post { requestOlderIfViewportNotFilled() }
                result.success(null)
            }

            "scrollToBottom" -> {
                if (args?.get("animated") == true) recycler.smoothScrollToPosition(0)
                else recycler.scrollToPosition(0)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun applyPatch(args: Map<*, *>) {
        val wasAtBottom = isAtBottom()
        val stickToBottom = args["stickToBottom"] == true
        var insertedNewest = false

        when (args["type"]) {
            "reset" -> adapter.reset(ChatRenderItem.listFromWire(args["items"]))
            "ops" -> for (raw in args["ops"] as? List<*> ?: emptyList<Any>()) {
                val op = raw as? Map<*, *> ?: continue
                val index = (op["index"] as? Number)?.toInt() ?: continue
                when (op["op"]) {
                    "insert" -> {
                        adapter.insert(index, ChatRenderItem.listFromWire(op["items"]))
                        if (index == 0) insertedNewest = true
                    }
                    "remove" -> adapter.remove(index, (op["count"] as? Number)?.toInt() ?: 0)
                    "update" -> (op["item"] as? Map<*, *>)
                        ?.let(ChatRenderItem::fromWire)
                        ?.let { adapter.update(index, it) }
                }
            }
            else -> Log.w(TAG, "unknown patch type: ${args["type"]}")
        }

        // index 0 에 삽입하면 RecyclerView 는 기존 셀을 기준으로 자리를 지키므로,
        // 맨 아래를 보고 있던 경우엔 새 메시지가 화면 밖(아래)에 생긴다 → 명시적으로 따라 내려간다.
        // 위로 스크롤해 읽는 중이었다면 그대로 두고, Dart 쪽 "최신 메시지" 버튼이 보이게 된다.
        if (stickToBottom || (insertedNewest && wasAtBottom)) {
            recycler.scrollToPosition(0)
        }
        recycler.post { notifyAtBottomIfChanged() }
    }

    // ---------------------------------------------------------------------------------------------
    // Native → Dart

    override fun onTapMessage(item: ChatRenderItem) = send("onTapMessage", mapOf("key" to item.key))

    override fun onTapLocked(item: ChatRenderItem) = send("onTapLocked", mapOf("key" to item.key))

    override fun onTapRetry(item: ChatRenderItem) = send("onTapRetry", mapOf("key" to item.key))

    override fun onTapAvatar() = send("onTapAvatar")

    private fun send(method: String, args: Map<String, Any?>? = null) {
        channel.invokeMethod(method, args)
    }

    private fun requestOlderIfNearTop() {
        val lastVisible = layoutManager.findLastVisibleItemPosition()
        if (lastVisible == RecyclerView.NO_POSITION) return
        // reverseLayout 에서 마지막 index = 화면 맨 위 = 가장 오래된 메시지
        if (lastVisible >= adapter.messageCount - 1 - PREFETCH_DISTANCE) requestOlder()
    }

    private fun requestOlderIfViewportNotFilled() {
        // 아직 레이아웃 전(높이 0)이면 판단할 수 없다. setOlderState 를 받을 때 다시 확인한다.
        if (recycler.height == 0) return
        if (!recycler.canScrollVertically(-1)) requestOlder()
    }

    private fun requestOlder() {
        if (!hasMoreOlder || loadingOlder) return
        // Dart 가 응답(setOlderState)을 보내기 전 짧은 시간 동안 같은 요청이 연달아 나가지 않게.
        val now = SystemClock.elapsedRealtime()
        if (now - lastOlderRequestAt < OLDER_REQUEST_DEBOUNCE_MS) return
        lastOlderRequestAt = now
        send("onLoadOlder")
    }

    private fun isAtBottom(): Boolean = !recycler.canScrollVertically(1)

    private fun notifyAtBottomIfChanged() {
        val now = isAtBottom()
        if (now == atBottom) return
        atBottom = now
        send("onAtBottomChanged", mapOf("atBottom" to now))
    }

    /** 빈 곳/메시지를 탭하면 Flutter 입력창의 키보드를 내린다. 터치는 소비하지 않는다. */
    private fun backgroundTapListener(context: Context): RecyclerView.OnItemTouchListener {
        val detector = GestureDetector(
            context,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onSingleTapUp(e: MotionEvent): Boolean {
                    send("onTapBackground")
                    return false
                }
            },
        )
        return object : RecyclerView.SimpleOnItemTouchListener() {
            override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
                detector.onTouchEvent(e)
                return false
            }
        }
    }

    private fun dp(value: Int): Int = (value * recycler.resources.displayMetrics.density).toInt()

    private companion object {
        const val TAG = "NativeChatView"
        const val PREFETCH_DISTANCE = 8
        const val OLDER_REQUEST_DEBOUNCE_MS = 1_000L
    }
}
