import 'package:flutter/material.dart';

class EmptyOrdersView extends StatelessWidget {
  const EmptyOrdersView({Key? key}) : super(key: key);

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
