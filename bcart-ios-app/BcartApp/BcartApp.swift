import SwiftUI
import Combine

/// アプリのエントリポイント。APNs のために AppDelegate を併用する。
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

/// 画面の状態。
enum AppRoute {
    case welcome  // 初回: ロゴ + 新規登録/ログイン
    case locked   // 再訪: Face IDロック
    case web      // WebView表示
}

/// アプリ横断の状態。
final class AppState: ObservableObject {
    @Published var route: AppRoute
    /// WebViewが最初に開くパス(Welcome画面のボタンで設定)
    @Published var startPath: String
    /// ログイン中の会員を識別するキー(email)
    @Published var memberKey: String? {
        didSet { if let memberKey { KeychainStore.saveMemberKey(memberKey) } }
    }

    init() {
        memberKey = KeychainStore.loadMemberKey()
        if KeychainStore.hasCredentials {
            route = .locked          // 登録済み → Face ID
            startPath = AppConfig.loginPath
        } else {
            route = .welcome         // 初回 → ロゴ画面
            startPath = "/"
        }
    }

    /// 指定パスをWebViewで開く(Welcome画面のボタンから使用)
    func open(path: String) {
        startPath = path
        route = .web
    }
}
