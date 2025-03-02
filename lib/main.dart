import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:staff_pos_app/services/supabase_manager.dart';
import 'package:staff_pos_app/services/notification_service.dart';

// 日付フォーマットのロケールデータを初期化
import 'package:intl/date_symbol_data_local.dart';

// ローカライズのため
import 'package:flutter_localizations/flutter_localizations.dart';

// POSログインページをimport
import 'pages/pos_login/pos_login_page.dart';

import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// バックグラウンドメッセージを受信する際に呼ばれるハンドラ.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    print("===== バックグラウンド通知受信 =====");
    print("MessageId: ${message.messageId}");
    print("通知データ: ${message.data}");
    print("通知タイトル: ${message.notification?.title}");
    print("通知本文: ${message.notification?.body}");

    // バックグラウンドでのFirebase初期化は必須
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // SharedPreferences を初期化（必須）
    final prefs = await SharedPreferences.getInstance();

    // ★★★ 重要: 直接 SharedPreferences から勤務状態を取得 ★★★
    // SupabaseManager に依存せず、直接プリミティブな値を取得することで
    // 初期化の問題を回避します
    final isWorkingDirect = prefs.getBool('is_working') ?? false;
    final storeIdDirect = prefs.getInt('current_store_id');

    print("バックグラウンド通知チェック（直接取得）: 店舗ID=$storeIdDirect, 勤務状態=${isWorkingDirect ? '勤務中' : '休憩中'}");

    // 勤務中でない場合は即座にリターン（直接取得した値を使用）
    if (!isWorkingDirect && !NotificationService.debugAlwaysShowNotifications) {
      print("勤務中ではないため通知を表示しません（直接チェック）");
      return;
    }

    // SupabaseManager を初期化
    await SupabaseManager.initialize();

    // 念のため、SupabaseManager からも値を取得して確認（ログ目的）
    final storeId = SupabaseManager.getLoggedInStoreId();
    final isWorking = SupabaseManager.getWorkingStatus();
    print("バックグラウンド通知チェック（SupabaseManager）: 店舗ID=$storeId, 勤務状態=${isWorking ? '勤務中' : '休憩中'}");

    // 値が不一致の場合は警告ログを出力
    if (isWorkingDirect != isWorking) {
      print("警告: 直接取得した勤務状態とSupabaseManagerの勤務状態が一致しません");
      print("直接取得: $isWorkingDirect, SupabaseManager: $isWorking");
    }

    // 通知サービスを初期化
    await NotificationService.initialize();

    // バックグラウンド通知を表示（直接取得した勤務状態を優先する）
    await NotificationService.showNotification(message, forceShowNotification: isWorkingDirect);
    print("===== バックグラウンド通知表示完了 =====");
  } catch (e) {
    print("バックグラウンド通知エラー: $e");
  }
}


// FCMトークンを取得する関数
Future<String?> getFCMToken() async {
  try {
    String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      print('FCM Token successfully retrieved: $token');
      return token;
    } else {
      print('FCM Token is null');
      return null;
    }
  } catch (e) {
    print('Error getting FCM token: $e');
    return null;
  }
}

// FCMトークンをSupabaseに保存する関数
Future<void> saveFCMTokenToSupabase(String token, String deviceName) async {
  try {
    // ログイン済みであればstore_idを取得
    final int? storeId = SupabaseManager.getLoggedInStoreId();

    print('FCMトークンを保存中: $token、店舗ID: $storeId');

    // 既存のトークンを確認
    final existingDevices = await supabase
        .from('pos_devices')
        .select()
        .eq('fcm_token', token);

    // トークンが存在しない場合は新規追加
    if (existingDevices.isEmpty) {
      final dataToInsert = {
        'device_name': deviceName,
        'fcm_token': token,
      };

      // store_idが存在する場合のみ追加
      if (storeId != null) {
        dataToInsert['store_id'] = storeId.toString();
      }

      final result = await supabase.from('pos_devices')
          .insert(dataToInsert)
          .select();
      print('FCMトークンをSupabaseに保存しました: $result');
    } else {
      // すでに存在する場合は店舗IDが設定されていれば更新
      if (storeId != null) {
        final device = existingDevices.first;
        if (device['store_id'] == null || device['store_id'].toString() != storeId.toString()) {
          final result = await supabase.from('pos_devices')
              .update({'store_id': storeId.toString()})
              .eq('fcm_token', token)
              .select();
          print('FCMトークンの店舗IDを更新しました: $result');
        } else {
          print('FCMトークンは既にSupabaseに存在し、店舗IDも正しく設定されています');
        }
      } else {
        print('FCMトークンは既に存在しますが、ログイン中の店舗IDがないため更新しません');
      }
    }

    // 最終的なFCMトークンを出力（デバッグ用）
    print('FCM token: $token');
  } catch (e) {
    print('FCMトークン保存エラー: $e');
    if (e is PostgrestException) {
      print('PostgrestException: ${e.message}');
      print('詳細: ${e.details}');
    }
  }
}

// 軽量なSupabase接続テスト - 改良版
Future<void> testSupabase() async {
  try {
    print('🔍 Supabase診断開始');
    try {
      // テーブルクエリでテスト
      final tableResponse = await supabase.from('store_settings').select('id').limit(1);
      print('✅ Supabase接続成功: $tableResponse');
    } catch (e) {
      print('❌ Supabase接続エラー: $e');

      if (e is PostgrestException) {
        print('PostgrestException: ${e.message}');
        print('詳細: ${e.details}');
        print('ヒント: ${e.hint}');
      } else if (e.toString().contains('SocketException')) {
        print('ネットワーク接続エラー。以下を確認してください:');
        print('1. デバイスのインターネット接続');
        print('2. エミュレータのネットワーク設定');
        print('3. ファイアウォールやVPNの設定');
      }
    }
  } catch (e) {
    print('❌ Supabase初期化エラー: $e');
  }
}

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // "ja_JP" のロケールデータを初期化
    await initializeDateFormatting('ja_JP');

    // Firebase初期化
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');

    // ここで先にバックグラウンドメッセージハンドラーを登録
    // 注: これは必ずFirebase初期化の直後に行う必要があります
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 通知サービスを初期化
    await NotificationService.initialize();
    print('通知サービスを初期化しました');

    // SupabaseManagerを使用して初期化
    print('Supabase初期化を開始します...');
    await SupabaseManager.initialize();
    print('✅ Supabase初期化成功');

    // 少し待機してから接続テスト
    await Future.delayed(const Duration(milliseconds: 500));
    await testSupabase();

    // 通知権限のリクエスト（Android/iOS共通）
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    print('User granted permission: ${settings.authorizationStatus}');

    // iOS固有の設定
    if (Platform.isIOS) {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      print('iOS specific settings configured');
    }

    // FCMトークンの取得（最大3回試行）
    String? token;
    for (int i = 0; i < 3; i++) {
      token = await getFCMToken();
      if (token != null) {
        // FCMトークンをSupabaseに保存
        String deviceType = Platform.isAndroid ? 'Android' : 'iOS';
        await saveFCMTokenToSupabase(token, '$deviceType Device ${DateTime.now().millisecondsSinceEpoch}');
        break;
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    // トークン更新時のハンドラー
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      print('FCM Token refreshed: $token');
      String deviceType = Platform.isAndroid ? 'Android' : 'iOS';
      saveFCMTokenToSupabase(token, '$deviceType Device (更新) ${DateTime.now().millisecondsSinceEpoch}');
    });

    // フォアグラウンドでのメッセージハンドリング
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('===== フォアグラウンド通知受信 =====');
      print('MessageId: ${message.messageId}');
      print('Message notification: ${message.notification?.title}');
      print('Message data: ${message.data}');

      // フォアグラウンド通知を表示
      NotificationService.showNotification(message);
    });

    // 通知タップでアプリが起動された場合の処理
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('通知タップでアプリが起動されました:');
      print('Message data: ${message.data}');
      // 必要に応じて特定の画面へ遷移するなどの処理を追加
    });

    // アプリが終了状態から起動された場合のメッセージハンドリング
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('App launched from terminated state by message:');
      print('Message data: ${initialMessage.data}');
      // ここで必要な処理を追加（例：特定の画面への遷移など）
    }

  } catch (e) {
    print('Error in initialization: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Staff POS App',
      theme: ThemeData(
        useMaterial3: false,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
        ),
        scaffoldBackgroundColor: Colors.grey[100],
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            textStyle: const TextStyle(fontSize: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        cardTheme: CardTheme(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      // ローカライズのデリゲート
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''), // 英語
        Locale('ja', ''), // 日本語
      ],

      // 最初に表示する画面をPosLoginPageに設定
      home: const PosLoginPage(),
    );
  }
}