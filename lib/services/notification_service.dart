import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:staff_pos_app/services/supabase_manager.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();
  static final AudioPlayer _audioPlayer = AudioPlayer();

  // 重複防止のために処理済みメッセージIDを追跡
  static final Set<String> _processedMessageIds = {};

  // 最後に通知を表示した時間（短時間での連続通知を防止）
  static DateTime? _lastNotificationTime;

  // デバッグ用フラグ - 本番環境ではfalseにすること
  static bool debugAlwaysShowNotifications = false;

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
  static Future<void> showNotification(RemoteMessage message, {bool forceShowNotification = false}) async {
    try {
      // forceShowNotificationがtrueの場合は勤務状態チェックをスキップ
      if (!forceShowNotification) {
        // まず即座に勤務状態を確認（バックグラウンド対応）
        final currentStoreId = SupabaseManager.getLoggedInStoreId();
        final isWorkingDirectCheck = SupabaseManager.getWorkingStatus();

        print('通知受信: 即座の勤務状態チェック - 店舗ID=${currentStoreId}, 勤務状態=${isWorkingDirectCheck ? "勤務中" : "休憩中"}');

        // 勤務状態が休憩中で、デバッグモードでない場合は通知をスキップ
        if (currentStoreId != null && !isWorkingDirectCheck && !debugAlwaysShowNotifications) {
          print('即座のチェック: 休憩中のため通知をスキップします');
          return;
        }
      } else {
        print('強制通知モード: 勤務状態チェックをスキップします');
      }

      final String messageId = message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();

      // 重複チェック - 同じメッセージIDが既に処理されていたらスキップ
      if (_processedMessageIds.contains(messageId)) {
        print('通知 ${messageId.substring(0, math.min(15, messageId.length))}... は既に処理済みです。スキップします。');
        return;
      }

      // 短時間での連続通知を制限（オプション）
      if (_lastNotificationTime != null) {
        final timeSinceLastNotification = DateTime.now().difference(_lastNotificationTime!);
        if (timeSinceLastNotification.inSeconds < 2) { // 2秒以内の連続通知を制限
          print('直前の通知から${timeSinceLastNotification.inMilliseconds}msしか経過していないため、通知をスキップします');
          return;
        }
      }

      // データから店舗IDを取得
      final String? notificationStoreId = message.data['storeId'];
      final currentStoreId = SupabaseManager.getLoggedInStoreId();

      print('通知の店舗ID: $notificationStoreId');
      print('現在のログイン店舗ID: $currentStoreId');

      // 店舗IDが一致しない場合は通知をスキップ
      if (notificationStoreId != null && currentStoreId != null) {
        if (notificationStoreId != currentStoreId.toString()) {
          print('通知の店舗ID($notificationStoreId)が現在のログイン店舗ID($currentStoreId)と一致しないため、通知をスキップします');
          return;
        }

        // forceShowNotificationがtrueの場合は勤務状態チェックをスキップ
        if (!forceShowNotification) {
          // 勤務状態を確認 - 改良版のチェックロジック（データベース確認も含む）
          final isWorking = await _checkWorkingStatus(currentStoreId);
          if (!isWorking && !debugAlwaysShowNotifications) {
            print('勤務中ではないため、通知をスキップします');
            return;
          }
        }
      } else {
        // 店舗IDが不明な場合は安全策としてスキップ（表示しない）
        print('店舗IDが不明のため、通知をスキップします');
        return;
      }

      // 処理済みとしてマーク
      _processedMessageIds.add(messageId);
      _lastNotificationTime = DateTime.now();

      // セットのサイズを制限（メモリ消費を防ぐため）
      if (_processedMessageIds.length > 100) {
        _processedMessageIds.remove(_processedMessageIds.first);
      }

      print('===== 通知表示処理開始 =====');
      print('MessageId: $messageId');
      print('通知データ: ${message.data}');
      print('通知オブジェクト: ${message.notification != null ? "あり" : "なし"}');

      // メッセージからアイテム情報を抽出
      String itemsInfo = "";
      if (message.data.containsKey('items')) {
        try {
          final itemsString = message.data['items'].toString();
          // 簡易的な件数表示
          if (itemsString.contains('"quantity"')) {
            itemsInfo = "から${itemsString.split('"quantity"').length - 1}点の注文が入りました";
          }
        } catch (e) {
          print('アイテム情報抽出エラー: $e');
        }
      }

      RemoteNotification? notification = message.notification;

      // 通知タイトルと本文を決定（通知オブジェクトまたはデータから）
      final String title = notification?.title ??
          message.data['title'] ??
          '新しい注文';

      final String body = notification?.body ??
          message.data['body'] ??
          'テーブル ${message.data['tableName'] ?? ''} ${itemsInfo.isNotEmpty ? itemsInfo : "からの注文が入りました"}';

      print('表示する通知: タイトル=$title, 本文=$body');

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

  // 勤務状態を確認するメソッド - バックグラウンド対応版
  static Future<bool> _checkWorkingStatus(int storeId) async {
    try {
      // 優先的にローカルの勤務状態を確認（バックグラウンドでもアクセス可能）
      final localWorkingStatus = SupabaseManager.getWorkingStatus();

      // 勤務状態がfalseなら通知をスキップ（デバッグモードでない場合）
      if (!localWorkingStatus && !debugAlwaysShowNotifications) {
        print('ローカルの勤務状態が休憩中のため、通知をスキップします');
        return false;
      }

      // FCMトークンを取得
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        print('FCMトークンが取得できないため、ローカルの勤務状態を使用します');
        return localWorkingStatus; // ローカルの状態を信頼する
      }

      // バックグラウンドではデータベース接続が不安定な場合もあるため
      // 例外をキャッチして、その場合はローカルの状態を使用
      try {
        // トークンに関連付けられたデバイスIDを取得
        final deviceResponse = await supabase
            .from('pos_devices')
            .select('id')
            .eq('fcm_token', token)
            .eq('store_id', storeId)
            .limit(1);

        if (deviceResponse.isEmpty) {
          print('デバイスが店舗に登録されていないため、ローカルの勤務状態を使用します');
          return localWorkingStatus;
        }

        final deviceId = deviceResponse[0]['id'] as String;

        // 勤務状態を取得
        final statusResponse = await supabase
            .from('staff_work_status')
            .select('is_working')
            .eq('device_id', deviceId)
            .eq('store_id', storeId)
            .order('updated_at', ascending: false)
            .limit(1);

        final bool isWorking = statusResponse.isNotEmpty &&
            statusResponse[0]['is_working'] == true;

        print('データベースの勤務状態: ${isWorking ? "勤務中" : "勤務外"}');

        // ローカルの状態と違う場合、ローカルの状態を更新（同期）
        if (isWorking != localWorkingStatus) {
          await SupabaseManager.setWorkingStatus(isWorking);
          print('ローカルの勤務状態を更新: ${isWorking ? "勤務中" : "勤務外"}');
        }

        return isWorking;
      } catch (e) {
        print('データベース勤務状態の確認エラー: $e');
        print('代わりにローカルの勤務状態を使用: ${localWorkingStatus ? "勤務中" : "勤務外"}');
        return localWorkingStatus;
      }
    } catch (e) {
      print('勤務状態の確認エラー: $e');
      // エラー発生時はローカルの状態を返す
      return SupabaseManager.getWorkingStatus();
    }
  }

  // バックグラウンド用の簡易勤務状態チェック - データベースアクセスなしで高速判定
  static bool isWorkingQuickCheck() {
    try {
      // ローカルの勤務状態だけを高速チェック
      return SupabaseManager.getWorkingStatus();
    } catch (e) {
      print('クイック勤務状態チェックエラー: $e');
      return false; // エラー時は安全のためfalse
    }
  }

  // 特定のデバイスの勤務状態を取得（他のクラスから呼び出し可能）
  static Future<bool> isDeviceWorking() async {
    try {
      final currentStoreId = SupabaseManager.getLoggedInStoreId();
      if (currentStoreId == null) {
        return false;
      }

      return await _checkWorkingStatus(currentStoreId);
    } catch (e) {
      print('勤務状態確認エラー: $e');
      return false;
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
      // 勤務状態を確認（オプション）
      final isWorking = await isDeviceWorking();
      if (!isWorking && !debugAlwaysShowNotifications) {
        print('勤務中ではないため、テスト通知を表示できません');
        return;
      }

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
    _lastNotificationTime = null;
    print('処理済み通知キャッシュをクリアしました');
  }
}