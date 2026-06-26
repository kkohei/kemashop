import Foundation

/// アプリ全体の設定。実値は環境に合わせて変更する。
enum AppConfig {
    /// Bカートの買い手向けサイトURL
    static let bcartURL = URL(string: "https://kema.i17.bcart.jp/")!

    /// 中継サーバー(XServer VPS)のベースURL
    static let relayBaseURL = URL(string: "https://relay.kema.hair")!

    /// ログイン状態の判定に使うURL条件。
    /// ログイン後にのみ現れるパス(例: マイページ)を含むかで判定する。
    /// TODO: 実際のBカートのログイン後URLに合わせて調整。
    static let loggedInPathHints = ["/mypage", "/order", "/member"]
}
