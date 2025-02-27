import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:staff_pos_app/services/supabase_manager.dart';

// 日付フォーマットのロケールデータを初期化
import 'package:intl/date_symbol_data_local.dart';

// ローカライズのため
import 'package:flutter_localizations/flutter_localizations.dart';

// POSログインページをimport
import 'pages/pos_login/pos_login_page.dart';

import 'firebase_options.dart';

/// バックグラウンドメッセージを受信する際に呼ばれるハンドラ.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // バックグラウンドの isolate でも Firebase.initializeApp(options: ...) が必要
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print("Handling a background message: ${message.messageId}");
  print("Message data: ${message.data}");
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
    // 既存のトークンを確認
    final existingDevices = await supabase
        .from('pos_devices')
        .select()
        .eq('fcm_token', token);

    // トークンが存在しない場合は新規追加
    if (existingDevices.isEmpty) {
      final result = await supabase.from('pos_devices').insert({
        'device_name': deviceName,
        'fcm_token': token,
      }).select();
      print('FCMトークンをSupabaseに保存しました: $result');
    } else {
      print('FCMトークンは既にSupabaseに存在します');
    }
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
        await saveFCMTokenToSupabase(token, 'Android Device ${DateTime.now().millisecondsSinceEpoch}');
        break;
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    // トークン更新時のハンドラー
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      print('FCM Token refreshed: $token');
      saveFCMTokenToSupabase(token, 'Android Device (更新) ${DateTime.now().millisecondsSinceEpoch}');
    });

    // バックグラウンドメッセージハンドラーの登録
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // フォアグラウンドでのメッセージハンドリング
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Received foreground message:');
      print('Message notification: ${message.notification?.title}');
      print('Message data: ${message.data}');
    });

    // アプリが終了状態から起動された場合のメッセージハンドリング
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('App launched from terminated state by message:');
      print('Message data: ${initialMessage.data}');
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
        useMaterial3: true,
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