import 'package:flutter/material.dart';

class PaymentHistoryPage extends StatelessWidget {
  const PaymentHistoryPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 今後 会計済みの履歴を表示
    return const Center(
      child: Text(
        '会計履歴ページ（今後実装）',
        style: TextStyle(fontSize: 16),
      ),
    );
  }
}
