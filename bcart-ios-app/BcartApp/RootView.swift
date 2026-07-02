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
/// 流れ続けるゴールド×ピンクゴールドの背景 + 中央ロゴ + PRO SHOP + ログイン/新規登録ボタン。
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            // 常時ゆらゆら流れる背景
            FlowingGoldBackground()

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

/// 流れ続けるゴールド×ピンクゴールドの背景。
/// MeshGradient の格子点を TimelineView で常時サイン波で動かし、有機的に流れる効果を出す。
struct FlowingGoldBackground: View {
    // 濃いめ・深みのあるゴールド × ピンクゴールド
    private let paleGold  = Color(red: 0.89, green: 0.74, blue: 0.42)
    private let lightGold = Color(red: 0.82, green: 0.63, blue: 0.26)
    private let gold      = Color(red: 0.72, green: 0.52, blue: 0.16)
    private let roseGold  = Color(red: 0.78, green: 0.52, blue: 0.40)
    private let deepGold  = Color(red: 0.50, green: 0.35, blue: 0.13)

    var body: some View {
        if #available(iOS 18.0, *) {
            TimelineView(.animation) { timeline in
                mesh(timeline.date.timeIntervalSinceReferenceDate)
            }
            .ignoresSafeArea()
        } else {
            // iOS 17 以前のフォールバック(静的グラデーション)
            LinearGradient(colors: [paleGold, lightGold, roseGold, gold, deepGold],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
    }

    @available(iOS 18.0, *)
    private func mesh(_ t: TimeInterval) -> some View {
        func p(_ x: Double, _ y: Double) -> SIMD2<Float> { SIMD2(Float(x), Float(y)) }
        // 異なる周期のサイン波で格子点を揺らす → ずっと流れ続ける
        let a = sin(t * 0.45), b = cos(t * 0.37)
        let c = sin(t * 0.60), d = cos(t * 0.52)
        return MeshGradient(
            width: 3, height: 3,
            points: [
                p(0, 0),                p(0.5 + 0.10 * a, 0),               p(1, 0),
                p(0, 0.5 + 0.10 * b),   p(0.5 + 0.12 * c, 0.5 + 0.12 * d),  p(1, 0.5 - 0.10 * b),
                p(0, 1),                p(0.5 - 0.10 * a, 1),               p(1, 1)
            ],
            colors: [
                paleGold,  lightGold, roseGold,
                gold,      roseGold,  gold,
                deepGold,  gold,      lightGold
            ]
        )
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
