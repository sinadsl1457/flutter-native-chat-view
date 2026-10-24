package dev.sintaek.nativechat

import dev.sintaek.nativechat.chat.NativeChatViewFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            NativeChatViewFactory.VIEW_TYPE,
            NativeChatViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
    }
}
