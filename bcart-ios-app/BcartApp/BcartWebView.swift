import SwiftUI
import WebKit
import QuickLook
import Combine

/// Bカートを表示する WKWebView。
/// - ログインフォーム送信時に メール+パスワード を一時保持し、ログイン後ページへ到達してから Keychain に保存
/// - 店舗ホスト(kema.i17.bcart.jp)以外はアプリ内で開かず Safari へ
/// - PDF/添付ファイルは WKDownload で一時保存し QuickLook でプレビュー
/// - 起動時、保存済み認証情報があればログイン画面を開いて自動入力・自動送信(方式B: Face IDでログイン)
/// - プッシュ通知タップ時のディープリンクで該当ページへ遷移
struct BcartWebView: UIViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator { Coordinator(appState: appState) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "memberCapture")
        controller.addUserScript(
            WKUserScript(source: Coordinator.captureJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        // アプリ内でのみ、新規登録/ログインフォームをモバイル最適化
        controller.addUserScript(
            WKUserScript(source: Coordinator.mobileFormJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        // App Store審査対策: 他プラットフォーム(Android等)への言及ブロックを隠す
        controller.addUserScript(
            WKUserScript(source: Coordinator.hidePlatformJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // 永続Cookie
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator   // JSのalert/confirm表示・target=_blank対応
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
        let url = AppConfig.shopURL(from: start) ?? AppConfig.bcartURL
        webView.load(URLRequest(url: url))
        context.coordinator.consumePendingIfPossible()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate, WKDownloadDelegate {
        let appState: AppState
        weak var webView: WKWebView?
        var pendingAutoLogin = false
        /// 自動ログインを送信した直後(次のページ読込完了までは保留中のディープリンクを開かない)
        private var autoLoginInFlight = false
        private var cancellables = Set<AnyCancellable>()

        /// 送信されたが未確定の認証情報。ログイン後ページへ到達するまで Keychain には保存しない。
        private var stashed: (email: String, password: String, at: Date)?
        private static let stashLifetime: TimeInterval = 120

        // ダウンロード関連
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]
        private var previewer: DownloadPreviewer?
        private static let downloadRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kema-downloads", isDirectory: true)

        init(appState: AppState) {
            self.appState = appState
            super.init()
            // 前回の取り残しファイルを掃除
            try? FileManager.default.removeItem(at: Self.downloadRoot)
            // 解錠(.web)かつ保留パスがあれば開く。ロックされたら開いているプレビューを閉じる。
            // (appState は強参照だが appState → Coordinator の参照は無いので循環しない)
            appState.$route.combineLatest(appState.$pendingPath)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] route, _ in
                    if route == .locked { self?.previewer?.dismiss() }
                    self?.consumePendingIfPossible()
                }
                .store(in: &cancellables)
        }

        @objc func reload() { webView?.reload() }

        /// 保留中のパスを、WebView準備済み・解錠済み・自動ログイン完了後に1度だけ開く
        func consumePendingIfPossible() {
            guard appState.route == .web, let webView,
                  !pendingAutoLogin, !autoLoginInFlight,
                  let path = appState.pendingPath else { return }
            appState.pendingPath = nil
            guard let url = AppConfig.shopURL(from: path) else { return }
            webView.load(URLRequest(url: url))
        }

        // ログインフォーム送信時に メール+パスワード を受け取る(ここでは保存せず一時保持のみ)
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // 店舗のメインフレーム以外からのメッセージは無視
            guard message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.host.lowercased() == AppConfig.shopHost,
                  AppConfig.isShopURL(webView?.url),
                  message.name == "memberCapture",
                  let dict = message.body as? [String: Any],
                  let email = (dict["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let password = dict["password"] as? String,
                  !email.isEmpty, !password.isEmpty else { return }
            stashed = (email, password, Date())
        }

        /// Safari 等の外部アプリで開く
        private func openExternally(_ url: URL) {
            UIApplication.shared.open(url)
        }

        // mailto: / tel: などWebで開けないリンクは外部アプリ(メール/電話)で開く
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            let scheme = (url.scheme ?? "").lowercased()
            if scheme == "http" || scheme == "https" {
                guard AppConfig.isShopURL(url) else {
                    // 店舗以外のホストはアプリ内に留めない。
                    // メインフレーム/ユーザー操作のときだけ Safari を開き、iframe の読込は黙って止める。
                    if navigationAction.targetFrame?.isMainFrame ?? true
                        || navigationAction.navigationType == .linkActivated {
                        openExternally(url)
                    }
                    decisionHandler(.cancel)
                    return
                }
                // <a download> 等のダウンロード指定(iOS 14.5+)
                if navigationAction.shouldPerformDownload {
                    decisionHandler(.download)
                    return
                }
                decisionHandler(.allow)
                return
            }
            if scheme != "about" && scheme != "blob" {
                openExternally(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // PDF・添付ファイルはダウンロードして QuickLook で表示する
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            let response = navigationResponse.response
            guard Self.shouldDownload(response: response, canShow: navigationResponse.canShowMIMEType) else {
                decisionHandler(.allow)
                return
            }
            // 店舗ホストからのレスポンスのみダウンロード(それ以外は取得せず中止)
            decisionHandler(AppConfig.isShopURL(response.url) ? .download : .cancel)
        }

        private static let downloadMIMETypes: Set<String> = [
            "application/pdf", "application/zip", "application/x-zip-compressed",
            "application/octet-stream", "text/csv",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ]

        private static func shouldDownload(response: URLResponse, canShow: Bool) -> Bool {
            if let http = response as? HTTPURLResponse,
               let disp = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
               disp.contains("attachment") {
                return true
            }
            let mime = (response.mimeType ?? "").lowercased()
            if downloadMIMETypes.contains(mime) { return true }
            return !canShow
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        // target="_blank" のリンクは同じWebView内で開く(未実装だと何も起きない)
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                let scheme = (url.scheme ?? "").lowercased()
                if AppConfig.isShopURL(url) {
                    webView.load(navigationAction.request)   // 店舗は同じWebViewで開く
                } else if scheme != "about" && scheme != "blob" {
                    openExternally(url)                      // 他ホスト/mailto等は外部で開く
                }
            }
            return nil
        }

        // MARK: - JSダイアログ(WKWebViewは未実装だと alert/confirm を無視してしまう)

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            guard let vc = Self.topViewController() else { completionHandler(); return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            vc.present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            guard let vc = Self.topViewController() else { completionHandler(false); return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            vc.present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            guard let vc = Self.topViewController() else { completionHandler(nil); return }
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                completionHandler(alert?.textFields?.first?.text)
            })
            vc.present(alert, animated: true)
        }

        /// 最前面のViewControllerを取得(アラート表示用)
        private static func topViewController() -> UIViewController? {
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            var top = window?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            autoLoginInFlight = false
            let isShop = AppConfig.isShopURL(webView.url)
            let path = (webView.url?.path ?? "").lowercased()
            let onLogin = path.contains("login")

            // 自動ログイン: 店舗のログイン画面が開いたら、保存済み認証情報を入力して送信
            if pendingAutoLogin, isShop, onLogin, let cred = KeychainStore.loadCredentials() {
                pendingAutoLogin = false
                autoLoginInFlight = true
                webView.evaluateJavaScript(Self.autoLoginJS(email: cred.email, password: cred.password))
                // フォームが送信されなかった場合に保留リンクを塞がないための保険
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.autoLoginInFlight = false
                    self?.consumePendingIfPossible()
                }
            }

            // 一時保持した認証情報の扱い:
            //  店舗のログイン/登録画面から離れた(成功や登録完了の着地) → Keychain保存 + 端末登録
            //  ログイン画面に留まった(失敗) / 120秒経過 → 破棄(既存の正しい認証情報は上書きしない)
            //  /mypage 以外の着地(トップなど)でも保存できるよう、hints のみには依存しない。
            let loggedIn = isShop && AppConfig.loggedInPathHints.contains(where: { path.contains($0) })
            let leftAuthPages = isShop && !onLogin && !path.contains("regist")
            if let st = stashed {
                if Date().timeIntervalSince(st.at) > Self.stashLifetime || (isShop && onLogin) {
                    stashed = nil
                } else if leftAuthPages {
                    stashed = nil
                    KeychainStore.saveCredentials(email: st.email, password: st.password)
                    appState.memberKey = st.email
                    DeviceRegistration.registerIfPossible()
                }
            }

            // 既存ログインでマイページ等に到達した場合も端末登録を試みる
            if loggedIn {
                DeviceRegistration.registerIfPossible()
            }

            consumePendingIfPossible()
        }

        // MARK: - ダウンロード(WKDownloadDelegate)

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            guard AppConfig.isShopURL(response.url) else { completionHandler(nil); return }
            var name = (suggestedFilename as NSString).lastPathComponent
                .replacingOccurrences(of: "/", with: "_")
            if name.isEmpty || name == "." || name == ".." { name = "download" }
            let dir = Self.downloadRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                completionHandler(nil)
                return
            }
            let dest = dir.appendingPathComponent(name)
            downloadDestinations[ObjectIdentifier(download)] = dest
            completionHandler(dest)
        }

        // ダウンロード中のリダイレクト先も店舗ホストに限定
        func download(
            _ download: WKDownload,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void
        ) {
            decisionHandler(AppConfig.isShopURL(request.url) ? .allow : .cancel)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let dest = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            // ロック中はプレビューを出さず破棄
            guard appState.route == .web, let vc = Self.topViewController() else {
                try? FileManager.default.removeItem(at: dest.deletingLastPathComponent())
                return
            }
            let previewer = DownloadPreviewer(fileURL: dest)
            self.previewer = previewer
            let ql = QLPreviewController()
            ql.dataSource = previewer
            ql.delegate = previewer
            previewer.controller = ql
            vc.present(ql, animated: true)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            if let dest = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) {
                try? FileManager.default.removeItem(at: dest.deletingLastPathComponent())
            }
            guard (error as NSError).code != NSURLErrorCancelled, let vc = Self.topViewController() else { return }
            let alert = UIAlertController(title: "ダウンロードできませんでした",
                                          message: "しばらくしてからもう一度お試しください。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            vc.present(alert, animated: true)
        }

        /// ログインフォームから メール+パスワード を捕捉するJS
        static let captureJS = """
        (function(){
          if (location.hostname !== 'kema.i17.bcart.jp') return;
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
            textarea {
              font-size:16px !important; box-sizing:border-box !important;
              padding:12px !important; border-radius:10px !important;
              color:#222 !important; background-color:#fff !important;
            }
            select {
              font-size:16px !important; box-sizing:border-box !important;
              color:#222 !important; background-color:#fff !important;
              height:48px !important; line-height:1.4 !important;
              padding:6px 12px !important; border-radius:10px !important;
              -webkit-appearance:menulist !important; appearance:menulist !important;
            }
            option { color:#222 !important; background-color:#fff !important; }
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
          function hasField(el){ return el && el.querySelector && !!el.querySelector('input:not([type=hidden]),select,textarea'); }
          // 目印テキストを直接含む要素を探す
          function findNoticeStart(){
            var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
            var n;
            while (n = w.nextNode()) {
              var v = n.nodeValue || '';
              if (v.indexOf('必ずご確認') >= 0 || v.indexOf('登録フォームを入力前') >= 0) return n.parentElement;
            }
            return null;
          }
          function run(){
            if (document.getElementById('app-regist-modal')) return;
            var start = findNoticeStart();
            var noticeNodes = [];
            if (start) {
              // 入力欄を含まない最大の親ブロックまで引き上げる(フィールドは絶対に含めない)
              while (start.parentElement && start.parentElement !== document.body && !hasField(start.parentElement)) {
                start = start.parentElement;
              }
              // start と、それに続く「入力欄を含まない」兄弟を注意書きとして集める
              var sib = start;
              while (sib) {
                if (hasField(sib)) break;
                var next = sib.nextElementSibling;
                noticeNodes.push(sib);
                sib = next;
              }
            }
            var noticeHTML = '';
            noticeNodes.forEach(function(n){ noticeHTML += n.outerHTML; n.style.display='none'; });
            if (!noticeHTML) noticeHTML = '<p>新規会員登録の前に、ご登録に関するご案内をご確認ください。</p>';

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

        /// App Store審査対策: 「推奨環境」など Android 等の他プラットフォーム表記を含むブロックを隠す。
        /// 入力欄を含む要素は隠さない安全設計。
        static let hidePlatformJS = """
        (function(){
          function hasField(el){ return el && el.querySelector && !!el.querySelector('input:not([type=hidden]),select,textarea'); }
          function run(){
            var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
            var n, targets = [];
            while (n = w.nextNode()) {
              var v = n.nodeValue || '';
              if (v.indexOf('Android') >= 0 || v.indexOf('推奨環境') >= 0) {
                var el = n.parentElement;
                while (el && el.parentElement && el.parentElement !== document.body && !hasField(el.parentElement)) {
                  el = el.parentElement;
                }
                if (el && !hasField(el)) targets.push(el);
              }
            }
            targets.forEach(function(el){ el.style.display = 'none'; });
          }
          if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', run); } else { run(); }
        })();
        """

        /// JS文字列リテラルとして安全にエスケープ(JSONエンコード。改行等もそのまま保持)
        static func jsString(_ s: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed]),
                  let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
            // U+2028/2029 は古いJS実装で文字列を壊すため念のためエスケープ
            return literal
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        }
    }
}

/// ダウンロードしたファイルの QuickLook プレビュー。閉じたら一時ファイルを削除する。
/// (QLPreviewController は dataSource/delegate を弱参照するため Coordinator が強参照で保持)
final class DownloadPreviewer: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    let fileURL: URL
    weak var controller: QLPreviewController?

    init(fileURL: URL) { self.fileURL = fileURL }

    func dismiss() {
        controller?.dismiss(animated: false) { [fileURL] in
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        fileURL as NSURL
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }
}
