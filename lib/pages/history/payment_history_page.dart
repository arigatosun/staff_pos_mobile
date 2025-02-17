import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'dart:math'; // 追加：ランダム生成用
import '../../services/supabase_manager.dart';

class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({Key? key}) : super(key: key);

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  late final Stream<List<Map<String, dynamic>>> _paymentHistoryStream;
  DateTime? _startDate;
  DateTime? _endDate;

  // 選択された日付範囲を表示するための文字列
  String get _dateRangeText {
    if (_startDate == null && _endDate == null) return 'すべての履歴';
    if (_startDate != null && _endDate != null && _startDate == _endDate) {
      return DateFormat('yyyy年MM月dd日', 'ja_JP').format(_startDate!);
    }
    final start = _startDate != null
        ? DateFormat('yyyy/MM/dd', 'ja_JP').format(_startDate!)
        : '';
    final end = _endDate != null
        ? DateFormat('yyyy/MM/dd', 'ja_JP').format(_endDate!)
        : '';
    return '$start 〜 $end';
  }

  @override
  void initState() {
    super.initState();
    _paymentHistoryStream = supabase
        .from('payment_history')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  Map<String, List<Map<String, dynamic>>> _filterAndGroupPayments(
      List<Map<String, dynamic>> allPayments) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final pay in allPayments) {
      final createdAtRaw = pay['created_at'] as String? ?? '';
      if (createdAtRaw.isEmpty) continue;

      DateTime dtLocal;
      try {
        final dtUtc = DateTime.parse(createdAtRaw);
        dtLocal = dtUtc.toLocal();
      } catch (_) {
        continue;
      }

      if (_startDate != null) {
        final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        if (dtLocal.isBefore(start)) continue;
      }
      if (_endDate != null) {
        final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        if (dtLocal.isAfter(end)) continue;
      }

      final dateKey = DateFormat('yyyy-MM-dd').format(dtLocal);
      grouped.putIfAbsent(dateKey, () => []).add(pay);
    }

    return grouped;
  }

  DateTime _parseDateKey(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length < 3) return DateTime.now();
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final day = int.tryParse(parts[2]) ?? DateTime.now().day;
    return DateTime(year, month, day);
  }

  void _filterAll() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  void _filterToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _startDate = today;
      _endDate = today;
    });
  }

  void _filterYesterday() {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    setState(() {
      _startDate = yesterday;
      _endDate = yesterday;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final lastYear = DateTime(now.year - 1, now.month, now.day);

    final result = await showDateRangePicker(
      context: context,
      locale: const Locale('ja'),
      initialDateRange: (_startDate != null && _endDate != null)
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      firstDate: lastYear,
      lastDate: DateTime(now.year + 1, now.month, now.day),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.orange,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (result != null) {
      setState(() {
        _startDate = result.start;
        _endDate = result.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会計履歴'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 日付フィルター表示部分
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 選択中の日付範囲を表示
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _dateRangeText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // フィルターボタン群
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterButton('すべて',
                        onTap: _filterAll,
                        isSelected: _startDate == null && _endDate == null,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterButton('今日',
                        onTap: _filterToday,
                        isSelected: _startDate != null && _endDate != null &&
                            _startDate!.year == DateTime.now().year &&
                            _startDate!.month == DateTime.now().month &&
                            _startDate!.day == DateTime.now().day,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterButton('昨日',
                        onTap: _filterYesterday,
                        isSelected: _startDate != null && _endDate != null &&
                            _startDate!.year == DateTime.now().year &&
                            _startDate!.month == DateTime.now().month &&
                            _startDate!.day == DateTime.now().day - 1,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterButton(
                        '日付範囲指定',
                        onTap: _pickDateRange,
                        icon: Icons.date_range,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 履歴リスト
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _paymentHistoryStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'エラー: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final allPayments = snapshot.data!;
                if (allPayments.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'まだ会計履歴がありません',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final groupedMap = _filterAndGroupPayments(allPayments);
                if (groupedMap.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          '該当の会計履歴はありません',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final dateKeys = groupedMap.keys.toList()
                  ..sort((a, b) => b.compareTo(a));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: dateKeys.length,
                  itemBuilder: (context, index) {
                    final dateKey = dateKeys[index];
                    final dayPayments = groupedMap[dateKey] ?? [];
                    final parsedDate = _parseDateKey(dateKey);
                    final formattedDate = DateFormat('yyyy年MM月dd日 (E)', 'ja_JP')
                        .format(parsedDate);
                    final dayTotal = dayPayments.fold<num>(
                      0,
                          (prev, pay) => prev + (pay['amount'] as num? ?? 0),
                    );

                    return _buildDaySection(
                      dateLabel: formattedDate,
                      dayTotal: dayTotal,
                      payments: dayPayments,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(
      String label, {
        required VoidCallback onTap,
        IconData? icon,
        bool isSelected = false,
      }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.orange : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected ? Colors.orange : Colors.grey.shade300,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDaySection({
    required String dateLabel,
    required num dayTotal,
    required List<Map<String, dynamic>> payments,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${payments.length}件の取引',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      '日計',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      '¥${dayTotal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Column(
            children: payments.map((pay) => _buildPaymentItem(pay)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentItem(Map<String, dynamic> pay) {
    final tableName = pay['table_name'] as String? ?? '不明テーブル';
    final amount = pay['amount'] as num? ?? 0;
    final String paymentMethodMock =
    (pay['id']?.toString().hashCode ?? Random().nextInt(1000)) % 2 == 0
        ? '現金'
        : 'square';
    final createdAtRaw = pay['created_at'] as String? ?? '';

    // 金額がマイナスかどうかのチェック
    final isNegativeAmount = (amount < 0);

    String timeStr = createdAtRaw;
    if (createdAtRaw.isNotEmpty) {
      try {
        final dtLocal = DateTime.parse(createdAtRaw).toLocal();
        timeStr = DateFormat('HH:mm').format(dtLocal);
      } catch (_) {}
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // タップ時の詳細表示などを実装可能
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tableName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.payment,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '決済手段:',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            paymentMethodMock,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600, // 決済手段は常にグレー
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '決済時間:',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  '¥${amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isNegativeAmount ? Colors.red : Colors.black87, // 金額のみ条件付きで赤文字
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
