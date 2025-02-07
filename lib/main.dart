import 'package:flutter/material.dart';
import 'pages/order_list_page.dart';

void main() {
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
        scaffoldBackgroundColor: Colors.grey[100], // 背景色を少し明るいグレーに
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white, // ボタン文字色
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
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
      home: const OrderListPage(),
    );
  }
}
