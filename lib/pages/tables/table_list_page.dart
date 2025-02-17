import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/supabase_manager.dart';
import '../../widgets/empty_orders_view.dart';

// order_list_page.dart に定義した TableColorManager を import
import '../../pages/orders/order_list_page.dart' show TableColorManager;

enum OrderFilter {
  all('すべて'),
  hasUnprovided('未提供あり'),
  fullyProvided('全提供済み');

  final String label;
  const OrderFilter(this.label);
}

class TableListPage extends StatefulWidget {
  const TableListPage({Key? key}) : super(key: key);

  @override
  State<TableListPage> createState() => _TableListPageState();
}

class _TableListPageState extends State<TableListPage> {
  late final Stream<List<Map<String, dynamic>>> _ordersStream;

  // table_colors購読用
  StreamSubscription<List<Map<String, dynamic>>>? _tableColorStreamSub;

  OrderFilter _selectedFilter = OrderFilter.all;

  @override
  void initState() {
    super.initState();

    // ordersテーブルを監視
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);


    // (2) table_colors を購読してリアルタイムで反映
    _tableColorStreamSub = supabase
        .from('table_colors')
        .stream(primaryKey: ['id'])
        .listen((rows) {
      // 取得したテーブルカラー情報を更新
      TableColorManager.updateTableColors(rows);
      // 画面を再描画 (同期メソッドで色を取得するためsetStateで再描画すればOK)
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // 購読の解除
    _tableColorStreamSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('テーブル管理'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'エラー: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!;
          if (orders.isEmpty) {
            return const EmptyOrdersView();
          }

          // フィルタリング
          final filteredOrders = _filterOrders(orders);

          // テーブル別にグルーピング
          final tableMap = _groupByTable(filteredOrders);
          final tableNames = tableMap.keys.toList();

          return Column(
            children: [
              // フィルタUI
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      "フィルタ: ",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButton<OrderFilter>(
                      value: _selectedFilter,
                      items: OrderFilter.values.map((f) {
                        return DropdownMenuItem(
                          value: f,
                          child: Text(f.label),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedFilter = val);
                        }
                      },
                    ),
                  ],
                ),
              ),

              // テーブルごとの表示
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: tableNames.length,
                  itemBuilder: (context, index) {
                    final tName = tableNames[index];
                    final tOrders = tableMap[tName]!;

                    return _TableBlock(
                      tableName: tName,
                      orders: tOrders,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// フィルタ適用
  List<Map<String, dynamic>> _filterOrders(List<Map<String, dynamic>> orders) {
    if (_selectedFilter == OrderFilter.all) return orders;

    return orders.where((o) {
      final items = o['items'] as List<dynamic>? ?? [];
      final hasUnprovided = items.any((i) => (i as Map)['status'] == 'unprovided');
      if (_selectedFilter == OrderFilter.hasUnprovided) {
        return hasUnprovided;
      } else {
        // fullyProvided
        return !hasUnprovided;
      }
    }).toList();
  }

  /// テーブル名でグルーピング
  Map<String, List<Map<String, dynamic>>> _groupByTable(
      List<Map<String, dynamic>> orders,
      ) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (var o in orders) {
      final tName = o['table_name'] as String? ?? '不明テーブル';
      map.putIfAbsent(tName, () => []);
      map[tName]!.add(o);
    }
    return map;
  }
}

/// テーブルブロック
class _TableBlock extends StatelessWidget {
  final String tableName;
  final List<Map<String, dynamic>> orders;

  const _TableBlock({
    Key? key,
    required this.tableName,
    required this.orders,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // ★ FutureBuilderではなく、同期メソッドでテーブルカラーを取得
    final tableColor = TableColorManager.getTableColor(tableName);

    // テーブル状態/合計など
    final tableStatus = _getTableStatus(orders);
    final tableTotal = _calculateTableTotal(orders);
    final orderWidgets = _buildOrderWidgets(orders);

    // 左側にカラーラインを入れたカード
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(width: 20, color: tableColor)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tableName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            _TableStatusBadge(tableStatus),
          ],
        ),
        children: [
          // オーダー一覧
          ...orderWidgets,

          // 合計表示
          Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '合計: ¥${tableTotal.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // 会計 & リセットボタン
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // 会計に進む
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final hasUnprovided = (tableStatus == 'unprovided');

                      final success = await _simulatePayment(
                        context,
                        tableTotal,
                        hasUnprovided: hasUnprovided,
                      );
                      if (success) {
                        // 決済成功 → payment_history へ書き込み & リセット
                        try {
                          await supabase.from('payment_history').insert({
                            'table_name': tableName,
                            'amount': tableTotal,
                          });
                        } catch (e) {
                          print('決済履歴の書き込み失敗: $e');
                        }
                        await _resetTable(tableName, context);
                      }
                    },
                    style: _buttonStyle(),
                    child: const Text('会計に進む'),
                  ),
                ),
                const SizedBox(width: 8),

                // テーブルリセット
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('テーブルリセット'),
                          content: const Text(
                            '本当にリセットしますか？\n(注文データがアーカイブされます)',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await _resetTable(tableName, context);
                      }
                    },
                    style: _buttonStyle(),
                    child: const Text('テーブルリセット'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ボタンスタイル
  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.blueAccent,
      foregroundColor: Colors.white,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      padding: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  /// (疑似)決済処理ダイアログ
  Future<bool> _simulatePayment(
      BuildContext context,
      double total, {
        required bool hasUnprovided,
      }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Square Terminal(疑似)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('¥${total.toStringAsFixed(0)} を決済します。\n結果を選択してください。'),
              const SizedBox(height: 8),
              if (hasUnprovided) ...[
                const Text(
                  '※未提供商品が残っています。',
                  style: TextStyle(color: Colors.redAccent),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('失敗'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('成功'),
            ),
          ],
        );
      },
    );
    return (result == true);
  }

  /// テーブルリセット (orders のデータをアーカイブ or 削除)
  Future<void> _resetTable(String tableName, BuildContext context) async {
    try {
      await supabase.rpc('reset_table', params: {
        'p_table_name': tableName,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$tableName をリセットしました(アーカイブ済み)')),
        );
      }
    } catch (e) {
      print('テーブルリセット失敗: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('テーブルリセット失敗: $e')),
        );
      }
    }
  }

  /// テーブルのステータス (未提供あり / 全提供済み)
  String _getTableStatus(List<Map<String, dynamic>> orders) {
    for (var o in orders) {
      final items = o['items'] as List<dynamic>? ?? [];
      if (items.any((i) => (i as Map)['status'] == 'unprovided')) {
        return 'unprovided';
      }
    }
    return 'provided';
  }

  /// 合計金額
  double _calculateTableTotal(List<Map<String, dynamic>> orders) {
    double sum = 0;
    for (final o in orders) {
      final items = o['items'] as List<dynamic>? ?? [];
      for (final it in items) {
        final itemMap = it as Map<String, dynamic>;
        final qty = (itemMap['quantity'] as int?) ?? 0;
        final price = (itemMap['price'] as num?)?.toDouble() ?? 0.0;
        final status = itemMap['status'] as String? ?? 'unprovided';

        if (status == 'canceled') {
          // キャンセルはマイナス
          sum -= price * qty;
        } else {
          sum += price * qty;
        }
      }
    }
    return sum;
  }

  List<Widget> _buildOrderWidgets(List<Map<String, dynamic>> orders) {
    // 日時順ソート（古い順）
    final sorted = [...orders];
    sorted.sort((a, b) {
      final tA = a['created_at'] as String? ?? '';
      final tB = b['created_at'] as String? ?? '';
      return tA.compareTo(tB);
    });

    final widgets = <Widget>[];
    for (var i = 0; i < sorted.length; i++) {
      final order = sorted[i];
      final label = (i == 0) ? "初回オーダー" : "追加オーダー$i";

      widgets.add(_OrderBlock(
        orderData: order,
        orderLabel: label,
      ));
    }
    return widgets;
  }
}

class _TableStatusBadge extends StatelessWidget {
  final String status;
  const _TableStatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final isUnprovided = (status == 'unprovided');
    final color = isUnprovided ? Colors.redAccent : Colors.green;
    final text = isUnprovided ? '未提供あり' : '全提供済み';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _OrderBlock extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final String orderLabel;

  const _OrderBlock({
    Key? key,
    required this.orderData,
    required this.orderLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final items = orderData['items'] as List<dynamic>? ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            orderLabel,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _buildItemsTable(items),
        ],
      ),
    );
  }

  Widget _buildItemsTable(List<dynamic> items) {
    if (items.isEmpty) return const SizedBox();

    final rows = <TableRow>[];
    // ヘッダ行
    rows.add(
      TableRow(
        decoration: BoxDecoration(color: Colors.grey[200]),
        children: [
          _cellHeader("商品名"),
          _cellHeader("数量"),
          _cellHeader("状態"),
          _cellHeader("小計"),
        ],
      ),
    );

    // 明細行
    for (var i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      final name = item['name'] as String? ?? '';
      final qty = (item['quantity'] as int?) ?? 0;
      final status = item['status'] as String? ?? 'unprovided';
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;

      final isCanceled = (status == 'canceled');
      final subTotal = price * qty * (isCanceled ? -1 : 1);
      final subTotalText = isCanceled
          ? '-¥${(price * qty).toStringAsFixed(0)}'
          : '¥${subTotal.toStringAsFixed(0)}';

      rows.add(
        TableRow(
          children: [
            _cellBody(name),
            _cellBody("$qty"),
            _cellBodyWidget(_buildStatusLabel(status)),
            _cellBody(
              subTotalText,
              color: isCanceled ? Colors.red : null,
            ),
          ],
        ),
      );
    }

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      columnWidths: const {
        0: FlexColumnWidth(3.0),
        1: FlexColumnWidth(0.6),
        2: FlexColumnWidth(1.0),
        3: FlexColumnWidth(1.0),
      },
      children: rows,
    );
  }

  Widget _cellHeader(String text) {
    return Container(
      padding: const EdgeInsets.all(6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          overflow: TextOverflow.ellipsis,
        ),
        maxLines: 1,
      ),
    );
  }

  Widget _cellBody(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color ?? Colors.black87,
          overflow: TextOverflow.ellipsis,
        ),
        maxLines: 1,
      ),
    );
  }

  Widget _cellBodyWidget(Widget child) {
    return Container(
      padding: const EdgeInsets.all(6),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  Widget _buildStatusLabel(String status) {
    String label;
    Color bgColor;
    switch (status) {
      case 'unprovided':
        label = '未提供';
        bgColor = Colors.redAccent;
        break;
      case 'provided':
        label = '済';
        bgColor = Colors.green;
        break;
      case 'canceled':
        label = '取消';
        bgColor = Colors.grey;
        break;
      default:
        label = status;
        bgColor = Colors.grey;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          overflow: TextOverflow.ellipsis,
        ),
        maxLines: 1,
      ),
    );
  }
}
