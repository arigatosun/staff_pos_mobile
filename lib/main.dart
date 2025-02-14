import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'pages/home_page.dart';

// ★ 追加: FlutterFire CLI で生成されたファイルをimport
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

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // ★ Firebase初期化: 新たに options を指定
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');

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

    // FCMトークンの取得（複数回試行）
    String? token;
    for (int i = 0; i < 3; i++) {
      token = await getFCMToken();
      if (token != null) break;
      await Future.delayed(const Duration(seconds: 2));
    }

    // トークン更新時のハンドラー
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      print('FCM Token refreshed: $token');
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
  const MyApp({Key? key}) : super(key: key);

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
      home: const HomePage(),
    );
  }
}
