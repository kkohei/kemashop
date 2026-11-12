import Foundation

/// アプリ全体の設定。実値は環境に合わせて変更する。
enum AppConfig {
    /// Bカートの買い手向けサイトURL
    static let bcartURL = URL(string: "https://kema.i17.bcart.jp/")!

    /// 中継サーバー(XServer VPS)のベースURL
    static let relayBaseURL = URL(string: "https://relay.kema.hair")!

    /// アプリ内WebViewで開いてよい唯一のホスト(完全一致)。
    static let shopHost = "kema.i17.bcart.jp"

    /// 中継サーバーの APP_REGISTER_SECRET と **完全に一致** させること。
    /// 空文字のままだと X-App-Token ヘッダを送らない(サーバー側が
    /// ALLOW_LEGACY_DEVICE_REGISTER=true の間はこれでも動く)。
    /// 実際の値はここに記入するが、リポジトリにはコミットしないこと。
    static let appRegisterSecret = ""

    /// ログイン状態の判定に使うURL条件(パスの部分一致)。
    /// 認証情報の保存と端末登録は、ここに一致する店舗ページへ到達した後にのみ行う。
    /// "/order" や "/member" は未ログインでも現れうる(例: /member_regist 等)ため除外し、
    /// アプリで実際に使っているマイページ(/mypage.php)のみを対象にした。
    /// ログイン後の着地先が他のパスならここに追加する(広すぎるパターンは避けること)。
    static let loggedInPathHints = ["/mypage"]

    /// URL が店舗ホスト(http/https かつホスト完全一致)か
    static func isShopURL(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return false }
        return host == shopHost
    }

    /// 通知・下部バー・ディープリンク・開始パス共通の検証。
    /// 相対パス、または店舗ホストの URL のみ許可し、解決後の URL を返す。それ以外は nil。
    static func shopURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw, relativeTo: bcartURL)?.absoluteURL,
              isShopURL(url) else { return nil }
        return url
    }

    // 下部バーのボタンが開くパス(bcartURL からの相対パス)
    // TODO: 実際のBカートのURLに合わせて確定する。
    static let loginPath = "/login.php"         // ログイン画面
    static let registerPath = "/regist.php"     // 新規会員登録
    static let orderHistoryPath = "/mypage.php" // 注文履歴(マイページ)
}
