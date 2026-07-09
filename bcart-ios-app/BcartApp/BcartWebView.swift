import SwiftUI
import WebKit

/// Bカートを表示する WKWebView。
/// - ログインフォーム送信時に メール+パスワード を捕捉し Keychain に保存
/// - 起動時、保存済み認証情報があればログイン画面を開いて自動入力・自動送信(方式B: Face IDでログイン)
/// - プッシュ通知タップ時のディープリンクで該当ページへ遷移
struct BcartWebView: UIViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator { Coordinator(appState: appState) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "memberCapture")
        controller.addUserScript(
            WKUserScript(source: Coordinator.captureJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
        // アプリ内でのみ、新規登録/ログインフォームをモバイル最適化
        controller.addUserScript(
            WKUserScript(source: Coordinator.mobileFormJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // 永続Cookie
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        // 認証情報が保存済みなら常にログイン画面を開いて自動ログイン。
        // 未登録なら Welcome 画面で選ばれたパス(新規登録/ログイン/ホーム)を開く。
        let start: String
        if KeychainStore.hasCredentials {
            context.coordinator.pendingAutoLogin = true
            start = AppConfig.loginPath
        } else {
            start = appState.startPath.isEmpty ? "/" : appState.startPath
        }
        let url = URL(string: start, relativeTo: AppConfig.bcartURL) ?? AppConfig.bcartURL
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let appState: AppState
        weak var webView: WKWebView?
        var pendingAutoLogin = false

        init(appState: AppState) {
            self.appState = appState
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleDeepLink(_:)), name: .openDeepLink, object: nil
            )
        }

        @objc func reload() { webView?.reload() }

        @objc func handleDeepLink(_ note: Notification) {
            guard let path = note.object as? String,
                  let url = URL(string: path, relativeTo: AppConfig.bcartURL) else { return }
            webView?.load(URLRequest(url: url))
        }

        // ログインフォーム送信時に メール+パスワード を受け取り保存
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "memberCapture",
                  let dict = message.body as? [String: Any],
                  let email = (dict["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let password = dict["password"] as? String,
                  !email.isEmpty, !password.isEmpty else { return }
            KeychainStore.saveCredentials(email: email, password: password)
            appState.memberKey = email
            DeviceRegistration.registerIfPossible()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            let path = webView.url?.path ?? ""

            // 自動ログイン: ログイン画面が開いたら、保存済み認証情報を入力して送信
            if pendingAutoLogin, path.contains("login"), let cred = KeychainStore.loadCredentials() {
                pendingAutoLogin = false
                webView.evaluateJavaScript(Self.autoLoginJS(email: cred.email, password: cred.password))
            }

            // ログイン後ページに到達したら端末登録を試みる
            if AppConfig.loggedInPathHints.contains(where: { path.contains($0) }) {
                DeviceRegistration.registerIfPossible()
            }
        }

        /// ログインフォームから メール+パスワード を捕捉するJS
        static let captureJS = """
        (function(){
          document.addEventListener('submit', function(){
            var email=null, pass=null, inputs=document.querySelectorAll('input');
            for (var i=0;i<inputs.length;i++){
              var el=inputs[i], t=(el.type||'').toLowerCase(), n=((el.name||'')+(el.id||'')).toLowerCase();
              if ((t==='email'||n.indexOf('mail')>=0) && el.value && el.value.indexOf('@')>0) email=el.value.trim();
              if (t==='password' && el.value) pass=el.value;
            }
            if (email && pass){ try { window.webkit.messageHandlers.memberCapture.postMessage({email:email, password:pass}); } catch(e){} }
          }, true);
        })();
        """

        /// 保存済み認証情報を入力して送信するJS
        static func autoLoginJS(email: String, password: String) -> String {
            return """
            (function(){
              var inputs=document.querySelectorAll('input'), ef=null, pf=null;
              for (var i=0;i<inputs.length;i++){
                var el=inputs[i], t=(el.type||'').toLowerCase(), n=((el.name||'')+(el.id||'')).toLowerCase();
                if (!ef && (t==='email'||t==='text'||n.indexOf('mail')>=0)) ef=el;
                if (!pf && t==='password') pf=el;
              }
              if (ef && pf){
                ef.value=\(jsString(email)); pf.value=\(jsString(password));
                ef.dispatchEvent(new Event('input',{bubbles:true}));
                pf.dispatchEvent(new Event('input',{bubbles:true}));
                var form=pf.form||ef.form;
                if (form){ if (form.requestSubmit) { form.requestSubmit(); } else { form.submit(); } }
              }
            })();
            """
        }

        /// アプリ内でのみ、新規登録/ログインフォームをモバイルネイティブ風に整えるCSSを注入。
        /// ページのパスが regist / login のときだけ適用(Web版・他ページには影響しない)。
        static let mobileFormJS = """
        (function(){
          var p = location.pathname || '';
          if (p.indexOf('regist') < 0 && p.indexOf('login') < 0) return;
          if (document.getElementById('app-mobile-style')) return;
          var css = `
            :root { -webkit-text-size-adjust: 100%; }
            body { background:#f7f3ea !important; margin:0 !important; color:#2a2a2a !important; }
            header, footer, #header, #footer, .header, .footer,
            .global-header, .global-footer, .gnav, .g-nav, .breadcrumb, .pankuzu { display:none !important; }
            #container, .container, main, #main, .contents, #contents {
              padding:18px !important; max-width:640px !important; margin:0 auto !important;
            }
            h1,h2,h3 { font-size:22px !important; font-weight:700 !important; margin:8px 0 18px !important; }
            input, select, textarea {
              font-size:16px !important; width:100% !important; box-sizing:border-box !important;
              padding:14px !important; margin:6px 0 16px !important;
              border:1px solid #dcd2b8 !important; border-radius:12px !important;
              background:#fff !important; -webkit-appearance:none !important;
            }
            input[type=checkbox], input[type=radio] {
              width:auto !important; margin:0 8px 0 0 !important; padding:0 !important; transform:scale(1.3);
            }
            button, input[type=submit], input[type=button], .btn, a.btn, a.button {
              width:100% !important; font-size:17px !important; font-weight:700 !important;
              padding:16px !important; border-radius:999px !important; border:none !important;
              background:linear-gradient(135deg,#b8860b,#8b6914) !important; color:#fff !important;
              margin:12px 0 !important; display:block !important; text-align:center !important;
              box-shadow:0 4px 12px rgba(139,105,20,0.25) !important;
            }
            table, tbody, tr, td, th { display:block !important; width:100% !important; box-sizing:border-box !important; }
            th { padding:6px 0 2px !important; font-weight:600 !important; text-align:left !important; font-size:14px !important; color:#6a5a2a !important; }
            td { padding:0 !important; }
          `;
          var s = document.createElement('style');
          s.id = 'app-mobile-style';
          s.textContent = css;
          (document.head || document.documentElement).appendChild(s);
        })();
        """

        /// JS文字列リテラルとして安全にエスケープ
        static func jsString(_ s: String) -> String {
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
            return "'\(escaped)'"
        }
    }
}
