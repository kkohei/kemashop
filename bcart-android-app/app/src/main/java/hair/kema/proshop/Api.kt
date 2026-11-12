package hair.kema.proshop

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/** FCMデバイストークンの一時保持 */
object PushTokenStore {
    @Volatile var deviceToken: String? = null
}

/** 中継サーバーとの通信(端末登録・解除・退会申請) */
object Api {

    /** 会員キー(email)とFCMトークンが揃っていれば中継サーバーへ登録 */
    fun registerIfPossible(context: Context) {
        val token = PushTokenStore.deviceToken ?: return
        val email = CredentialStore.loadEmail(context) ?: return
        post(
            "/devices/register",
            JSONObject()
                .put("memberId", email)
                .put("deviceToken", token)
                .put("platform", "android")
        )
    }

    /** 端末登録の解除(ログアウト・退会申請時)。呼び出し時点の値を取り出して非同期送信する */
    fun unregister(context: Context, memberId: String? = null) {
        val token = PushTokenStore.deviceToken ?: return
        val member = memberId ?: CredentialStore.loadEmail(context) ?: ""
        unregister(token, member)
    }

    fun unregister(deviceToken: String, memberId: String) {
        post(
            "/devices/unregister",
            JSONObject().put("memberId", memberId).put("deviceToken", deviceToken)
        )
    }

    /** 退会(アカウント削除)申請。受理(2xx)なら onResult(true) をメインスレッドで呼ぶ */
    fun requestDeletion(context: Context, onResult: (Boolean) -> Unit) {
        post(
            "/account/deletion-request",
            JSONObject()
                .put("memberId", CredentialStore.loadEmail(context) ?: "")
                .put("deviceToken", PushTokenStore.deviceToken ?: ""),
            onResult,
        )
    }

    private fun post(path: String, body: JSONObject, onResult: ((Boolean) -> Unit)? = null) {
        thread {
            var ok = false
            try {
                val conn = URL(AppConfig.RELAY_BASE_URL + path).openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                if (AppConfig.appRegisterSecret.isNotEmpty()) {
                    conn.setRequestProperty("X-App-Token", AppConfig.appRegisterSecret)
                }
                conn.doOutput = true
                conn.connectTimeout = 10000
                conn.readTimeout = 10000
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
                val code = conn.responseCode
                ok = code in 200..299
                Log.i("KemaApi", "$path -> $code")
                conn.disconnect()
            } catch (e: Exception) {
                Log.w("KemaApi", "$path 失敗: ${e.message}")
            }
            onResult?.let { cb -> Handler(Looper.getMainLooper()).post { cb(ok) } }
        }
    }
}
