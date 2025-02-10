package jp.staff.posapp

// ▼ Android/Flutter関連のimport文をしっかり明記 ▼
import android.os.Build
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {

    /**
     * Flutterエンジンの初期化時に通知チャンネルを作成
     */
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 旧来の一部プラグインで必要な場合に呼ぶ (GeneratedPluginRegistrant) —
        // 最近のFlutterでは自動登録されるため必須ではありませんが、明示的に呼びたい場合は以下を有効に
        // GeneratedPluginRegistrant.registerWith(flutterEngine)

        createNotificationChannel()
    }

    /**
     * 通知チャンネル "orders" を作成する関数
     */
    private fun createNotificationChannel() {
        // Android 8.0 (API 26)以上でのみ通知チャンネルを作成
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "orders"
            val channelName = "Orders Channel"
            val channelDescription = "Channel for new orders notifications"

            // 重要度: HIGH (アラート音やヘッドアップ通知)
            val importance = NotificationManager.IMPORTANCE_HIGH

            val channel = NotificationChannel(channelId, channelName, importance)
            channel.description = channelDescription
            channel.enableLights(true)
            channel.enableVibration(true)

            // (任意) カスタム音を使う場合
            // val soundUri = Uri.parse("android.resource://${packageName}/${R.raw.notification_sound}")
            // val audioAttributes = AudioAttributes.Builder()
            //     .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            //     .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            //     .build()
            // channel.setSound(soundUri, audioAttributes)

            // NotificationManager を取得してチャンネルを登録
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
}
