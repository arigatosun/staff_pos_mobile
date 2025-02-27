// lib/services/notification_service.dart を新規作成
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  static AndroidNotificationChannel channel = const AndroidNotificationChannel(
    'orders', // ID
    '注文通知', // タイトル
    description: '新しい注文の通知です', // 説明
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('notification_sound'),
    enableVibration: true,
  );

  static Future<void> initialize() async {
    // Android設定
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS設定
    final DarwinInitializationSettings iOSSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    // 初期化
    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iOSSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('通知タップ: ${response.payload}');
      },
    );

    // Android通知チャンネルの作成
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // フォアグラウンド時に通知を表示するメソッド
  static Future<void> showNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.max,
            priority: Priority.high,
            sound: channel.sound,
            playSound: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'notification_sound.wav',
          ),
        ),
        payload: message.data['orderId'],
      );
    }
  }
}