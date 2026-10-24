package dev.sintaek.nativechat.chat

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NativeChatViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        NativeChatView(context, messenger, viewId, args as? Map<*, *>)

    companion object {
        /** Dart `NativeChatView.viewType` 과 같아야 한다. */
        const val VIEW_TYPE = "native_chat_view"
    }
}
