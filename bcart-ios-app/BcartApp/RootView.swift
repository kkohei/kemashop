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

/// 初回起動画面:
/// 動くゴールド×ピンクゴールドのグラデーション背景 + 中央ロゴ + PRO SHOP + ログイン/新規登録ボタン。
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var animate = false

    // ゴールド〜ピンクゴールドの配色
    private let lightGold = Color(red: 0.96, green: 0.87, blue: 0.66)
    private let gold      = Color(red: 0.85, green: 0.67, blue: 0.32)
    private let roseGold  = Color(red: 0.91, green: 0.72, blue: 0.66)
    private let deepGold  = Color(red: 0.72, green: 0.52, blue: 0.30)

    var body: some View {
        ZStack {
            // 動くグラデーション背景
            LinearGradient(
                colors: [lightGold, gold, roseGold, deepGold],
                startPoint: animate ? .topLeading : .bottomTrailing,
                endPoint: animate ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }

            VStack(spacing: 0) {
                Spacer()

                // ロゴ(Assets に "logo" 画像を追加してください)
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200)
                    .padding(.bottom, 14)

                Text("PRO SHOP")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(8)
                    .foregroundStyle(.white)

                Spacer()

                VStack(spacing: 14) {
                    // ログイン(白ボタン)
                    Button {
                        appState.open(path: AppConfig.loginPath)
                    } label: {
                        Text("ログイン")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(.white, in: Capsule())
                    }

                    // 新規登録(白枠ボタン)
                    Button {
                        appState.open(path: AppConfig.registerPath)
                    } label: {
                        Text("新規登録")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(.white.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1.5))
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
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
