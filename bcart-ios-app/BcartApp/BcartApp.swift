import SwiftUI

/// アプリのエントリポイント。
/// APNs(プッシュ通知)のために AppDelegate を併用する。
@main
struct BcartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}

/// アプリ横断の状態。
final class AppState: ObservableObject {
    /// 生体認証によるロック解除済みか
    @Published var isUnlocked = false
    /// プッシュ通知タップで開きたいパス(WebViewへ反映)
    @Published var pendingDeepLinkPath: String?
    /// ログイン中の会員を識別するキー(email を採用。customer_id でも可)
    @Published var memberKey: String? {
        didSet { if let memberKey { KeychainStore.saveMemberKey(memberKey) } }
    }

    init() {
        memberKey = KeychainStore.loadMemberKey()
    }
}
