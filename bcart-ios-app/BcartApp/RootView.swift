import SwiftUI
import WebKit

/// ルート画面。状態に応じて Welcome / ロック / WebView を切り替える。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if appState.route == .welcome {
                WelcomeView()
            } else {
                // Welcome を抜けたら(.web / .locked)WebView と下部バーは常にマウントしたままにする。
                // ロック中も破棄しないので、カート/フォーム状態が保たれ、ロック中に届いた通知も処理できる。
                VStack(spacing: 0) {
                    BcartWebView()
                    BottomBar()
                }
                .allowsHitTesting(appState.route == .web)
                .accessibilityHidden(appState.route == .locked)
                // 設定シートは解錠中のみ(シートはオーバーレイより前面に出てしまうため、ロック時に閉じる)
                .sheet(isPresented: $appState.showSettings) {
                    SettingsView().environmentObject(appState)
                }

                // ロック画面はWebViewの上に重ねるオーバーレイ
                if appState.route == .locked {
                    LockView()
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            // バックグラウンドへ移動したら、認証情報がある場合は再ロック(WebViewは破棄しない)
            if newPhase == .background, KeychainStore.hasCredentials, appState.route == .web {
                appState.showSettings = false
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

/// 動きのあるアイボリー背景(Welcome / ロック画面で共通)。
/// 静的な IvoryBackground の上に、ごく淡い3層のアニメーションを重ねる:
///  1. シャンパン/ベージュ系のぼかした光だまりが、20〜40秒周期でゆっくり漂う(メッシュグラデーション風)
///  2. 約11秒ごとに、斜めの淡い光の帯(シーン)が一度だけ画面を横切る
///  3. 小さな金色の粒子がゆっくり上へ浮かび、左右にかすかに揺れる
/// 文字の可読性を損なわないよう、すべて低い不透明度に抑えている。
/// 「視差効果を減らす(Reduce Motion)」がオンの場合は静止画で表示する。
/// 画面が非表示・アプリが非アクティブの間はタイムラインを停止し、バッテリー消費を抑える。
struct AnimatedIvoryBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var startDate = Date()

    var body: some View {
        ZStack {
            IvoryBackground()

            if reduceMotion {
                // 静止フォールバック(動きなし・光の帯なし)
                IvoryAmbientLayer(time: 6, showsSheen: false)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                        paused: !(isVisible && scenePhase == .active))) { timeline in
                    IvoryAmbientLayer(time: timeline.date.timeIntervalSince(startDate), showsSheen: true)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

/// AnimatedIvoryBackground の描画本体。time(秒)から各要素の位置を決定的に計算する(フレームごとの乱数なし)。
private struct IvoryAmbientLayer: View {
    let time: Double
    let showsSheen: Bool

    private struct Blob {
        let color: Color
        let alpha: Double
        let center: CGPoint      // 画面に対する相対位置(0〜1)
        let amplitude: CGSize    // 漂う幅(画面に対する相対値)
        let period: CGSize       // x / y の周期(秒)
        let phase: Double
        let radius: CGFloat      // 画面の長辺に対する半径
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
    }

    private static let blobs: [Blob] = [
        Blob(color: rgb(0xec, 0xd8, 0xb0), alpha: 0.42, center: CGPoint(x: 0.22, y: 0.28),
             amplitude: CGSize(width: 0.16, height: 0.10), period: CGSize(width: 31, height: 23),
             phase: 0.0, radius: 0.55),
        Blob(color: rgb(0xff, 0xfb, 0xf2), alpha: 0.70, center: CGPoint(x: 0.78, y: 0.20),
             amplitude: CGSize(width: 0.12, height: 0.12), period: CGSize(width: 27, height: 37),
             phase: 1.7, radius: 0.50),
        Blob(color: rgb(0xe6, 0xcf, 0xa2), alpha: 0.32, center: CGPoint(x: 0.70, y: 0.78),
             amplitude: CGSize(width: 0.18, height: 0.08), period: CGSize(width: 39, height: 29),
             phase: 3.1, radius: 0.60),
        Blob(color: rgb(0xf3, 0xe4, 0xc6), alpha: 0.45, center: CGPoint(x: 0.25, y: 0.82),
             amplitude: CGSize(width: 0.10, height: 0.12), period: CGSize(width: 25, height: 33),
             phase: 4.6, radius: 0.48)
    ]

    private static let particleCount = 22
    private static let particleColor = rgb(0xb8, 0x96, 0x5a)

    /// 0〜1 の決定的な疑似乱数(粒子の初期配置用)
    private static func seeded(_ i: Int, _ k: Int) -> Double {
        let v = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            guard w > 0, h > 0 else { return }
            let longSide = max(w, h)
            let twoPi = Double.pi * 2

            // 1. 漂う光だまり
            for blob in Self.blobs {
                let x = w * (blob.center.x + blob.amplitude.width * CGFloat(sin(twoPi * time / Double(blob.period.width) + blob.phase)))
                let y = h * (blob.center.y + blob.amplitude.height * CGFloat(cos(twoPi * time / Double(blob.period.height) + blob.phase)))
                let r = longSide * blob.radius
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                let gradient = Gradient(stops: [
                    .init(color: blob.color.opacity(blob.alpha), location: 0),
                    .init(color: blob.color.opacity(blob.alpha * 0.45), location: 0.45),
                    .init(color: blob.color.opacity(0), location: 1)
                ])
                context.fill(Path(ellipseIn: rect),
                             with: .radialGradient(gradient, center: CGPoint(x: x, y: y),
                                                   startRadius: 0, endRadius: r))
            }

            // 2. 斜めの光の帯(周期の前半 40% だけ横切り、残りは休止)
            if showsSheen {
                let cycle = 11.0
                let progress = (time + 2.0).truncatingRemainder(dividingBy: cycle) / cycle
                let sweep = progress / 0.4
                if sweep < 1 {
                    let eased = sweep * sweep * (3 - 2 * sweep)              // smoothstep
                    let dir = CGVector(dx: 0.857, dy: 0.514)                 // 右下がりの斜め方向(単位ベクトル)
                    let band = longSide * 0.32
                    let travel = w * dir.dx + h * dir.dy
                    let s = -band + (travel + band * 2) * CGFloat(eased)
                    let c = CGPoint(x: dir.dx * s, y: dir.dy * s)
                    let start = CGPoint(x: c.x - dir.dx * band / 2, y: c.y - dir.dy * band / 2)
                    let end = CGPoint(x: c.x + dir.dx * band / 2, y: c.y + dir.dy * band / 2)
                    let strength = 0.26 * sin(Double.pi * sweep)            // 入り/抜けをフェード
                    let gradient = Gradient(stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(strength), location: 0.5),
                        .init(color: .white.opacity(0), location: 1)
                    ])
                    context.fill(Path(CGRect(origin: .zero, size: size)),
                                 with: .linearGradient(gradient, startPoint: start, endPoint: end))
                }
            }

            // 3. ゆっくり浮かぶ金色の粒子
            let travelH = Double(h) + 40
            for i in 0..<Self.particleCount {
                let baseX = Self.seeded(i, 1)
                let offset = Self.seeded(i, 2)
                let speed = Double(h) / (45 + 35 * Self.seeded(i, 3))   // 画面高さを45〜80秒で上昇
                let sizePt = 1.5 + 1.6 * Self.seeded(i, 4)
                let alpha = 0.14 + 0.22 * Self.seeded(i, 5)
                let swayPeriod = 7 + 6 * Self.seeded(i, 6)

                var yTravel = (time * speed + offset * travelH).truncatingRemainder(dividingBy: travelH)
                if yTravel < 0 { yTravel += travelH }
                let y = Double(h) + 20 - yTravel
                let x = baseX * Double(w) + 14 * sin(twoPi * time / swayPeriod + offset * twoPi)

                // 上下端に近いほど薄くする
                let edge = min(max(y / Double(h), 0), 1)
                let fade = min(edge / 0.15, (1 - edge) / 0.15, 1)
                guard fade > 0 else { continue }

                let rect = CGRect(x: x - sizePt / 2, y: y - sizePt / 2, width: sizePt, height: sizePt)
                context.fill(Path(ellipseIn: rect), with: .color(Self.particleColor.opacity(alpha * fade)))
            }
        }
    }
}

/// 公式ロゴ + 小さな「PRO SHOP」キャプション(Welcome / ロック画面で共通)。
struct KemaLogoMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

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
        // 表示時のやわらかなフェードイン(不透明度のみ。ロゴの拡大縮小・変形はしない)
        .opacity(reduceMotion || appeared ? 1 : 0)
        .onAppear {
            guard !appeared else { return }
            withAnimation(.easeOut(duration: 1.0)) { appeared = true }
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
            AnimatedIvoryBackground()

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
                // 申請後はログアウトして Welcome へ戻る
                Button("OK") {
                    performLocalLogout()
                    dismiss()
                }
            } message: {
                Text("退会申請を受け付けました。削除完了までお待ちください。")
            }
        }
    }

    /// 退会申請: 申請送信 → 端末登録解除。完了アラートのOK後に ログアウト → 閉じる。
    private func submit() {
        let member = KeychainStore.loadMemberKey()
        let token = PushTokenStore.shared.deviceToken
        DeletionRequest.submit(memberKey: member, deviceToken: token)
        DeviceRegistration.unregister(memberKey: member, deviceToken: token)
        done = true
    }

    /// ログアウト: 端末登録を解除し、保存した認証情報とWebViewのログインCookieを消し、最初のWelcome画面に戻る。
    private func logout() {
        DeviceRegistration.unregister(
            memberKey: KeychainStore.loadMemberKey(),
            deviceToken: PushTokenStore.shared.deviceToken
        )
        performLocalLogout()
        dismiss()
    }

    private func performLocalLogout() {
        KeychainStore.clearCredentials()
        appState.memberKey = nil
        appState.pendingPath = nil
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {}
        }
        appState.route = .welcome
    }
}

/// 退会申請を中継サーバーへ送信する。
enum DeletionRequest {
    static func submit(memberKey: String?, deviceToken: String?) {
        let url = AppConfig.relayBaseURL.appendingPathComponent("/account/deletion-request")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        DeviceRegistration.applyAppToken(&req)
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
            DeepLinkInbox.shared.push(path)   // 検証 → pendingPath 経由で開く
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
            AnimatedIvoryBackground()

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
