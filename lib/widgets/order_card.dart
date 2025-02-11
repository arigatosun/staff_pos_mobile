import 'package:flutter/material.dart';
import 'status_badge.dart';
import 'order_items_view.dart';

class OrderCard extends StatelessWidget {
  final Map<String, dynamic> orderData;

  // Item単位のステータス更新を受け取る関数
  final Future<void> Function(String orderId, int itemIndex, String newStatus)
  onItemStatusUpdate;

  const OrderCard({
    Key? key,
    required this.orderData,
    required this.onItemStatusUpdate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tableName = orderData['table_name'] as String? ?? '不明';
    final orderId = orderData['id'] as String? ?? '';
    final statusList = _extractItemStatuses(orderData['items'] as List? ?? []);
    final hasUnprovided = statusList.contains('unprovided');

    // created_at があれば経過時間を計算
    final createdAtStr = orderData['created_at'] as String?;
    final diffMinutes = _getElapsedMinutes(createdAtStr);

    // 経過時間によって枠色や背景色を変化させる例
    final cardColor = _getCardColor(diffMinutes);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cardColor, // 経過時間による色
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // 上段: テーブル名 + 経過時間 + 全体ステータスバッジ
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "テーブル: $tableName",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _formatElapsedTime(diffMinutes),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 全体ステータスバッジ (未提供アイテムがあれば unprovided, なければ provided)
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(status: hasUnprovided ? 'unprovided' : 'provided'),
            ),
            const SizedBox(height: 6),
            // アイテム一覧
            OrderItemsView(
              orderId: orderId,
              items: orderData['items'] as List<dynamic>? ?? [],
              onItemStatusUpdate: onItemStatusUpdate,
            ),
          ],
        ),
      ),
    );
  }

  /// items配列内にある status 一覧を抽出
  List<String> _extractItemStatuses(List items) {
    return items
        .map((e) => (e as Map<String, dynamic>)['status'] as String? ?? '')
        .toList();
  }

  /// created_at からの経過分数を返す
  int _getElapsedMinutes(String? createdAtStr) {
    if (createdAtStr == null) return 0;
    DateTime? createdAt;
    try {
      createdAt = DateTime.parse(createdAtStr).toLocal();
    } catch (_) {
      return 0;
    }
    final diff = DateTime.now().difference(createdAt);
    return diff.inMinutes;
  }

  /// 経過時間(分)によって色を変える
  Color _getCardColor(int diffMinutes) {
    if (diffMinutes >= 20) {
      return Colors.orange[300]!;
    } else if (diffMinutes >= 10) {
      return Colors.orange[100]!;
    }
    return Colors.white; // 10分未満は白
  }

  /// 分数を "x分前" / "x時間前" / "x日前" / "たった今" に変換
  String _formatElapsedTime(int minutes) {
    if (minutes < 1) {
      return "たった今";
    } else if (minutes < 60) {
      return "${minutes}分前";
    }
    final hours = minutes ~/ 60;
    if (hours < 24) {
      return "${hours}時間前";
    }
    final days = hours ~/ 24;
    return "${days}日前";
  }
}
