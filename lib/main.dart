import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'pages/home_page.dart';

/// バックグラウンドメッセージを受信する際に呼ばれるハンドラ.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // バックグラウンドの isolate でも Firebase.initializeApp() が必要
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
  print("Message data: ${message.data}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase初期化 (フォアグラウンド用)
  await Firebase.initializeApp();

  // バックグラウンドメッセージを受信した際に呼ばれる関数を登録
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Staff POS App',
      theme: ThemeData(
        // Material 3を有効化
        useMaterial3: true,

        // カラースキームの設定
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal, // プライマリーカラーをtealに設定
          // 必要に応じて個別の色をカスタマイズ可能
          // brightness: Brightness.light,  // ライトモード
          // secondary: Colors.tealAccent,  // アクセントカラー
        ),

        // 背景色の設定
        scaffoldBackgroundColor: Colors.grey[100],

        // ボタンテーマの設定
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

        // カードテーマの設定
        cardTheme: CardTheme(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),

        // AppBarテーマの設定（オプション）
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.teal, // AppBarの背景色
          foregroundColor: Colors.white, // AppBarのテキストと親子の色
          elevation: 2, // 影の設定
        ),
      ),
      home: const HomePage(), // BottomNavigationBarを持つホーム画面へ
    );
  }
}