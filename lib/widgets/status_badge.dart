import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({
    super.key,
    required this.status,
  });

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
        bgColor = Colors.green;
        text = '提供済み';
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
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
