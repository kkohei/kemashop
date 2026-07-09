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
        // アプリ内でのみ、新規登録ページの注意書きをモーダルに移して確認ボタンを出す
        controller.addUserScript(
            WKUserScript(source: Coordinator.registModalJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
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
          // 安全な最小CSS: 何も隠さず、入力欄とボタンを見やすく大きくするだけ
          var css = `
            input:not([type=checkbox]):not([type=radio]):not([type=submit]):not([type=button]),
            select, textarea {
              font-size:16px !important; box-sizing:border-box !important;
              padding:12px !important; border-radius:10px !important;
            }
            input[type=checkbox], input[type=radio] { transform:scale(1.2); }
            button, input[type=submit], input[type=button] {
              font-size:17px !important; padding:14px 22px !important; border-radius:999px !important;
            }
          `;
          var s = document.createElement('style');
          s.id = 'app-mobile-style';
          s.textContent = css;
          (document.head || document.documentElement).appendChild(s);
        })();
        """

        /// アプリ内でのみ、新規登録ページの「フォームの前にある注意書き」をモーダルに移し、
        /// 確認ボタンで閉じる。フォーム本体(inputを含む<form>)は絶対に隠さない安全設計。
        static let registModalJS = """
        (function(){
          if ((location.pathname||'').indexOf('regist') < 0) return;
          function run(){
            if (document.getElementById('app-regist-modal')) return;
            var form = document.querySelector('form');
            if (!form || !form.parentElement) return;
            var container = form.parentElement;
            var kids = Array.prototype.slice.call(container.children);
            var formIdx = kids.indexOf(form);
            // フォームの直前にある連続したテキストブロックだけを注意書きとみなす
            var noticeNodes = [];
            for (var i = formIdx - 1; i >= 0; i--) {
              var el = kids[i], tag = el.tagName.toLowerCase();
              if (tag==='script' || tag==='style') continue;
              var cn = (el.className||'') + ' ' + (el.id||'');
              if (tag==='header'||tag==='nav'||tag==='footer'||/header|nav|footer|breadcrumb|pankuzu/i.test(cn)) break;
              var txt = (el.innerText||'').trim();
              if (!txt) continue;
              noticeNodes.unshift(el);
            }
            var noticeHTML = '';
            noticeNodes.forEach(function(n){ noticeHTML += n.outerHTML; n.style.display='none'; });
            if (!noticeHTML) noticeHTML = '<p>新規会員登録を行います。内容をご確認のうえ、お進みください。</p>';

            var overlay = document.createElement('div');
            overlay.id = 'app-regist-modal';
            overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483000;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;padding:20px;';
            var card = document.createElement('div');
            card.style.cssText = 'background:#fff;border-radius:16px;max-width:560px;width:100%;max-height:78%;overflow:auto;padding:22px;-webkit-overflow-scrolling:touch;';
            var h = document.createElement('div');
            h.textContent = 'ご確認ください';
            h.style.cssText = 'font-size:18px;font-weight:700;margin-bottom:12px;color:#222;';
            var bodyEl = document.createElement('div');
            bodyEl.innerHTML = noticeHTML;
            bodyEl.style.cssText = 'font-size:15px;line-height:1.7;color:#333;';
            var btn = document.createElement('button');
            btn.textContent = '確認して登録に進む';
            btn.style.cssText = 'margin-top:18px;width:100%;padding:15px;border:none;border-radius:999px;background:linear-gradient(135deg,#b8860b,#8b6914);color:#fff;font-size:16px;font-weight:700;';
            btn.addEventListener('click', function(){ var o=document.getElementById('app-regist-modal'); if(o) o.remove(); });
            card.appendChild(h); card.appendChild(bodyEl); card.appendChild(btn);
            overlay.appendChild(card);
            document.body.appendChild(overlay);
          }
          if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', run); } else { run(); }
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
