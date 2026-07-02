import Foundation
import Security

/// ログイン認証情報(メール+パスワード)を Keychain に安全に保存する。
/// アプリ自体を Face ID でロックした上で、この認証情報を使って自動ログインする(方式B)。
enum KeychainStore {
    private static let service = "kema.Bcartapp"
    private static let emailAccount = "email"
    private static let passwordAccount = "password"

    /// メール+パスワードを保存
    static func saveCredentials(email: String, password: String) {
        save(account: emailAccount, value: email)
        save(account: passwordAccount, value: password)
    }

    /// 保存済みの認証情報を取得(無ければ nil)
    static func loadCredentials() -> (email: String, password: String)? {
        guard let e = load(account: emailAccount),
              let p = load(account: passwordAccount) else { return nil }
        return (e, p)
    }

    /// 認証情報が保存済みか
    static var hasCredentials: Bool { load(account: passwordAccount) != nil }

    // 会員キー(= email)。端末登録に使用。
    static func loadMemberKey() -> String? { load(account: emailAccount) }
    static func saveMemberKey(_ value: String) { save(account: emailAccount, value: value) }

    // MARK: - 汎用

    private static func save(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
