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

/// 初回起動画面(アイボリー・ミニマル):
/// アイボリーの紙色グラデーション背景 + 公式ロゴ + PRO SHOP キャプション + ログイン/新規登録ボタン。
/// ライト/ダークモードに関わらず常にこのデザインで表示する。
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    private let ink   = Color(red: 0x1a / 255.0, green: 0x16 / 255.0, blue: 0x12 / 255.0)  // #1a1612
    private let ivory = Color(red: 0xf7 / 255.0, green: 0xf1 / 255.0, blue: 0xe6 / 255.0)  // #f7f1e6
    private let gold  = Color(red: 0x9a / 255.0, green: 0x7d / 255.0, blue: 0x4a / 255.0)  // #9a7d4a

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer()

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
                    .foregroundStyle(gold)
                    .padding(.top, 20)

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

    private var background: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0xf7 / 255.0, green: 0xf1 / 255.0, blue: 0xe6 / 255.0), location: 0),
                    .init(color: Color(red: 0xf3 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0), location: 0.48),
                    .init(color: Color(red: 0xef / 255.0, green: 0xe4 / 255.0, blue: 0xd0 / 255.0), location: 1)
                ],
                startPoint: .top, endPoint: .bottom)

            // 上部中央のやわらかなハイライト(ellipse 80% 60% at 50% 0%)
            GeometryReader { geo in
                RadialGradient(
                    colors: [Color(red: 1, green: 0xfd / 255.0, blue: 0xf8 / 255.0), .clear],
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea() // Duo内側画面でも物理画面の中央に揃える
        .onAppear { unlock() }
    }

    private func unlock() {
        BiometricGate.authenticate { success in
            if success { appState.route = .web }
        }
    }
}
