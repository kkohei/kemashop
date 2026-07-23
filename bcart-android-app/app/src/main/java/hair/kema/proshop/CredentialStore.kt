package hair.kema.proshop

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * ログイン認証情報(メール+パスワード)を Android Keystore で暗号化して保存する。
 * iOS版 KeychainStore と同じ役割(方式B: 生体認証でアプリ解錠→自動ログイン)。
 */
object CredentialStore {

    private fun prefs(context: Context): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context,
            "kema_secure_prefs",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun saveCredentials(context: Context, email: String, password: String) {
        prefs(context).edit().putString("email", email).putString("password", password).apply()
    }

    fun loadEmail(context: Context): String? = prefs(context).getString("email", null)

    fun loadPassword(context: Context): String? = prefs(context).getString("password", null)

    fun hasCredentials(context: Context): Boolean = loadPassword(context) != null

    fun clear(context: Context) {
        prefs(context).edit().clear().apply()
    }
}
