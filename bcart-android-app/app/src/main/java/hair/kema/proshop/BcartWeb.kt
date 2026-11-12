package hair.kema.proshop

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.DownloadListener
import android.webkit.JavascriptInterface
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.Toast
import androidx.core.content.ContextCompat
import java.lang.ref.WeakReference
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** WebViewへの参照を保持し、通知タップや下部バーからの遷移に使う */
object WebController {
    var ref: WeakReference<WebView>? = null

    /** 解錠後に開くURL(ショップ内に解決済みのフルURLのみ保持) */
    @Volatile var pendingUrl: String? = null

    /** ロック中は true。ロック中の遷移要求は pendingUrl に退避する */
    @Volatile var locked: Boolean = false

    /** 自動ログインを実行してよいか(解錠操作ごとに武装、使用したら解除) */
    @Volatile var autoLoginArmed: Boolean = false

    /** 外部入力(通知extra等)から呼ぶ。ショップ外URLは無視する */
    fun load(raw: String) {
        val url = AppConfig.resolveShopUrl(raw) ?: return
        val web = ref?.get()
        if (web != null && !locked) {
            web.post { web.loadUrl(url) }
        } else {
            pendingUrl = url
        }
    }

    /** 外部入力を保留として登録(WebView生成前) */
    fun setPending(raw: String?) {
        AppConfig.resolveShopUrl(raw)?.let { pendingUrl = it }
    }

    /** 解錠後に保留中のURLがあれば開く */
    fun consumePending() {
        val url = pendingUrl ?: return
        pendingUrl = null
        val web = ref?.get() ?: return
        web.post { web.loadUrl(url) }
    }
}

/** ファイル選択(<input type=file>)を Activity Result API 側へ中継する */
interface FileChooserHost {
    /** 起動できたら true。callback は結果(またはキャンセル時 null)で必ず1回呼ぶこと */
    fun launchFileChooser(intent: Intent, callback: ValueCallback<Array<Uri>>): Boolean
}

/**
 * 入力されたメール+パスワードの一時保管(送信直後は保存しない)。
 * ログイン成功(ログイン以外のショップページへ遷移)を確認できた時だけ CredentialStore へ確定する。
 */
object CredentialStash {
    private const val TTL_MS = 120_000L
    private var email: String? = null
    private var password: String? = null
    private var at = 0L

    @Synchronized fun put(e: String, p: String) {
        email = e; password = p; at = System.currentTimeMillis()
    }

    @Synchronized fun discard() {
        email = null; password = null; at = 0L
    }

    /** 有効期限内なら取り出して破棄。期限切れ・なしは null */
    @Synchronized fun take(): Pair<String, String>? {
        val e = email; val p = password
        val fresh = System.currentTimeMillis() - at <= TTL_MS
        discard()
        return if (e != null && p != null && fresh) e to p else null
    }
}

/** ログインフォームからメール+パスワードを受け取るJSブリッジ */
class KemaBridge(context: Context, web: WebView) {
    private val appContext = context.applicationContext
    // WebView → JS interface → WebView の循環参照を避ける
    private val webRef = WeakReference(web)

    /** メインフレームの現在URLがショップか(JSスレッドからメインスレッドへ問い合わせ) */
    private fun mainFrameIsShop(): Boolean {
        val web = webRef.get() ?: return false
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return AppConfig.isShopUrl(web.url)
        }
        val result = java.util.concurrent.atomic.AtomicBoolean(false)
        val latch = CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            result.set(AppConfig.isShopUrl(web.url))
            latch.countDown()
        }
        return latch.await(1, TimeUnit.SECONDS) && result.get()
    }

    @JavascriptInterface
    fun capture(email: String, password: String) {
        if (!mainFrameIsShop()) return
        if (email.contains("@") && password.isNotEmpty()) {
            CredentialStash.put(email.trim(), password)   // ここでは保存しない
        }
    }
}

private fun openExternal(context: Context, uri: Uri) {
    val action = if (uri.scheme == "tel") Intent.ACTION_DIAL else Intent.ACTION_VIEW
    val intent = Intent(action, uri)
    if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (e: Exception) {
        Toast.makeText(context, "開けませんでした", Toast.LENGTH_SHORT).show()
    }
}

/** ログイン確認後に認証情報を確定保存し、端末登録する */
private fun commitStashedCredentials(context: Context) {
    val (email, pass) = CredentialStash.take() ?: return
    val old = CredentialStore.loadEmail(context)
    if (old != null && !old.equals(email, ignoreCase = true)) {
        Api.unregister(context, old)   // アカウント切替: 旧会員への紐付けを解除
    }
    CredentialStore.saveCredentials(context, email, pass)
    Api.registerIfPossible(context)
}

@SuppressLint("SetJavaScriptEnabled")
fun createBcartWebView(
    context: Context,
    startPath: String,
    autoLogin: Boolean,
    chooserHost: FileChooserHost,
): WebView {
    val web = WebView(context)
    web.settings.javaScriptEnabled = true
    web.settings.domStorageEnabled = true
    web.settings.loadWithOverviewMode = true
    web.settings.useWideViewPort = true
    web.settings.allowFileAccess = false
    web.settings.allowContentAccess = false
    web.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW

    CookieManager.getInstance().setAcceptCookie(true)
    CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)

    web.addJavascriptInterface(KemaBridge(context, web), "KemaBridge")
    WebController.autoLoginArmed = autoLogin

    web.webViewClient = object : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
            handleNavigation(view.context, request.url)

        @Deprecated("API 24 未満向け")
        override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
            handleNavigation(view.context, Uri.parse(url))

        /** true = WebViewでは読み込まない */
        private fun handleNavigation(ctx: Context, uri: Uri): Boolean {
            return when (uri.scheme?.lowercase()) {
                "http", "https" -> {
                    if (AppConfig.isShopHost(uri.host)) false
                    else { openExternal(ctx, uri); true }
                }
                "mailto", "tel", "sms" -> { openExternal(ctx, uri); true }
                "about", "blob" -> false
                else -> true   // intent:, file:, content:, javascript: 等は遮断
            }
        }

        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
            super.onPageStarted(view, url, favicon)
        }

        override fun onPageFinished(view: WebView, url: String) {
            super.onPageFinished(view, url)
            if (!AppConfig.isShopUrl(url)) return   // ショップ以外ではJS注入・認証処理をしない

            view.evaluateJavascript(CAPTURE_JS, null)
            view.evaluateJavascript(MOBILE_FORM_JS, null)
            view.evaluateJavascript(HIDE_PLATFORM_JS, null)

            val path = (Uri.parse(url).path ?: "").lowercase()
            val isLogin = path.contains("login")
            val isRegist = path.contains("regist")

            if (isLogin) {
                // 送信後もログイン画面のまま = 失敗とみなし、入力値は破棄(保存済みの正しい認証情報を上書きしない)
                CredentialStash.discard()
            } else if (!isRegist) {
                commitStashedCredentials(context)
            }

            // 自動ログイン(方式B): ショップのログイン画面でのみ、保存済み認証情報を入力・送信
            if (WebController.autoLoginArmed && isLogin) {
                val email = CredentialStore.loadEmail(context)
                val pass = CredentialStore.loadPassword(context)
                if (email != null && pass != null) {
                    WebController.autoLoginArmed = false
                    view.evaluateJavascript(autoLoginJs(email, pass), null)
                }
            }

            // ログイン後ページに到達したら端末登録
            if (AppConfig.LOGGED_IN_PATH_HINTS.any { path.contains(it) }) {
                Api.registerIfPossible(context)
                CookieManager.getInstance().flush()
            }
        }
    }

    web.setDownloadListener(DownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
        startDownload(context, url, userAgent, contentDisposition, mimeType)
    })

    web.webChromeClient = object : WebChromeClient() {
        private fun dialogHost(view: WebView): Activity? =
            (view.context as? Activity)?.takeIf { !it.isFinishing && !it.isDestroyed }

        private fun title(url: String?) = Uri.parse(url ?: "").host ?: "KEMA PRO SHOP"

        override fun onJsAlert(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
            val a = dialogHost(view) ?: run { result.cancel(); return true }
            AlertDialog.Builder(a).setTitle(title(url)).setMessage(message)
                .setPositiveButton("OK") { _, _ -> result.confirm() }
                .setOnCancelListener { result.cancel() }.show()
            return true
        }

        override fun onJsConfirm(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
            val a = dialogHost(view) ?: run { result.cancel(); return true }
            AlertDialog.Builder(a).setTitle(title(url)).setMessage(message)
                .setPositiveButton("OK") { _, _ -> result.confirm() }
                .setNegativeButton("キャンセル") { _, _ -> result.cancel() }
                .setOnCancelListener { result.cancel() }.show()
            return true
        }

        override fun onJsPrompt(
            view: WebView, url: String?, message: String?, defaultValue: String?, result: JsPromptResult
        ): Boolean {
            val a = dialogHost(view) ?: run { result.cancel(); return true }
            val input = EditText(a).apply { setText(defaultValue ?: "") }
            AlertDialog.Builder(a).setTitle(title(url)).setMessage(message).setView(input)
                .setPositiveButton("OK") { _, _ -> result.confirm(input.text.toString()) }
                .setNegativeButton("キャンセル") { _, _ -> result.cancel() }
                .setOnCancelListener { result.cancel() }.show()
            return true
        }

        override fun onShowFileChooser(
            webView: WebView,
            filePathCallback: ValueCallback<Array<Uri>>,
            fileChooserParams: FileChooserParams,
        ): Boolean {
            return try {
                if (!chooserHost.launchFileChooser(fileChooserParams.createIntent(), filePathCallback)) {
                    filePathCallback.onReceiveValue(null)
                }
                true
            } catch (e: Exception) {
                filePathCallback.onReceiveValue(null)
                true
            }
        }
    }

    WebController.ref = WeakReference(web)
    val initial = WebController.pendingUrl ?: AppConfig.resolveShopUrl(startPath) ?: AppConfig.BCART_URL
    WebController.pendingUrl = null
    web.loadUrl(initial)
    return web
}

/** ショップからのダウンロードは DownloadManager(アプリ専用領域)で保存し、完了後に開く */
private fun startDownload(
    context: Context, url: String, userAgent: String?, contentDisposition: String?, mimeType: String?
) {
    val uri = Uri.parse(url)
    val scheme = uri.scheme?.lowercase()
    if ((scheme == "http" || scheme == "https") && !AppConfig.isShopHost(uri.host)) {
        openExternal(context, uri)   // 他ホストは外部ブラウザへ(認証Cookieは渡さない)
        return
    }
    if (!AppConfig.isShopUrl(url)) {
        Toast.makeText(context, "このダウンロードには対応していません", Toast.LENGTH_SHORT).show()
        return
    }
    try {
        val name = URLUtil.guessFileName(url, contentDisposition, mimeType)
            .replace('/', '_').replace('\\', '_')
        val request = DownloadManager.Request(uri)
            .setTitle(name)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, name)
        if (!mimeType.isNullOrEmpty()) request.setMimeType(mimeType)
        CookieManager.getInstance().getCookie(url)?.let { request.addRequestHeader("Cookie", it) }
        if (!userAgent.isNullOrEmpty()) request.addRequestHeader("User-Agent", userAgent)

        val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val id = dm.enqueue(request)
        Toast.makeText(context, "ダウンロードを開始しました: $name", Toast.LENGTH_SHORT).show()

        val app = context.applicationContext
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                if (intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) != id) return
                try { app.unregisterReceiver(this) } catch (_: Exception) {}
                val fileUri = dm.getUriForDownloadedFile(id)
                if (fileUri == null) {
                    Toast.makeText(app, "ダウンロードに失敗しました", Toast.LENGTH_SHORT).show()
                    return
                }
                val open = Intent(Intent.ACTION_VIEW)
                    .setDataAndType(fileUri, dm.getMimeTypeForDownloadedFile(id) ?: "*/*")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                try { app.startActivity(open) } catch (_: Exception) {
                    Toast.makeText(app, "ダウンロードしました(通知から開けます)", Toast.LENGTH_LONG).show()
                }
            }
        }
        // DOWNLOAD_COMPLETE はシステム保護ブロードキャストのため exported 指定でも安全
        ContextCompat.registerReceiver(
            app, receiver, IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
            ContextCompat.RECEIVER_EXPORTED,
        )
    } catch (e: Exception) {
        Toast.makeText(context, "ダウンロードを開始できませんでした", Toast.LENGTH_SHORT).show()
    }
}

/** JS文字列リテラル化(JSONエスケープ。改行等も落とさず保持) */
private fun jsString(s: String): String =
    org.json.JSONObject.quote(s).replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")

private val SHOP_GUARD = "if (location.hostname !== '${AppConfig.shopHost}') return;"

private fun autoLoginJs(email: String, password: String): String = """
(function(){
  $SHOP_GUARD
  if ((location.pathname || '').toLowerCase().indexOf('login') < 0) return;
  var inputs=document.querySelectorAll('input'), ef=null, pf=null;
  for (var i=0;i<inputs.length;i++){
    var el=inputs[i], t=(el.type||'').toLowerCase(), n=((el.name||'')+(el.id||'')).toLowerCase();
    if (!ef && (t==='email'||t==='text'||n.indexOf('mail')>=0)) ef=el;
    if (!pf && t==='password') pf=el;
  }
  if (ef && pf){
    ef.value=${jsString(email)}; pf.value=${jsString(password)};
    ef.dispatchEvent(new Event('input',{bubbles:true}));
    pf.dispatchEvent(new Event('input',{bubbles:true}));
    var form=pf.form||ef.form;
    if (form){ if (form.requestSubmit) { form.requestSubmit(); } else { form.submit(); } }
  }
})();
"""

private val CAPTURE_JS = """
(function(){
  $SHOP_GUARD
  if (window.__kemaCapture) return; window.__kemaCapture = true;
  document.addEventListener('submit', function(){
    var email=null, pass=null, inputs=document.querySelectorAll('input');
    for (var i=0;i<inputs.length;i++){
      var el=inputs[i], t=(el.type||'').toLowerCase(), n=((el.name||'')+(el.id||'')).toLowerCase();
      if ((t==='email'||n.indexOf('mail')>=0) && el.value && el.value.indexOf('@')>0) email=el.value.trim();
      if (t==='password' && el.value) pass=el.value;
    }
    if (email && pass){ try { KemaBridge.capture(email, pass); } catch(e){} }
  }, true);
})();
"""

private val MOBILE_FORM_JS = """
(function(){
  $SHOP_GUARD
  var p = location.pathname || '';
  if (p.indexOf('regist') < 0 && p.indexOf('login') < 0) return;
  if (document.getElementById('app-mobile-style')) return;
  var css = 'input:not([type=checkbox]):not([type=radio]):not([type=submit]):not([type=button]),textarea{font-size:16px !important;box-sizing:border-box !important;padding:12px !important;border-radius:10px !important;color:#222 !important;background-color:#fff !important;}' +
    'select{font-size:16px !important;box-sizing:border-box !important;color:#222 !important;background-color:#fff !important;height:48px !important;line-height:1.4 !important;padding:6px 12px !important;border-radius:10px !important;}' +
    'option{color:#222 !important;background-color:#fff !important;}' +
    'input[type=checkbox],input[type=radio]{transform:scale(1.2);}' +
    'button,input[type=submit],input[type=button]{font-size:17px !important;padding:14px 22px !important;border-radius:999px !important;}';
  var s = document.createElement('style');
  s.id = 'app-mobile-style';
  s.textContent = css;
  (document.head || document.documentElement).appendChild(s);
})();
"""

private val HIDE_PLATFORM_JS = """
(function(){
  $SHOP_GUARD
  function hasField(el){ return el && el.querySelector && !!el.querySelector('input:not([type=hidden]),select,textarea'); }
  function run(){
    var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    var n, targets = [];
    while (n = w.nextNode()) {
      var v = n.nodeValue || '';
      if (v.indexOf('iOS') >= 0 || v.indexOf('推奨環境') >= 0) {
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
