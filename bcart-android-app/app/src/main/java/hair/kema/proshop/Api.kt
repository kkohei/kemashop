package hair.kema.proshop

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/** FCMデバイストークンの一時保持 */
object PushTokenStore {
    @Volatile var deviceToken: String? = null
}

/** 中継サーバーとの通信(端末登録・退会申請) */
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

    /** 退会(アカウント削除)申請 */
    fun requestDeletion(context: Context) {
        post(
            "/account/deletion-request",
            JSONObject()
                .put("memberId", CredentialStore.loadEmail(context) ?: "")
                .put("deviceToken", PushTokenStore.deviceToken ?: "")
        )
    }

    private fun post(path: String, body: JSONObject) {
        thread {
            try {
                val conn = URL(AppConfig.RELAY_BASE_URL + path).openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true
                conn.connectTimeout = 10000
                conn.readTimeout = 10000
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
                Log.i("KemaApi", "$path -> ${conn.responseCode}")
                conn.disconnect()
            } catch (e: Exception) {
                Log.w("KemaApi", "$path 失敗: ${e.message}")
            }
        }
    }
}
