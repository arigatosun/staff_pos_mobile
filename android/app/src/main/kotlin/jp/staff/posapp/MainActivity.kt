package jp.staff.posapp

import android.os.Build
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()
    }

    /**
     * 通知チャンネル "orders" を作成する関数
     * -> バックグラウンド通知で "notification_sound.mp3" を鳴らす
     */
    private fun createNotificationChannel() {
        // Android 8.0 (API 26)以上でのみ通知チャンネルを作成
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "orders"
            val channelName = "Orders Channel"
            val channelDescription = "Channel for new orders notifications"

            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(channelId, channelName, importance)
            channel.description = channelDescription
            channel.enableLights(true)
            channel.enableVibration(true)

            // ▼ カスタム音を設定（res/raw/notification_sound.mp3）
            val soundUri = Uri.parse("android.resource://$packageName/${R.raw.notification_sound}")
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)        // 通知用途
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            channel.setSound(soundUri, audioAttributes)

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
}
