import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'pages/home_page.dart';

/// バックグラウンドメッセージを受信する際に呼ばれるハンドラ.
/// Flutter 3.3+では @pragma('vm:entry-point') が必須になる場合があるので付与.
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
        primarySwatch: Colors.teal, // AppBarなどのベースカラー
        scaffoldBackgroundColor: Colors.grey[100], // 背景色を少し明るいグレー

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white, // ボタン文字色
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        cardTheme: CardTheme(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
      ),
      home: const HomePage(), // ← BottomNavigationBarを持つホーム画面へ
    );
  }
}
