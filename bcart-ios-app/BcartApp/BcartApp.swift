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
    /// 設定シート(退会申請など)の表示
    @Published var showSettings = false
    /// ログイン中の会員を識別するキー(email)
    @Published var memberKey: String? {
        didSet { if let memberKey { KeychainStore.saveMemberKey(memberKey) } }
    }

    /// 通知タップ等で届いた検証済みの遷移先。WebViewが準備済み かつ 解錠済み(.web)になってから1度だけ開いて消す。
    @Published var pendingPath: String?

    private var deepLinkObserver: AnyCancellable?

    init() {
        memberKey = KeychainStore.loadMemberKey()
        if KeychainStore.hasCredentials {
            route = .locked          // 登録済み → Face ID
            startPath = AppConfig.loginPath
        } else {
            route = .welcome         // 初回 → ロゴ画面
            startPath = "/"
        }
        pendingPath = DeepLinkInbox.shared.take()
        deepLinkObserver = NotificationCenter.default.publisher(for: .openDeepLink)
            .sink { [weak self] _ in
                if let p = DeepLinkInbox.shared.take() { self?.pendingPath = p }
            }
    }

    /// 指定パスをWebViewで開く(Welcome画面のボタンから使用)
    func open(path: String) {
        startPath = AppConfig.shopURL(from: path) != nil ? path : "/"
        route = .web
    }
}
