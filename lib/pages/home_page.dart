import 'package:flutter/material.dart';
import 'package:staff_pos_app/pages/orders/order_list_page.dart';
import 'package:staff_pos_app/pages/tables/table_list_page.dart';
import 'package:staff_pos_app/pages/history/payment_history_page.dart';
import 'package:staff_pos_app/pages/settings/settings_page.dart';

class HomePage extends StatefulWidget {
  final int storeId; // 受け取り用
  const HomePage({super.key, required this.storeId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  // 後から初期化するため late
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // 子ページに storeId を渡す
    _pages = [
      OrderListPage(storeId: widget.storeId),
      TableListPage(storeId: widget.storeId),
      PaymentHistoryPage(storeId: widget.storeId),
      SettingsPage(storeId: widget.storeId),
    ];
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 既存同様、AppBarは削除し全画面を切り替える
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        // ★ ここを追加
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.teal,
        // ★ すべての項目にラベルを表示したい場合
        showUnselectedLabels: true,
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
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
