package hair.kema.proshop

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import java.lang.ref.WeakReference

/** WebViewへの参照を保持し、通知タップや下部バーからの遷移に使う */
object WebController {
    var ref: WeakReference<WebView>? = null
    var pendingPath: String? = null

    fun load(path: String) {
        val web = ref?.get()
        if (web != null) {
            val url = if (path.startsWith("http")) path else AppConfig.BCART_URL + path
            web.post { web.loadUrl(url) }
        } else {
            pendingPath = path
        }
    }
}

/** ログインフォームからメール+パスワードを受け取るJSブリッジ */
class KemaBridge(context: Context) {
    private val appContext = context.applicationContext

    @JavascriptInterface
    fun capture(email: String, password: String) {
        if (email.contains("@") && password.isNotEmpty()) {
            CredentialStore.saveCredentials(appContext, email.trim(), password)
            Api.registerIfPossible(appContext)
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
fun createBcartWebView(context: Context, startPath: String, autoLogin: Boolean): WebView {
    val web = WebView(context)
    web.settings.javaScriptEnabled = true
    web.settings.domStorageEnabled = true
    web.settings.loadWithOverviewMode = true
    web.settings.useWideViewPort = true

    CookieManager.getInstance().setAcceptCookie(true)
    CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)

    web.addJavascriptInterface(KemaBridge(context), "KemaBridge")

    var pendingAutoLogin = autoLogin

    web.webViewClient = object : WebViewClient() {
        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
            super.onPageStarted(view, url, favicon)
        }

        override fun onPageFinished(view: WebView, url: String) {
            super.onPageFinished(view, url)
            view.evaluateJavascript(CAPTURE_JS, null)
            view.evaluateJavascript(MOBILE_FORM_JS, null)
            view.evaluateJavascript(HIDE_PLATFORM_JS, null)

            // 自動ログイン(方式B): ログイン画面で保存済み認証情報を入力・送信
            if (pendingAutoLogin && url.contains("login")) {
                val email = CredentialStore.loadEmail(context)
                val pass = CredentialStore.loadPassword(context)
                if (email != null && pass != null) {
                    pendingAutoLogin = false
                    view.evaluateJavascript(autoLoginJs(email, pass), null)
                }
            }

            // ログイン後ページに到達したら端末登録
            if (AppConfig.LOGGED_IN_PATH_HINTS.any { url.contains(it) }) {
                Api.registerIfPossible(context)
                CookieManager.getInstance().flush()
            }
        }
    }

    WebController.ref = WeakReference(web)
    val initial = WebController.pendingPath ?: startPath
    WebController.pendingPath = null
    web.loadUrl(if (initial.startsWith("http")) initial else AppConfig.BCART_URL + initial)
    return web
}

private fun jsString(s: String): String {
    val escaped = s.replace("\\", "\\\\").replace("'", "\\'")
        .replace("\n", "").replace("\r", "")
    return "'$escaped'"
}

private fun autoLoginJs(email: String, password: String): String = """
(function(){
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

private const val CAPTURE_JS = """
(function(){
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

private const val MOBILE_FORM_JS = """
(function(){
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

private const val HIDE_PLATFORM_JS = """
(function(){
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
