import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/supabase_manager.dart';
import '../../widgets/empty_orders_view.dart';
import '../../pages/orders/order_list_page.dart' show TableColorManager;

enum OrderFilter {
  all('すべて'),
  hasUnprovided('未提供あり'),
  fullyProvided('全提供済み');

  final String label;
  const OrderFilter(this.label);
}

class TableListPage extends StatefulWidget {
  final int storeId; // ★ コンストラクタで必須引数にする
  const TableListPage({super.key, required this.storeId});

  @override
  State<TableListPage> createState() => _TableListPageState();
}

class _TableListPageState extends State<TableListPage> {
  // orders テーブルのストリーム
  late final Stream<List<Map<String, dynamic>>> _ordersStream;
  // table_colors テーブル用のストリーム購読
  StreamSubscription<List<Map<String, dynamic>>>? _tableColorStreamSub;

  // payment_history の該当レコードを購読するサブスク
  StreamSubscription<List<Map<String, dynamic>>>? _paymentHistoryStreamSub;

  // フィルタ選択
  OrderFilter _selectedFilter = OrderFilter.all;

  @override
  void initState() {
    super.initState();

    // ordersテーブル: store_id 絞り込みストリーム
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('store_id', widget.storeId)
        .order('created_at', ascending: false);

    // table_colors を購読: store_id 絞り込み
    _tableColorStreamSub = supabase
        .from('table_colors')
        .stream(primaryKey: ['table_name'])
        .eq('store_id', widget.storeId)
        .listen((rows) {
      TableColorManager.updateTableColors(rows);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tableColorStreamSub?.cancel();
    _paymentHistoryStreamSub?.cancel(); // ★ payment_history のサブスク解放
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

          // フィルタに応じて絞り込み
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
                      // ★ 会計ボタン押下時のコールバック
                      onRequestCheckout: _handleCheckout,
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

  /// 会計処理ボタンが押されたときのフロー
  Future<void> _handleCheckout(String tableName, double total) async {
    // 会計ボタン押下 → Square Terminal Checkout作成
    final success = await _createSquareCheckout(tableName, total);
    if (!success) {
      return; // API失敗時は何もしない
    }
    // → Webhook で支払いが 'completed' になるのを待つ (サブスクで待機)
    // テーブルリセットはWebhook完了後に行う
  }

  /// Square チェックアウトをサーバー側で作成し、 payment_history レコードID を受け取る
  Future<bool> _createSquareCheckout(String tableName, double total) async {
    // あなたの Next.js API の URL (実際のURLに差し替えてください)
    final url = Uri.parse(
      'https://cf42-2400-4150-78a0-5300-a58e-41a-bed2-a718.ngrok-free.app/api/payments/terminal-checkout/',
    );

    final payload = {
      'storeId': widget.storeId,
      'amount': total.toInt(),
      'referenceId': tableName,
    };

    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (resp.statusCode == 200) {
        final jsonBody = jsonDecode(resp.body) as Map<String, dynamic>;

        if (jsonBody['success'] == true) {
          final checkout = jsonBody['checkout'] as Map<String, dynamic>?;
          final paymentHistoryId = jsonBody['paymentHistoryId'] as String?;
          if (checkout == null || paymentHistoryId == null) {
            throw Exception('checkout or paymentHistoryId is missing');
          }

          final cid = checkout['id'];
          final cstatus = checkout['status'];
          print('Checkout created: id=$cid status=$cstatus');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Square決済開始: checkoutId=$cid')),
          );

          // ★ payment_history のレコードをサブスク
          _subscribePaymentHistory(paymentHistoryId, tableName);

          return true;
        } else {
          final errorMsg = jsonBody['error'] ?? jsonBody.toString();
          print('Checkout creation failed. body=$errorMsg');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Checkout作成失敗: $errorMsg')),
          );
          return false;
        }
      } else {
        print(
          'Checkout creation failed. code=${resp.statusCode}, body=${resp.body}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout作成失敗: ${resp.body}')),
        );
        return false;
      }
    } catch (e) {
      print('Error creating checkout: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout作成エラー: $e')),
      );
      return false;
    }
  }

  /// payment_history テーブルで、指定IDの status を監視し 'completed' になったらテーブルリセット
  void _subscribePaymentHistory(String paymentHistoryId, String tableName) {
    // すでに購読中なら一旦キャンセル
    _paymentHistoryStreamSub?.cancel();
    _paymentHistoryStreamSub = supabase
        .from('payment_history')
        .stream(primaryKey: ['id'])
        .eq('id', paymentHistoryId)
        .listen((List<Map<String, dynamic>> data) async {
      if (data.isNotEmpty) {
        final row = data.first;
        final status = row['status'] as String?;
        print(
          'PaymentHistory status changed: id=$paymentHistoryId -> status=$status',
        );

        if (status == 'completed') {
          // ★ 支払い完了 → テーブルリセット
          await _resetTable(tableName);
          // サブスク解除
          await _paymentHistoryStreamSub?.cancel();
          _paymentHistoryStreamSub = null;

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('[$tableName] の支払いが完了しました→リセット完了')),
          );
        } else if (status == 'failed' || status == 'canceled') {
          // 失敗 or キャンセルなど
          await _paymentHistoryStreamSub?.cancel();
          _paymentHistoryStreamSub = null;

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('[$tableName] の支払いが $status になりました')),
          );
        }
      }
    });
  }

  /// テーブルリセット
  Future<void> _resetTable(String tableName) async {
    try {
      await supabase.rpc('reset_table', params: {
        'p_table_name': tableName,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$tableName をリセットしました(アーカイブ済み)')),
        );
      }
    } catch (e) {
      print('テーブルリセット失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('テーブルリセット失敗: $e')),
        );
      }
    }
  }

  /// フィルタに応じてオーダーを絞り込み
  List<Map<String, dynamic>> _filterOrders(List<Map<String, dynamic>> orders) {
    if (_selectedFilter == OrderFilter.all) return orders;

    return orders.where((o) {
      final items = o['items'] as List<dynamic>? ?? [];
      final hasUnprovided =
      items.any((i) => (i as Map)['status'] == 'unprovided');
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

  /// 会計ボタンが押された際に呼び出すコールバック
  final Future<void> Function(String tableName, double total) onRequestCheckout;

  const _TableBlock({
    required this.tableName,
    required this.orders,
    required this.onRequestCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final tableColor = TableColorManager.getTableColor(tableName);
    final tableStatus = _getTableStatus(orders);
    final tableTotal = _calculateTableTotal(orders);
    final orderWidgets = _buildOrderWidgets(orders);

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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            _TableStatusBadge(tableStatus),
          ],
        ),
        children: [
          ...orderWidgets,

          // 合計表示
          Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '合計: ¥${tableTotal.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('会計確認'),
                          content: Text(
                            'テーブル [$tableName]\n'
                                '¥${tableTotal.toStringAsFixed(0)} の会計を行いますか？',
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
                      if (confirm != true) return;

                      // 新ロジック：会計に進むときは onRequestCheckout を呼ぶ
                      await onRequestCheckout(tableName, tableTotal);
                    },
                    style: _buttonStyle(),
                    child: const Text('会計に進む'),
                  ),
                ),
                const SizedBox(width: 8),

                // テーブルリセット (任意: Webhook完了前に操作しないよう注意が必要)
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
                        // 直接リセットする場合
                        // (Webhook待たずに強制リセットする場合のみ)
                        final parent =
                        context.findAncestorStateOfType<_TableListPageState>();
                        if (parent != null) {
                          await parent._resetTable(tableName);
                        }
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

  /// テーブルのステータスを判定
  String _getTableStatus(List<Map<String, dynamic>> orders) {
    // items の中に 'unprovided' があれば 'unprovided'
    // orders.status が 'paid' なら 'paid'
    for (var o in orders) {
      final items = o['items'] as List<dynamic>? ?? [];
      if (items.any((i) => (i as Map)['status'] == 'unprovided')) {
        return 'unprovided';
      }
      if (o['status'] == 'paid') {
        return 'paid';
      }
    }
    return 'provided';
  }

  /// テーブル合計金額
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
          sum -= price * qty;
        } else {
          sum += price * qty;
        }
      }
    }
    return sum;
  }

  /// オーダー明細のウィジェットリストを生成
  List<Widget> _buildOrderWidgets(List<Map<String, dynamic>> orders) {
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
      widgets.add(_OrderBlock(orderData: order, orderLabel: label));
    }
    return widgets;
  }
}

/// ステータスバッジ
class _TableStatusBadge extends StatelessWidget {
  final String status;
  const _TableStatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;
    if (status == 'unprovided') {
      color = Colors.redAccent;
      text = '未提供あり';
    } else if (status == 'paid') {
      color = Colors.blueGrey;
      text = '会計済み';
    } else {
      color = Colors.green;
      text = '全提供済み';
    }

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

/// オーダーブロック
class _OrderBlock extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final String orderLabel;

  const _OrderBlock({
    required this.orderData,
    required this.orderLabel,
  });

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

    // ヘッダ
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

    // 明細
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
            _cellBodyWidget(_statusLabel(status)),
            _cellBody(subTotalText, color: isCanceled ? Colors.red : null),
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
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _cellBody(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(6),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: color ?? Colors.black87),
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

  Widget _statusLabel(String status) {
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
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }
}
