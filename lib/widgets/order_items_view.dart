import 'package:flutter/material.dart';

class OrderItemsView extends StatelessWidget {
  final String orderId;
  final List<dynamic> items;
  // 親から受け取った item単位の更新用関数
  final Future<void> Function(String orderId, int itemIndex, String newStatus)
  onItemStatusUpdate;

  const OrderItemsView({
    super.key,
    required this.orderId,
    required this.items,
    required this.onItemStatusUpdate,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "注文内容 (商品ごとに提供完了可)",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value as Map<String, dynamic>;
          final itemName = item['name'] as String? ?? '';
          final quantity = item['quantity'] as int? ?? 0;
          final status = item['status'] as String? ?? 'unprovided';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                // 商品名
                Expanded(
                  child: Text(
                    "$itemName ×$quantity",
                    maxLines: 1,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                // ステータス表示 or ボタン
                if (status == 'provided') ...[
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "提供済み",
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: () => onItemStatusUpdate(orderId, index, 'provided'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    child: const Text(
                      "提供完了",
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}
