package hair.kema.proshop

import android.Manifest
import android.content.Intent
import android.graphics.Color as AndroidColor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.google.firebase.messaging.FirebaseMessaging

enum class Route { Welcome, Web }

class MainActivity : FragmentActivity(), FileChooserHost {

    private var fileCallback: ValueCallback<Array<Uri>>? = null

    /** ファイル選択で一時的に画面を離れる間は再ロックしない */
    @Volatile var suppressRelock = false

    private val fileChooserLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result: ActivityResult ->
            suppressRelock = false
            val cb = fileCallback
            fileCallback = null
            cb?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data))
        }

    override fun launchFileChooser(intent: Intent, callback: ValueCallback<Array<Uri>>): Boolean {
        fileCallback?.onReceiveValue(null)   // 未完了の前回要求はキャンセル
        fileCallback = callback
        suppressRelock = true
        return try {
            fileChooserLauncher.launch(intent)
            true
        } catch (e: Exception) {
            suppressRelock = false
            fileCallback = null
            false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val light = SystemBarStyle.light(AndroidColor.TRANSPARENT, AndroidColor.TRANSPARENT)
        enableEdgeToEdge(statusBarStyle = light, navigationBarStyle = light)

        PushService.createNotificationChannel(this)
        WebController.setPending(intent?.getStringExtra("url"))

        // FCMトークンを取得して保持(登録はログイン後)
        FirebaseMessaging.getInstance().token.addOnSuccessListener {
            PushTokenStore.deviceToken = it
            Api.registerIfPossible(this)
        }

        setContent { App(this) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("url")?.let { WebController.load(it) }   // ショップ外URLは無視・ロック中は保留
    }
}

@Composable
fun App(activity: MainActivity) {
    val context = LocalContext.current
    val hasCreds = CredentialStore.hasCredentials(context)

    var route by remember { mutableStateOf(if (hasCreds) Route.Web else Route.Welcome) }
    // 認証情報がある起動直後はロック。解錠するまで WebView は生成しない(自動ログインを走らせない)
    var locked by remember { mutableStateOf(hasCreds) }
    var webMounted by remember { mutableStateOf(false) }
    var startPath by remember { mutableStateOf(AppConfig.LOGIN_PATH) }
    var showDeletionDone by remember { mutableStateOf(false) }

    WebController.locked = locked

    // 通知許可(Android 13+)
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33) {
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // アプリを離れたら再ロック(WebViewは破棄せずオーバーレイで隠す)
    val currentRoute by rememberUpdatedState(route)
    DisposableEffect(activity) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP && currentRoute == Route.Web &&
                !activity.suppressRelock && CredentialStore.hasCredentials(activity)
            ) {
                locked = true
                WebController.locked = true
            }
        }
        activity.lifecycle.addObserver(observer)
        onDispose { activity.lifecycle.removeObserver(observer) }
    }

    fun logout(unregister: Boolean = true) {
        if (unregister) Api.unregister(context)   // 認証情報を消す前に値を取り出して非同期送信
        CredentialStash.discard()
        CredentialStore.clear(context)
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
        WebController.pendingUrl = null
        WebController.autoLoginArmed = false
        locked = false
        WebController.locked = false
        webMounted = false
        route = Route.Welcome
    }

    Box(Modifier.fillMaxSize()) {
        when (route) {
            Route.Welcome -> WelcomeScreen(
                onLogin = { startPath = AppConfig.LOGIN_PATH; webMounted = true; route = Route.Web },
                onRegister = { startPath = AppConfig.REGISTER_PATH; webMounted = true; route = Route.Web },
            )
            Route.Web -> if (webMounted) {
                WebScreen(
                    activity = activity,
                    startPath = startPath,
                    autoLogin = CredentialStore.hasCredentials(context),
                    locked = locked,
                    backEnabled = !locked,
                    onLogout = { logout() },
                    onDeletionAccepted = {
                        Api.unregister(context)
                        logout(unregister = false)
                        showDeletionDone = true
                    },
                )
            }
        }

        if (route == Route.Web && locked) {
            LockScreen(
                activity = activity,
                onUnlocked = {
                    locked = false
                    WebController.locked = false
                    if (!webMounted) {
                        startPath = AppConfig.LOGIN_PATH
                        webMounted = true          // 初回解錠: ここで初めてWebViewを生成
                    } else {
                        WebController.autoLoginArmed = true   // セッション切れ時のみログイン画面で自動入力
                        WebController.consumePending()
                    }
                },
                onBack = { activity.moveTaskToBack(true) },
            )
        }
    }

    if (showDeletionDone) {
        AlertDialog(
            onDismissRequest = { showDeletionDone = false },
            title = { Text("申請を受け付けました") },
            text = { Text("退会申請を受け付けました。削除完了までお待ちください。ログアウトしました。") },
            confirmButton = { TextButton(onClick = { showDeletionDone = false }) { Text("OK") } },
        )
    }
}

// ---- WebView + 下部バー + 設定 ----

@Composable
fun WebScreen(
    activity: MainActivity,
    startPath: String,
    autoLogin: Boolean,
    locked: Boolean,
    backEnabled: Boolean,
    onLogout: () -> Unit,
    onDeletionAccepted: () -> Unit,
) {
    val context = LocalContext.current
    var showSettings by remember { mutableStateOf(false) }
    var showDeletionConfirm by remember { mutableStateOf(false) }
    var showDeletionFailed by remember { mutableStateOf(false) }

    // 設定ダイアログは Popup なのでロック画面の上に残る。ロック時は閉じる。
    LaunchedEffect(locked) {
        if (locked) {
            showSettings = false
            showDeletionConfirm = false
        }
    }

    // 戻る: 履歴があれば戻る。なければアプリを終了せずバックグラウンドへ(再ロックされる)
    BackHandler(enabled = backEnabled) {
        val web = WebController.ref?.get()
        if (web != null && web.canGoBack()) web.goBack() else activity.moveTaskToBack(true)
    }

    Column(Modifier.fillMaxSize().background(Color(0xFFFFFFFF)).systemBarsPadding()) {
        AndroidView(
            factory = { ctx -> createBcartWebView(ctx, startPath, autoLogin, activity) },
            onRelease = { web ->
                if (WebController.ref?.get() === web) WebController.ref = null
                web.stopLoading()
                web.destroy()
            },
            modifier = Modifier.weight(1f).fillMaxWidth(),
        )
        // 下部バー
        Row(
            Modifier.fillMaxWidth().background(Color(0xFFF7F3EA)).padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            BarItem("ホーム") { WebController.load("/") }
            BarItem("ログイン") { WebController.load(AppConfig.LOGIN_PATH) }
            BarItem("新規登録") { WebController.load(AppConfig.REGISTER_PATH) }
            BarItem("注文履歴") { WebController.load(AppConfig.ORDER_HISTORY_PATH) }
            BarItem("設定") { showSettings = true }
        }
    }

    if (showSettings) {
        AlertDialog(
            onDismissRequest = { showSettings = false },
            title = { Text("設定") },
            text = {
                Column {
                    Text("ログアウト(最初の画面に戻る)",
                        modifier = Modifier.fillMaxWidth().clickable {
                            showSettings = false; onLogout()
                        }.padding(vertical = 14.dp))
                    Text("退会(アカウント削除)を申請", color = Color(0xFFC0392B),
                        modifier = Modifier.fillMaxWidth().clickable {
                            showSettings = false; showDeletionConfirm = true
                        }.padding(vertical = 14.dp))
                }
            },
            confirmButton = {
                TextButton(onClick = { showSettings = false }) { Text("閉じる") }
            },
        )
    }

    if (showDeletionConfirm) {
        AlertDialog(
            onDismissRequest = { showDeletionConfirm = false },
            title = { Text("退会(アカウント削除)を申請します") },
            text = { Text("この操作でアカウント削除を申請します。数営業日以内に削除いたします。よろしいですか?") },
            confirmButton = {
                TextButton(onClick = {
                    showDeletionConfirm = false
                    Api.requestDeletion(context) { ok ->
                        if (ok) onDeletionAccepted() else showDeletionFailed = true
                    }
                }) { Text("申請する", color = Color(0xFFC0392B)) }
            },
            dismissButton = {
                TextButton(onClick = { showDeletionConfirm = false }) { Text("キャンセル") }
            },
        )
    }

    if (showDeletionFailed) {
        AlertDialog(
            onDismissRequest = { showDeletionFailed = false },
            title = { Text("申請できませんでした") },
            text = { Text("通信状況をご確認のうえ、もう一度お試しください。解決しない場合は info@kema.hair までご連絡ください。") },
            confirmButton = {
                TextButton(onClick = { showDeletionFailed = false }) { Text("OK") }
            },
        )
    }
}

@Composable
private fun BarItem(label: String, onClick: () -> Unit) {
    Box(
        Modifier.clickable(onClick = onClick).padding(horizontal = 6.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, fontSize = 12.sp, color = Color(0xFF2A2318), fontWeight = FontWeight.Medium)
    }
}
