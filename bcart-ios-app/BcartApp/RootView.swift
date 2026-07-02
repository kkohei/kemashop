import SwiftUI

/// ルート画面。状態に応じて Welcome / ロック / WebView を切り替える。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appState.route {
            case .welcome:
                WelcomeView()
            case .locked:
                LockView()
            case .web:
                VStack(spacing: 0) {
                    BcartWebView()
                    BottomBar()
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            // バックグラウンドへ移動したら、認証情報がある場合は再ロック
            if newPhase == .background, KeychainStore.hasCredentials {
                appState.route = .locked
            }
        }
    }
}

/// 初回起動画面: KEMAロゴ + 新規登録ボタン + ログインリンク。
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            // ロゴ(画像に差し替える場合は Image("logo") に変更)
            VStack(spacing: 6) {
                Text("KEMA")
                    .font(.system(size: 46, weight: .bold))
                    .tracking(6)
                Text("SHOP")
                    .font(.system(size: 18, weight: .medium))
                    .tracking(10)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 18) {
                Button {
                    appState.open(path: AppConfig.registerPath)
                } label: {
                    Text("新規登録")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    appState.open(path: AppConfig.loginPath)
                } label: {
                    Text("ログインはこちら")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
    }
}

/// WebView下部の常設ナビゲーションバー。
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
            if success { appState.route = .web }
        }
    }
}
