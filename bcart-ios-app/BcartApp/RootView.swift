import SwiftUI

/// ルート画面。生体認証で解錠するまではロック画面を表示する。
/// 解錠後は WebView + 下部のナビゲーションバー(ホーム/ログイン/注文履歴)を表示。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if appState.isUnlocked {
                VStack(spacing: 0) {
                    BcartWebView()
                    BottomBar()
                }
            } else {
                LockView()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            // バックグラウンドへ移動したら再ロック(復帰時に再度Face IDを要求)
            if newPhase == .background {
                appState.isUnlocked = false
            }
        }
    }
}

/// 下部の常設ナビゲーションバー。ログインをいつでも1タップで開ける。
struct BottomBar: View {
    var body: some View {
        HStack(alignment: .center) {
            BarButton(title: "ホーム", systemImage: "house", path: "/")
            BarButton(title: "ログイン", systemImage: "person.crop.circle", path: AppConfig.loginPath)
            BarButton(title: "新規登録", systemImage: "person.badge.plus", path: AppConfig.registerPath)
            BarButton(title: "注文履歴", systemImage: "clock.arrow.circlepath", path: AppConfig.orderHistoryPath)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
    }
}

/// 下部バーの1ボタン。タップでWebViewを該当パスへ遷移させる。
struct BarButton: View {
    let title: String
    let systemImage: String
    let path: String

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openDeepLink, object: path)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 20))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.primary)
    }
}

/// ロック画面。Face ID / Touch ID で解錠する。
struct LockView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("KEMASHOP")
                .font(.title2.bold())
            Button {
                unlock()
            } label: {
                Label("Face ID で解錠", systemImage: "faceid")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear { unlock() }
    }

    private func unlock() {
        BiometricGate.authenticate { success in
            if success { appState.isUnlocked = true }
        }
    }
}
