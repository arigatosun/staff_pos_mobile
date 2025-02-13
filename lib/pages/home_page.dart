import 'package:flutter/material.dart';
import 'package:staff_pos_app/pages/orders/order_list_page.dart';
import 'package:staff_pos_app/pages/tables/table_list_page.dart';
import 'package:staff_pos_app/pages/history/payment_history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  // 表示するページをリスト管理
  final List<Widget> _pages = const [
    // 1) 新しい「注文管理ページ（キッチンオーダー画面）」
    OrderListPage(),
    // 2) 現在の「テーブル管理ページ」(旧: order_list_page のテーブル分割表示を移植)
    TableListPage(),
    // 3) 会計履歴ページ
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
      // AppBarを削除しているため、画面上部には何も表示されません
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
