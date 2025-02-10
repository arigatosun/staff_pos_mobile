import 'package:flutter/material.dart';
import 'orders/order_list_page.dart';
import 'tables/table_list_page.dart';
import 'history/payment_history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  // 表示するページをリスト管理
  final List<Widget> _pages = const [
    OrderListPage(),
    TableListPage(),
    PaymentHistoryPage(),
  ];

  // ボトムナビゲーションのタップ時に呼ばれる
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 各ページで個別のAppBarを使用したい場合、下記を削除し
      // ページ側(例: OrderListPage)で Scaffold(appBar: ...) を実装してもOK
      appBar: AppBar(
        title: const Text('スタッフ用POS'),
        centerTitle: true,
      ),

      body: _pages[_selectedIndex],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.teal,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: '注文管理',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.table_bar),
            label: 'テーブル管理',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: '会計履歴',
          ),
        ],
      ),
    );
  }
}
