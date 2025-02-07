import 'package:flutter/material.dart';
import '../supabase_manager.dart';

class OrderListPage extends StatefulWidget {
  const OrderListPage({Key? key}) : super(key: key);

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  late final Stream<List<Map<String, dynamic>>> _ordersStream;

  @override
  void initState() {
    super.initState();
    // 「orders」テーブルのリアルタイムストリームを取得
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("スタッフ用POS"),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          // 通信中 or データ未取得
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // エラー時
          if (snapshot.hasError) {
            return Center(
              child: Text('エラーが発生しました: ${snapshot.error}'),
            );
          }
          // データ取得完了
          final orders = snapshot.data!;
          if (orders.isEmpty) {
            return const _EmptyOrdersView();
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final o = orders[index];
              final tableName = o['table_name'] as String?;
              final status = o['status'] as String?;
              final orderId = o['id'] as String?;
              final items = o['items'] as List<dynamic>?;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 上段: テーブル名とステータスバッジ
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.table_bar, color: Colors.teal),
                              const SizedBox(width: 6),
                              Text(
                                tableName ?? '不明',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          _StatusBadge(status: status),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 注文内容
                      if (items != null && items.isNotEmpty)
                        _OrderItemsView(items: items)
                      else
                        const Text(
                          "注文内容なし",
                          style: TextStyle(color: Colors.grey),
                        ),

                      const SizedBox(height: 12),

                      // ステータス変更ボタン
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (status != 'provided') ...[
                            ElevatedButton.icon(
                              onPressed: () {
                                _updateStatus(orderId!, 'provided');
                              },
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text("提供完了"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber[800],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (status != 'paid')
                            ElevatedButton.icon(
                              onPressed: () {
                                _updateStatus(orderId!, 'paid');
                              },
                              icon: const Icon(Icons.payment),
                              label: const Text("会計済み"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[600],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// ステータス更新
  Future<void> _updateStatus(String orderId, String newStatus) async {
    final response = await supabase
        .from('orders')
        .update({'status': newStatus})
        .eq('id', orderId);

    if (response is! List && response is! Map) {
      debugPrint('Update error: $response');
    }
  }
}

/// 注文アイテム表示用ウィジェット
class _OrderItemsView extends StatelessWidget {
  final List<dynamic> items;
  const _OrderItemsView({Key? key, required this.items}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "注文内容",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        ...items.map((item) {
          final itemMap = item as Map<String, dynamic>;
          final itemName = itemMap['name'] as String?;
          final quantity = itemMap['quantity'] as int?;
          final price = itemMap['price'] as int?;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(itemName ?? '', maxLines: 1)),
                Text("×${quantity ?? 0}"),
                const SizedBox(width: 16),
                Text(
                  price != null ? "¥$price" : "-",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}

/// ステータスバッジ（色分け）
class _StatusBadge extends StatelessWidget {
  final String? status;
  const _StatusBadge({Key? key, required this.status}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    String text;
    switch (status) {
      case 'unprovided':
        bgColor = Colors.redAccent;
        text = '未提供';
        break;
      case 'provided':
        bgColor = Colors.blueAccent;
        text = '提供済み';
        break;
      case 'paid':
        bgColor = Colors.green;
        text = '会計済み';
        break;
      default:
        bgColor = Colors.grey;
        text = '不明';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 「まだ注文はありません」用のWidget
class _EmptyOrdersView extends StatelessWidget {
  const _EmptyOrdersView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'まだ注文はありません',
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 16,
        ),
      ),
    );
  }
}
