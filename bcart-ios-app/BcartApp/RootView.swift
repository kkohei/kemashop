import SwiftUI
import WebKit

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
                .sheet(isPresented: $appState.showSettings) {
                    SettingsView().environmentObject(appState)
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

/// アイボリー・ミニマルのブランドカラー(Welcome / ロック画面で共通)。
/// 注意: 16進→Double変換は必ず 255.0 で割ること(整数除算になるため 255 は不可)。
enum KemaTheme {
    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
    }

    static let ink   = rgb(0x1a, 0x16, 0x12)  // #1a1612
    static let ivory = rgb(0xf7, 0xf1, 0xe6)  // #f7f1e6
    static let gold  = rgb(0x9a, 0x7d, 0x4a)  // #9a7d4a

    // 背景グラデーション
    static let bgTop       = rgb(0xf7, 0xf1, 0xe6)  // #f7f1e6
    static let bgMiddle    = rgb(0xf3, 0xea, 0xd9)  // #f3ead9
    static let bgBottom    = rgb(0xef, 0xe4, 0xd0)  // #efe4d0
    static let bgHighlight = rgb(0xff, 0xfd, 0xf8)  // #fffdf8
}

/// アイボリーの紙色グラデーション背景 + 上部中央のハイライト(Welcome / ロック画面で共通)。
struct IvoryBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: KemaTheme.bgTop, location: 0),
                    .init(color: KemaTheme.bgMiddle, location: 0.48),
                    .init(color: KemaTheme.bgBottom, location: 1)
                ],
                startPoint: .top, endPoint: .bottom)

            // 上部中央のやわらかなハイライト(ellipse 80% 60% at 50% 0%)
            GeometryReader { geo in
                RadialGradient(
                    colors: [KemaTheme.bgHighlight, .clear],
                    center: .init(x: 0.5, y: 0),
                    startRadius: 0,
                    endRadius: geo.size.width * 0.8)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(x: 1, y: 0.75, anchor: .top)
            }
        }
        .ignoresSafeArea()
    }
}

/// 公式ロゴ + 小さな「PRO SHOP」キャプション(Welcome / ロック画面で共通)。
struct KemaLogoMark: View {
    var body: some View {
        VStack(spacing: 0) {
            // 公式ロゴ(黒・透過PNG)。再タイプセットや加工は行わないこと。
            // 【Mac側セットアップ】git pull → Xcode で Assets.xcassets を開き、
            // bcart-ios-app/BcartApp/Resources/kema-logo.imageset フォルダを Assets.xcassets にドラッグ。
            // セット名が "kema-logo"(下の Image 名と完全一致)であることを確認して再ビルド。
            Image("kema-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 228)

            // 公式ロゴの一部ではない小さなキャプション
            Text("PRO SHOP")
                .font(.system(size: 10, weight: .regular))
                .tracking(4.8)
                .padding(.leading, 4.8)   // 末尾の字間分を相殺して視覚的に中央へ
                .foregroundStyle(KemaTheme.gold)
                .padding(.top, 20)
        }
    }
}

/// 初回起動画面(アイボリー・ミニマル):
/// アイボリーの紙色グラデーション背景 + 公式ロゴ + PRO SHOP キャプション + ログイン/新規登録ボタン。
/// ライト/ダークモードに関わらず常にこのデザインで表示する。
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    private let ink = KemaTheme.ink
    private let ivory = KemaTheme.ivory

    var body: some View {
        ZStack {
            IvoryBackground()

            VStack(spacing: 0) {
                Spacer()

                KemaLogoMark()

                Spacer()

                VStack(spacing: 14) {
                    // ログイン(塗りつぶし)
                    Button {
                        appState.open(path: AppConfig.loginPath)
                    } label: {
                        Text("ログイン")
                            .font(.system(size: 17, weight: .medium))
                            .tracking(2.4)
                            .foregroundStyle(ivory)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(ink, in: Capsule())
                    }

                    // 新規登録(細い枠線)
                    Button {
                        appState.open(path: AppConfig.registerPath)
                    } label: {
                        Text("新規登録")
                            .font(.system(size: 17, weight: .medium))
                            .tracking(2.4)
                            .foregroundStyle(ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .overlay(Capsule().stroke(ink, lineWidth: 1))
                    }
                }
                .frame(maxWidth: 440)   // iPhone Duo等の広い画面でボタンが間延びしないよう上限
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity) // コンテンツは物理画面の中央寄せ
        }
        // iPhone Duo内側画面では右端のステータスバー分セーフエリアが非対称になり
        // コンテンツが左に寄るため、画面全体でセーフエリアを無視して物理画面基準で配置する
        .ignoresSafeArea()
        // 常にアイボリーのデザイン。ステータスバーも黒文字になる
        .preferredColorScheme(.light)
    }
}

/// WebView下部の常設ナビゲーションバー。
struct BottomBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(alignment: .center) {
            BarButton(title: "ホーム", systemImage: "house", path: "/")
            BarButton(title: "ログイン", systemImage: "person.crop.circle", path: AppConfig.loginPath)
            BarButton(title: "新規登録", systemImage: "person.badge.plus", path: AppConfig.registerPath)
            BarButton(title: "注文履歴", systemImage: "clock.arrow.circlepath", path: AppConfig.orderHistoryPath)
            Button {
                appState.showSettings = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "gearshape").font(.system(size: 20))
                    Text("設定").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: 620)           // iPhone Duo等の広い画面でボタンが離れすぎないよう上限
        .frame(maxWidth: .infinity)     // バーの背景自体は全幅
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
    }
}

/// 設定シート。App Store要件のため、アプリ内から退会(アカウント削除)を申請できる。
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showConfirm = false
    @State private var done = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("アカウント")) {
                    Button {
                        logout()
                    } label: {
                        Label("ログアウト（最初の画面に戻る）", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button(role: .destructive) {
                        showConfirm = true
                    } label: {
                        Label("退会（アカウント削除）を申請", systemImage: "trash")
                    }
                }
                Section(footer: Text("退会を申請すると、数営業日以内にアカウントと関連データを削除いたします。")) {
                    EmptyView()
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("退会（アカウント削除）を申請します", isPresented: $showConfirm) {
                Button("キャンセル", role: .cancel) {}
                Button("申請する", role: .destructive) { submit() }
            } message: {
                Text("この操作でアカウント削除を申請します。数営業日以内に削除いたします。よろしいですか？")
            }
            .alert("申請を受け付けました", isPresented: $done) {
                Button("OK") { dismiss() }
            } message: {
                Text("退会申請を受け付けました。削除完了までお待ちください。")
            }
        }
    }

    private func submit() {
        DeletionRequest.submit(
            memberKey: KeychainStore.loadMemberKey(),
            deviceToken: PushTokenStore.shared.deviceToken
        )
        done = true
    }

    /// ログアウト: 保存した認証情報とWebViewのログインCookieを消し、最初のWelcome画面に戻る。
    private func logout() {
        KeychainStore.clearCredentials()
        appState.memberKey = nil
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {}
        }
        appState.route = .welcome
        dismiss()
    }
}

/// 退会申請を中継サーバーへ送信する。
enum DeletionRequest {
    static func submit(memberKey: String?, deviceToken: String?) {
        let url = AppConfig.relayBaseURL.appendingPathComponent("/account/deletion-request")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "memberId": memberKey ?? "",
            "deviceToken": deviceToken ?? "",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
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

/// ロック画面(アイボリー・ミニマル)。Welcome画面と同じ背景・公式ロゴ・PRO SHOP キャプションに、
/// 黒塗りカプセルの「Face ID で解錠」ボタンを下部に配置。表示時に自動で生体認証を開始する。
/// パスコードへのフォールバックはシステムの Face ID シート側で提供される。
struct LockView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            IvoryBackground()

            VStack(spacing: 0) {
                Spacer()

                KemaLogoMark()

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        unlock()
                    } label: {
                        Label("Face ID で解錠", systemImage: "faceid")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(KemaTheme.ivory)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(KemaTheme.ink, in: Capsule())
                    }
                }
                .frame(maxWidth: 440)   // iPhone Duo等の広い画面でボタンが間延びしないよう上限
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity) // コンテンツは物理画面の中央寄せ
        }
        .ignoresSafeArea() // Duo内側画面でも物理画面の中央に揃える
        .preferredColorScheme(.light)
        .onAppear { unlock() }
    }

    private func unlock() {
        BiometricGate.authenticate { success in
            if success { appState.route = .web }
        }
    }
}
