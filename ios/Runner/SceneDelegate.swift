import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let badgeChannelName = "com.example.agent_str/app_badge"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    configureBadgeChannel()
  }

  private func configureBadgeChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let badgeChannel = FlutterMethodChannel(
      name: badgeChannelName,
      binaryMessenger: controller.binaryMessenger
    )

    badgeChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "setBadgeCount":
        let args = call.arguments as? [String: Any]
        let count = args?["count"] as? Int ?? 0
        UIApplication.shared.applicationIconBadgeNumber = max(0, count)
        result(nil)
      case "clearBadge":
        UIApplication.shared.applicationIconBadgeNumber = 0
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
