import 'package:flutter/material.dart';

class OrderItemsView extends StatelessWidget {
  final List<dynamic> items;

  const OrderItemsView({Key? key, required this.items}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox();
    }

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
          final itemName = itemMap['name'] as String? ?? '';
          final quantity = itemMap['quantity'] as int? ?? 0;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text(itemName, maxLines: 1)),
                Text("×$quantity"),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}
