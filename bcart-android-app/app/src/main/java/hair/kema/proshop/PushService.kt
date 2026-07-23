package hair.kema.proshop

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** FCM受信サービス。通知の表示と、トークン更新時の中継サーバー登録を行う。 */
class PushService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        PushTokenStore.deviceToken = token
        Api.registerIfPossible(applicationContext)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val title = message.notification?.title ?: message.data["title"] ?: "KEMA PRO SHOP"
        val body = message.notification?.body ?: message.data["body"] ?: ""
        val url = message.data["url"]

        createNotificationChannel(this)

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (url != null) putExtra("url", url)
        }
        val pending = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, "default")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(System.currentTimeMillis().toInt(), notification)
    }

    companion object {
        fun createNotificationChannel(context: Context) {
            val channel = NotificationChannel(
                "default", "お知らせ", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "注文・出荷などのお知らせ" }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
