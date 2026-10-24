import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let registrar = registrar(forPlugin: "NativeChatView") {
      registrar.register(
        NativeChatViewFactory(messenger: registrar.messenger()),
        withId: NativeChatViewFactory.viewType
      )
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
