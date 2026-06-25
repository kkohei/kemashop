import Foundation
import Security

/// 会員キー(email等)を Keychain に安全に保存する。
/// ※方式A(Cookie保持)ではパスワードは保存しない。保存するのは識別子のみ。
enum KeychainStore {
    private static let service = "jp.example.bcart"
    private static let memberKeyAccount = "memberKey"

    static func saveMemberKey(_ value: String) {
        save(account: memberKeyAccount, value: value)
    }

    static func loadMemberKey() -> String? {
        load(account: memberKeyAccount)
    }

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
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
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
