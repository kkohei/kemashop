package hair.kema.proshop

import androidx.activity.compose.BackHandler
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver

// ---- ブランド配色(デザインB: アイボリー・ミニマル。ダークモードでも同一) ----
private val IvoryTop = Color(0xFFF7F1E6)
private val IvoryMid = Color(0xFFF3EAD9)
private val IvoryBottom = Color(0xFFEFE4D0)
private val Highlight = Color(0xFFFFFDF8)
private val InkBlack = Color(0xFF1A1612)
private val CaptionGold = Color(0xFF9A7D4A)

/** アイボリーの縦グラデーション + 上部のやわらかいハイライト */
@Composable
fun IvoryBackground(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(IvoryTop, IvoryMid, IvoryBottom)))
            .drawBehind {
                drawRect(
                    Brush.radialGradient(
                        colors = listOf(Highlight, Highlight.copy(alpha = 0f)),
                        center = Offset(size.width / 2f, 0f),
                        radius = size.width * 0.9f,
                    )
                )
            },
    ) { content() }
}

/** 公式ロゴ(画像そのまま)+「PRO SHOP」キャプション。KEMA/タグラインは再タイプセットしない */
@Composable
private fun BrandMark() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Image(
            painter = painterResource(R.drawable.kema_logo),
            contentDescription = "KEMA",
            modifier = Modifier.width(228.dp),
            contentScale = ContentScale.FillWidth,
        )
        Spacer(Modifier.height(20.dp))
        Text(
            "PRO SHOP",
            color = CaptionGold,
            fontSize = 10.sp,
            letterSpacing = 4.8.sp,
            fontWeight = FontWeight.Normal,
            modifier = Modifier.padding(start = 4.8.dp),   // letterSpacing の末尾余白ぶん視覚中央に補正
        )
    }
}

@Composable
private fun CapsuleFilled(label: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().height(50.dp),
        shape = RoundedCornerShape(999.dp),
        elevation = null,
        colors = ButtonDefaults.buttonColors(containerColor = InkBlack, contentColor = IvoryTop),
    ) { Text(label, fontSize = 16.sp, letterSpacing = 2.2.sp, fontWeight = FontWeight.Medium) }
}

@Composable
private fun CapsuleOutline(label: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().height(50.dp),
        shape = RoundedCornerShape(999.dp),
        elevation = null,
        border = BorderStroke(1.dp, InkBlack),
        colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent, contentColor = InkBlack),
    ) { Text(label, fontSize = 16.sp, letterSpacing = 2.2.sp, fontWeight = FontWeight.Medium) }
}

@Composable
fun WelcomeScreen(onLogin: () -> Unit, onRegister: () -> Unit) {
    IvoryBackground {
        Column(
            Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.weight(1f))
            BrandMark()
            Spacer(Modifier.weight(1f))
            CapsuleFilled("ログイン", onLogin)
            Spacer(Modifier.height(14.dp))
            CapsuleOutline("新規登録", onRegister)
            Spacer(Modifier.height(32.dp))
        }
    }
}

// ---- 生体認証ロック(WebViewの上に重ねるオーバーレイ) ----

@Composable
fun LockScreen(activity: FragmentActivity, onUnlocked: () -> Unit, onBack: () -> Unit) {
    val unlocked = rememberUpdatedState(onUnlocked)

    fun authenticate() {
        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(activity, executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    unlocked.value()
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

    // 画面が前面にある時に表示された場合は即認証。バックグラウンド中にロックされた場合は復帰時(ON_RESUME)に1回だけ認証
    val authPending = remember { java.util.concurrent.atomic.AtomicBoolean(false) }
    LaunchedEffect(Unit) {
        if (activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) authenticate()
        else authPending.set(true)
    }
    DisposableEffect(activity) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME && authPending.getAndSet(false)) {
                authenticate()
            }
        }
        activity.lifecycle.addObserver(observer)
        onDispose { activity.lifecycle.removeObserver(observer) }
    }

    // 戻るでアプリを終了(=WebView破棄)させず、バックグラウンドへ
    BackHandler(onBack = onBack)

    IvoryBackground(
        // 下層のWebViewへタッチを通さない
        Modifier.pointerInput(Unit) {
            awaitPointerEventScope {
                while (true) awaitPointerEvent().changes.forEach { it.consume() }
            }
        }
    ) {
        Column(
            Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.weight(1f))
            BrandMark()
            Spacer(Modifier.weight(1f))
            CapsuleFilled("ロックを解除") { authenticate() }
            Spacer(Modifier.height(32.dp))
        }
    }
}
