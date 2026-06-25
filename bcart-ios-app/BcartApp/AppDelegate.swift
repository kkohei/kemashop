import UIKit
import UserNotifications

/// APNs 登録と通知ハンドリングを担う。
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        requestPushAuthorization()
        return true
    }

    /// 通知許可を求め、許可されたら APNs に登録
    private func requestPushAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// APNs デバイストークン取得 → 中継サーバーへ登録
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushTokenStore.shared.deviceToken = token
        // 会員キーが既に分かっていれば即登録(分からなければログイン検知後に登録)
        DeviceRegistration.registerIfPossible()
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs登録失敗: \(error)")
    }

    // フォアグラウンドでも通知を表示
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // 通知タップ → ディープリンクのパスを取り出して通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let path = info["url"] as? String {
            NotificationCenter.default.post(name: .openDeepLink, object: path)
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let openDeepLink = Notification.Name("openDeepLink")
}

/// デバイストークンの一時保持
final class PushTokenStore {
    static let shared = PushTokenStore()
    var deviceToken: String?
}
