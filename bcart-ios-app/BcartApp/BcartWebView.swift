import SwiftUI
import WebKit

/// Bカートを表示する WKWebView。
/// - 永続データストアでログインCookie(「ログイン状態を保存する」)を保持(方式A)
/// - ログインフォーム送信時にメールアドレスを捕捉し、会員キーとして登録
/// - プッシュ通知タップ時のディープリンクで該当ページへ遷移
struct BcartWebView: UIViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator { Coordinator(appState: appState) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "memberCapture")
        controller.addUserScript(
            WKUserScript(source: Self.captureJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // 永続Cookie(ログイン保持)
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        webView.load(URLRequest(url: AppConfig.bcartURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let appState: AppState
        weak var webView: WKWebView?

        init(appState: AppState) {
            self.appState = appState
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleDeepLink(_:)), name: .openDeepLink, object: nil
            )
        }

        @objc func reload() {
            webView?.reload()
        }

        @objc func handleDeepLink(_ note: Notification) {
            guard let path = note.object as? String,
                  let url = URL(string: path, relativeTo: AppConfig.bcartURL) else { return }
            webView?.load(URLRequest(url: url))
        }

        // JS からメールアドレスを受け取り、会員キーとして登録
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "memberCapture",
                  let email = (message.body as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !email.isEmpty else { return }
            appState.memberKey = email
            DeviceRegistration.registerIfPossible()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            // ログイン後ページに到達したら(会員キーが既知なら)端末登録を試みる
            if let path = webView.url?.path,
               AppConfig.loggedInPathHints.contains(where: { path.contains($0) }) {
                DeviceRegistration.registerIfPossible()
            }
        }
    }

    /// ログインフォーム送信時にメールアドレスを捕捉するJS。
    /// input[type=email] か name/id に "mail" を含む入力の値を読む。
    /// TODO: 実際のBカートのログインフォームのフィールド名に合わせて精緻化。
    static let captureJS = """
    (function(){
      function findEmail(){
        var inputs = document.querySelectorAll('input');
        for (var i=0;i<inputs.length;i++){
          var el = inputs[i];
          var t = (el.type||'').toLowerCase();
          var n = ((el.name||'')+(el.id||'')).toLowerCase();
          if (t==='email' || n.indexOf('mail')>=0){
            if (el.value && el.value.indexOf('@')>0) return el.value.trim();
          }
        }
        return null;
      }
      document.addEventListener('submit', function(){
        var email = findEmail();
        if (email){ try { window.webkit.messageHandlers.memberCapture.postMessage(email); } catch(e){} }
      }, true);
    })();
    """
}
