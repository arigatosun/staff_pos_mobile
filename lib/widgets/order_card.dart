import 'package:flutter/material.dart';
import 'status_badge.dart';
import 'order_items_view.dart';

class OrderCard extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final Future<void> Function(String orderId, String newStatus) onStatusUpdate;

  const OrderCard({
    Key? key,
    required this.orderData,
    required this.onStatusUpdate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tableName = orderData['table_name'] as String? ?? '不明';
    final status = orderData['status'] as String? ?? 'unknown';
    final orderId = orderData['id'] as String? ?? '';
    final items = orderData['items'] as List<dynamic>? ?? [];

    // created_at があれば経過時間を計算
    final createdAtStr = orderData['created_at'] as String?;
    final elapsedTimeText = _getElapsedTime(createdAtStr);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 上部: テーブル名 & 経過時間
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.table_bar, color: Colors.teal),
                    const SizedBox(width: 6),
                    Text(
                      tableName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  elapsedTimeText,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            // ステータスバッジ
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(status: status),
            ),

            const SizedBox(height: 12),
            // 注文アイテムリスト
            if (items.isNotEmpty)
              OrderItemsView(items: items)
            else
              const Text(
                "注文内容なし",
                style: TextStyle(color: Colors.grey),
              ),

            const SizedBox(height: 12),
            // ステータス更新ボタン
            _StatusButtons(
              status: status,
              orderId: orderId,
              onStatusUpdate: onStatusUpdate,
            ),
          ],
        ),
      ),
    );
  }

  /// created_at(ISO8601文字列)からの経過時間を "たった今","x分前","x時間前","x日前" の形に変換
  String _getElapsedTime(String? createdAtStr) {
    if (createdAtStr == null) return '';
    DateTime? createdAt;
    try {
      createdAt = DateTime.parse(createdAtStr).toLocal();
    } catch (_) {
      return '';
    }

    final diff = DateTime.now().difference(createdAt);

    if (diff.inMinutes < 1) {
      return 'たった今';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}時間前';
    } else {
      return '${diff.inDays}日前';
    }
  }
}

/// ステータス更新ボタン
class _StatusButtons extends StatelessWidget {
  final String status;
  final String orderId;
  final Future<void> Function(String, String) onStatusUpdate;

  const _StatusButtons({
    required this.status,
    required this.orderId,
    required this.onStatusUpdate,
  });

  @override
  Widget build(BuildContext context) {
    // 会計済みは不要なのでボタンは「提供完了」のみ表示
    // すでに provided の場合は押せないようにする
    if (status == 'provided') {
      return Container(
        alignment: Alignment.centerRight,
        child: const Text(
          '提供済み',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      );
    }

    // unprovided → 「提供完了」ボタン
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton.icon(
        onPressed: () => onStatusUpdate(orderId, 'provided'),
        icon: const Icon(Icons.check_circle_outline),
        label: const Text("提供完了"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber[700],
        ),
      ),
    );
  }
}
