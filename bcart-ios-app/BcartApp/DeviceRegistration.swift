import Foundation

/// 「会員キー + デバイストークン」を中継サーバーへ登録する。
enum DeviceRegistration {
    /// 会員キーとデバイストークンが揃っていれば登録する(順不同で呼ばれてよい)
    static func registerIfPossible() {
        guard let token = PushTokenStore.shared.deviceToken,
              let memberKey = KeychainStore.loadMemberKey() else { return }
        register(memberKey: memberKey, deviceToken: token)
    }

    static func register(memberKey: String, deviceToken: String) {
        let url = AppConfig.relayBaseURL.appendingPathComponent("/devices/register")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAppToken(&req)
        let body: [String: Any] = [
            "memberId": memberKey,
            "deviceToken": deviceToken,
            "platform": "ios",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error {
                print("端末登録失敗: \(error)")
            } else if let http = response as? HTTPURLResponse {
                print("端末登録: status=\(http.statusCode) member=\(memberKey)")
            }
        }.resume()
    }

    /// 端末登録を解除する(ログアウト・退会申請時)。memberKey は分かっていれば送る。
    static func unregister(memberKey: String?, deviceToken: String?) {
        guard let deviceToken, !deviceToken.isEmpty else { return }
        let url = AppConfig.relayBaseURL.appendingPathComponent("/devices/unregister")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAppToken(&req)
        var body: [String: Any] = ["deviceToken": deviceToken]
        if let memberKey, !memberKey.isEmpty { body["memberId"] = memberKey }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error {
                print("端末登録解除失敗: \(error)")
            } else if let http = response as? HTTPURLResponse {
                print("端末登録解除: status=\(http.statusCode)")
            }
        }.resume()
    }

    /// APP_REGISTER_SECRET が設定されていれば X-App-Token を付ける
    static func applyAppToken(_ req: inout URLRequest) {
        let secret = AppConfig.appRegisterSecret
        if !secret.isEmpty { req.setValue(secret, forHTTPHeaderField: "X-App-Token") }
    }
}
