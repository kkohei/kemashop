import LocalAuthentication

/// Face ID / Touch ID でアプリ自体を解錠する。
/// 方式A: ログイン済みCookieはWebViewが保持するため、ここではアプリの「ロック解除」のみ行う。
enum BiometricGate {
    static func authenticate(reason: String = "ロックを解除します", completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = "パスコードを使用"

        var error: NSError?
        // 生体認証が使えない端末ではパスコードにフォールバック
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}
