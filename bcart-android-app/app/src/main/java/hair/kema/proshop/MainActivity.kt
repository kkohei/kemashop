package hair.kema.proshop

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.webkit.CookieManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.google.firebase.messaging.FirebaseMessaging

enum class Route { Welcome, Locked, Web }

class MainActivity : FragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PushService.createNotificationChannel(this)
        intent?.getStringExtra("url")?.let { WebController.pendingPath = it }

        // FCMトークンを取得して保持(登録はログイン後)
        FirebaseMessaging.getInstance().token.addOnSuccessListener {
            PushTokenStore.deviceToken = it
            Api.registerIfPossible(this)
        }

        setContent { App(this) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("url")?.let { WebController.load(it) }
    }
}

@Composable
fun App(activity: FragmentActivity) {
    val context = LocalContext.current
    var route by remember {
        mutableStateOf(if (CredentialStore.hasCredentials(context)) Route.Locked else Route.Welcome)
    }
    var startPath by remember { mutableStateOf("/") }

    // 通知許可(Android 13+)
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33) {
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    when (route) {
        Route.Welcome -> WelcomeScreen(
            onLogin = { startPath = AppConfig.LOGIN_PATH; route = Route.Web },
            onRegister = { startPath = AppConfig.REGISTER_PATH; route = Route.Web },
        )
        Route.Locked -> LockScreen(activity) { route = Route.Web; startPath = AppConfig.LOGIN_PATH }
        Route.Web -> WebScreen(
            startPath = startPath,
            autoLogin = CredentialStore.hasCredentials(context),
            onLogout = {
                CredentialStore.clear(context)
                CookieManager.getInstance().removeAllCookies(null)
                CookieManager.getInstance().flush()
                route = Route.Welcome
            },
        )
    }
}

// ---- Welcome(ゴールドの流れる背景 + ロゴ + ボタン) ----

@Composable
fun FlowingGoldBackground(modifier: Modifier = Modifier) {
    val paleGold = Color(0xFFE3BD6B)
    val gold = Color(0xFFB88529)
    val roseGold = Color(0xFFC78566)
    val deepGold = Color(0xFF805921)

    val transition = rememberInfiniteTransition(label = "gold")
    val t by transition.animateFloat(
        initialValue = 0f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(9000, easing = LinearEasing)),
        label = "t",
    )
    val dx = (kotlin.math.sin(t * 2 * Math.PI) * 400).toFloat()
    val dy = (kotlin.math.cos(t * 2 * Math.PI) * 400).toFloat()

    Box(
        modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    colors = listOf(paleGold, gold, roseGold, deepGold),
                    start = Offset(0f + dx, 0f + dy),
                    end = Offset(1200f - dx, 2200f - dy),
                )
            )
    )
}

@Composable
fun WelcomeScreen(onLogin: () -> Unit, onRegister: () -> Unit) {
    Box(Modifier.fillMaxSize()) {
        FlowingGoldBackground()
        Column(
            Modifier.fillMaxSize().padding(horizontal = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.weight(1f))
            // ロゴ(テキスト版。画像に差し替え可)
            Box(
                Modifier.size(88.dp).border(3.dp, Color.White, RoundedCornerShape(18.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Text("K", color = Color.White, fontSize = 46.sp, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.height(18.dp))
            Text("KEMA", color = Color.White, fontSize = 44.sp,
                fontWeight = FontWeight.ExtraBold, letterSpacing = 10.sp)
            Text("PRO SHOP", color = Color.White.copy(alpha = 0.95f),
                fontSize = 16.sp, letterSpacing = 8.sp)
            Spacer(Modifier.weight(1f))

            Button(
                onClick = onLogin,
                modifier = Modifier.fillMaxWidth().height(54.dp),
                shape = RoundedCornerShape(999.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White, contentColor = Color.Black),
            ) { Text("ログイン", fontSize = 17.sp, fontWeight = FontWeight.Bold) }

            Spacer(Modifier.height(14.dp))

            Button(
                onClick = onRegister,
                modifier = Modifier
                    .fillMaxWidth().height(54.dp)
                    .border(2.dp, Color.White.copy(alpha = 0.9f), RoundedCornerShape(999.dp)),
                shape = RoundedCornerShape(999.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White.copy(alpha = 0.12f), contentColor = Color.White),
            ) { Text("新規登録", fontSize = 17.sp, fontWeight = FontWeight.Bold) }

            Spacer(Modifier.height(50.dp))
        }
    }
}

// ---- 生体認証ロック ----

@Composable
fun LockScreen(activity: FragmentActivity, onUnlocked: () -> Unit) {
    fun authenticate() {
        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(activity, executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    onUnlocked()
                }
            })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("KEMA PRO SHOP")
            .setSubtitle("ロックを解除します")
            .setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL
            )
            .build()
        prompt.authenticate(info)
    }

    LaunchedEffect(Unit) { authenticate() }

    Box(Modifier.fillMaxSize().background(Color(0xFFFFFDF8)), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("KEMA PRO SHOP", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(20.dp))
            Button(
                onClick = { authenticate() },
                shape = RoundedCornerShape(999.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFA9781A)),
            ) { Text("生体認証で解錠") }
        }
    }
}

// ---- WebView + 下部バー + 設定 ----

@Composable
fun WebScreen(startPath: String, autoLogin: Boolean, onLogout: () -> Unit) {
    val context = LocalContext.current
    var showSettings by remember { mutableStateOf(false) }
    var showDeletionConfirm by remember { mutableStateOf(false) }
    var showDeletionDone by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().navigationBarsPadding()) {
        AndroidView(
            factory = { ctx -> createBcartWebView(ctx, startPath, autoLogin) },
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
                    Api.requestDeletion(context)
                    showDeletionConfirm = false
                    showDeletionDone = true
                }) { Text("申請する", color = Color(0xFFC0392B)) }
            },
            dismissButton = {
                TextButton(onClick = { showDeletionConfirm = false }) { Text("キャンセル") }
            },
        )
    }

    if (showDeletionDone) {
        AlertDialog(
            onDismissRequest = { showDeletionDone = false },
            title = { Text("申請を受け付けました") },
            text = { Text("退会申請を受け付けました。削除完了までお待ちください。") },
            confirmButton = {
                TextButton(onClick = { showDeletionDone = false }) { Text("OK") }
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
