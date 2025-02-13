import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/supabase_manager.dart';

class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({Key? key}) : super(key: key);

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  late final Stream<List<Map<String, dynamic>>> _paymentHistoryStream;

  @override
  void initState() {
    super.initState();
    // payment_historyテーブルをストリーム購読 (created_at は UTC で保存)
    _paymentHistoryStream = supabase
        .from('payment_history')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会計履歴'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _paymentHistoryStream,
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

          final payments = snapshot.data!;
          if (payments.isEmpty) {
            return const Center(child: Text('まだ会計履歴がありません'));
          }

          return ListView.builder(
            itemCount: payments.length,
            itemBuilder: (context, index) {
              final pay = payments[index];

              final tableName = pay['table_name'] as String? ?? '不明テーブル';
              final amount = pay['amount'] as num? ?? 0;

              // Supabaseに保存されているUTC日時
              final createdAtRaw = pay['created_at'] as String? ?? '';

              // 表示用文字列（初期値は生の文字列）
              String formattedDate = createdAtRaw;

              if (createdAtRaw.isNotEmpty) {
                try {
                  // 1) UTCの文字列をDateTimeにパース
                  final dtUtc = DateTime.parse(createdAtRaw);

                  // 2) 端末ローカル（日本ならUTC+9）に変換
                  final dtLocal = dtUtc.toLocal();

                  // 3) 好きな書式でフォーマット (例: yyyy年MM月dd日 HH:mm)
                  final formatter = DateFormat('yyyy年MM月dd日 HH:mm');
                  formattedDate = formatter.format(dtLocal);

                } catch (e) {
                  // もし変換に失敗したらログを出すだけ
                  debugPrint('DateTime parse error: $e');
                }
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text('テーブル: $tableName'),
                  subtitle: Text('決済時刻: $formattedDate'),
                  trailing: Text(
                    '¥${amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
