import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io' show Platform;
import 'dart:math' as math;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();
  static final AudioPlayer _audioPlayer = AudioPlayer();

  // 重複防止のために処理済みメッセージIDを追跡
  static final Set<String> _processedMessageIds = {};

  // Android用の通知チャンネル設定
  static AndroidNotificationChannel channel = const AndroidNotificationChannel(
    'orders', // Firebase側で設定されているチャンネルID
    '注文通知', // ユーザーに表示されるチャンネル名
    description: '新しい注文の通知です', // 説明
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('notification_sound'), // 拡張子なし
  );

  static Future<void> initialize() async {
    try {
      // Android設定
      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS設定 - DarwinInitializationSettingsはiOS 10以降用
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

      // 通知初期化と通知タップ時のハンドラ設定
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          print('通知タップ: ${response.payload}');
          // タップ時の処理（必要に応じて追加）
          // 例：特定の画面に遷移するロジックを実装
        },
      );

      // Android通知チャンネルの作成
      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

        print('Androidの通知チャンネルを作成しました: ${channel.id}');
      }

      print('通知サービスが正常に初期化されました');
    } catch (e) {
      print('通知サービス初期化エラー: $e');
    }
  }

  // 通知を表示するメソッド（フォアグラウンド/バックグラウンド共通）
  static Future<void> showNotification(RemoteMessage message) async {
    try {
      final String messageId = message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();

      // 重複チェック - 同じメッセージIDが既に処理されていたらスキップ
      if (_processedMessageIds.contains(messageId)) {
        print('通知 ${messageId.substring(0, math.min(15, messageId.length))}... は既に処理済みです。スキップします。');
        return;
      }

      // 処理済みとしてマーク
      _processedMessageIds.add(messageId);

      // セットのサイズを制限（メモリ消費を防ぐため）
      if (_processedMessageIds.length > 100) {
        _processedMessageIds.remove(_processedMessageIds.first);
      }

      print('===== 通知表示処理開始 =====');
      print('MessageId: $messageId');
      print('通知データ: ${message.data}');
      print('通知オブジェクト: ${message.notification != null ? "あり" : "なし"}');

      RemoteNotification? notification = message.notification;

      // 通知タイトルと本文を決定（通知オブジェクトまたはデータから）
      final String title = notification?.title ??
          message.data['title'] ??
          '新しい注文';

      final String body = notification?.body ??
          message.data['body'] ??
          'テーブル ${message.data['tableName'] ?? ''} からの注文が入りました';

      print('表示する通知: タイトル=$title, 本文=$body');

      // 通知音の再生はシステムの通知機能に任せ、ここでは明示的に再生しない
      // LocalNotificationsPluginが自動的に通知音を処理するため

      // 通知ID - 同じIDの通知は上書きされるので、一意の値を使用
      final int notificationId = messageId.hashCode;

      // 通知を表示
      await _localNotifications.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: Importance.max,
              priority: Priority.high,
              enableVibration: true,
              sound: const RawResourceAndroidNotificationSound('notification_sound'),
              icon: '@mipmap/ic_launcher', // 通知アイコン
              playSound: true,
              enableLights: true
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true, // 通知をアラートとして表示
            presentBadge: true, // アプリアイコンにバッジを表示
            presentSound: true, // 通知音を再生
            sound: 'notification_sound.caf', // iOSのサウンドファイル名（.caf形式推奨）
            interruptionLevel: InterruptionLevel.active,
          ),
        ),
        payload: message.data['orderId'], // タップ時に渡されるデータ
      );
      print('===== 通知表示完了 =====');
    } catch (e) {
      print('通知表示エラー: $e');
    }
  }

  // 通知権限の確認と要求（必要に応じて使用）
  static Future<bool> requestNotificationPermissions() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('通知権限ステータス: ${settings.authorizationStatus}');

      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      print('通知権限リクエストエラー: $e');
      return false;
    }
  }

  // デバッグ用: 手動でテスト通知を表示
  static Future<void> showTestNotification() async {
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.hashCode,
        'テスト通知',
        'これはテスト通知です。正常に表示されていますか？',
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.max,
            priority: Priority.high,
            sound: const RawResourceAndroidNotificationSound('notification_sound'),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'notification_sound.caf',
          ),
        ),
      );
      print('テスト通知を表示しました');
    } catch (e) {
      print('テスト通知表示エラー: $e');
    }
  }

  // 実行済み通知IDのキャッシュをクリア（必要に応じて使用）
  static void clearProcessedMessageCache() {
    _processedMessageIds.clear();
    print('処理済み通知キャッシュをクリアしました');
  }
}