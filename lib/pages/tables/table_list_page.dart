import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/supabase_manager.dart';
import '../../widgets/empty_orders_view.dart';
import '../../pages/orders/order_list_page.dart' show TableColorManager;
import '../../pages/history/payment_history_page.dart';

enum OrderFilter {
  all('すべて'),
  hasUnprovided('未提供あり'),
  fullyProvided('全提供済み');

  final String label;
  const OrderFilter(this.label);
}

/// ステータスバッジ
class _TableStatusBadge extends StatelessWidget {
  final String status;
  const _TableStatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;
    if (status == 'unprovided') {
      color = Colors.redAccent;
      text = '未提供あり';
    } else if (status == 'paid') {
      color = Colors.blueGrey;
      text = '会計済み';
    } else {
      color = Colors.green;
      text = '全提供済み';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

/// オーダーブロック
class _OrderBlock extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final String orderLabel;

  const _OrderBlock({
    required this.orderData,
    required this.orderLabel,
  });

  @override
  Widget build(BuildContext context) {
    final items = orderData['items'] as List<dynamic>? ?? [];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            orderLabel,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _buildItemsTable(items),
        ],
      ),
    );
  }

  Widget _buildItemsTable(List<dynamic> items) {
    if (items.isEmpty) return const SizedBox();
    final rows = <TableRow>[];

    // ヘッダ
    rows.add(
      TableRow(
        decoration: BoxDecoration(color: Colors.grey[200]),
        children: [
          _cellHeader("商品名"),
          _cellHeader("数量"),
          _cellHeader("状態"),
          _cellHeader("小計"),
        ],
      ),
    );

    // 明細
    for (var i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      final name = item['itemName'] as String? ?? '';
      final qty = (item['quantity'] as int?) ?? 0;
      final status = item['status'] as String? ?? 'unprovided';
      final price = (item['itemPrice'] as num?)?.toDouble() ?? 0.0;

      final isCanceled = (status == 'canceled');

      // キャンセルされたアイテムは小計を0円として表示
      final subTotal = isCanceled ? 0.0 : price * qty;
      final subTotalText = isCanceled
          ? '¥0'
          : '¥${subTotal.toStringAsFixed(0)}';

      rows.add(
        TableRow(
          children: [
            _cellBody(name),
            _cellBody("$qty"),
            _cellBodyWidget(_statusLabel(status)),
            _cellBody(subTotalText, color: isCanceled ? Colors.red : null),
          ],
        ),
      );
    }

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      columnWidths: const {
        0: FlexColumnWidth(3.0),
        1: FlexColumnWidth(0.6),
        2: FlexColumnWidth(1.0),
        3: FlexColumnWidth(1.0),
      },
      children: rows,
    );
  }

  Widget _cellHeader(String text) {
    return Container(
      padding: const EdgeInsets.all(6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _cellBody(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(6),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: color ?? Colors.black87),
      ),
    );
  }

  Widget _cellBodyWidget(Widget child) {
    return Container(
      padding: const EdgeInsets.all(6),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  Widget _statusLabel(String status) {
    String label;
    Color bgColor;
    switch (status) {
      case 'unprovided':
        label = '未提供';
        bgColor = Colors.redAccent;
        break;
      case 'provided':
        label = '済';
        bgColor = Colors.green;
        break;
      case 'canceled':
        label = '取消';
        bgColor = Colors.grey;
        break;
      default:
        label = status;
        bgColor = Colors.grey;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }
}

class TableListPage extends StatefulWidget {
  final int storeId;
  const TableListPage({super.key, required this.storeId});

  @override
  State<TableListPage> createState() => _TableListPageState();
}

class _TableListPageState extends State<TableListPage> {
  // orders テーブルのストリーム
  late final Stream<List<Map<String, dynamic>>> _ordersStream;
  // table_colors テーブル用のストリーム購読
  StreamSubscription<List<Map<String, dynamic>>>? _tableColorStreamSub;

  // payment_history の該当レコードを購読するサブスク (Square決済用)
  StreamSubscription<List<Map<String, dynamic>>>? _paymentHistoryStreamSub;

  // 現在処理中のテーブル名（Square支払いが進行中かどうかを追跡）
  String? _processingTableName;

  // 支払い処理が完了したかどうかのフラグ (Square用)
  bool _paymentCompleted = false;

  // タイムアウト用タイマー (Square用)
  Timer? _checkoutTimeoutTimer;

  // ポーリング用タイマー (Square用)
  Timer? _pollingTimer;

  // 現在処理中のペイメントID (Square用)
  String? _currentPaymentHistoryId;

  // フィルタ選択
  OrderFilter _selectedFilter = OrderFilter.all;

  @override
  void initState() {
    super.initState();
    print('TableListPage: initState');

    // ordersテーブル: store_id 絞り込みストリーム
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('store_id', widget.storeId)
        .order('created_at', ascending: false);

    // table_colors を購読: store_id 絞り込み
    _tableColorStreamSub = supabase
        .from('table_colors')
        .stream(primaryKey: ['store_id', 'table_name']) // 複合主キー
        .eq('store_id', widget.storeId)
        .listen((rows) {
      print('TableListPage: table_colors updated with ${rows.length} rows');
      TableColorManager.updateTableColors(rows);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    print('TableListPage: dispose');
    _tableColorStreamSub?.cancel();
    _paymentHistoryStreamSub?.cancel();
    _checkoutTimeoutTimer?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 支払い完了フラグがtrueなら会計履歴ページに遷移 (Square決済用)
    if (_paymentCompleted && mounted) {
      print('TableListPage: payment completed, navigating to payment history');
      _paymentCompleted = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToPaymentHistory();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('テーブル管理'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print('TableListPage: StreamBuilder error: ${snapshot.error}');
            return Center(
              child: Text(
                'エラー: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snapshot.hasData) {
            print('TableListPage: StreamBuilder waiting for data');
            return const Center(child: CircularProgressIndicator());
          }

          final allOrders = snapshot.data!;
          print('TableListPage: StreamBuilder received ${allOrders.length} orders');

          // アーカイブされていない注文のみをフィルタ
          final orders = allOrders.where((order) => order['archived'] != true).toList();

          if (orders.isEmpty) {
            return const EmptyOrdersView();
          }

          // フィルタに応じて絞り込み
          final filteredOrders = _filterOrders(orders);

          // テーブル別にグルーピング
          final tableMap = _groupByTable(filteredOrders);
          final tableNames = tableMap.keys.toList();

          return Column(
            children: [
              // フィルタUI
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      "フィルタ: ",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButton<OrderFilter>(
                      value: _selectedFilter,
                      items: OrderFilter.values.map((f) {
                        return DropdownMenuItem(
                          value: f,
                          child: Text(f.label),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedFilter = val);
                        }
                      },
                    ),
                  ],
                ),
              ),

              // 処理中のテーブルがある場合、通知バーを表示 (Square決済フロー用)
              if (_processingTableName != null)
                _buildProcessingNotificationBar(),

              // テーブルごとの表示
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: tableNames.length,
                  itemBuilder: (context, index) {
                    final tName = tableNames[index];
                    final tOrders = tableMap[tName]!;

                    // 処理中のテーブルかどうか (Square)
                    final isProcessing = _processingTableName == tName;

                    return _TableBlock(
                      tableName: tName,
                      orders: tOrders,
                      isProcessing: isProcessing,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- ここから下はSquare決済で使う既存フロー ---

  // 処理中表示用の通知バー (Square決済フロー用)
  Widget _buildProcessingNotificationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.blue.shade100,
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'テーブル [$_processingTableName] の決済処理中...',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          // 手動更新ボタン
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: () {
              if (_currentPaymentHistoryId != null && _processingTableName != null) {
                _checkPaymentStatus(_currentPaymentHistoryId!, _processingTableName!);
              }
            },
            tooltip: '状態を更新',
            iconSize: 20,
          ),
          // キャンセルボタン
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red),
            onPressed: () => _cancelProcessing(),
            tooltip: '処理をキャンセル',
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  // 処理をキャンセル (Square決済のキャンセル)
  void _cancelProcessing() {
    if (_processingTableName == null) return;

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('処理キャンセル'),
        content: Text('テーブル [$_processingTableName] の決済処理をキャンセルしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('いいえ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('はい'),
          ),
        ],
      ),
    ).then((confirm) async {
      if (confirm == true) {
        _checkoutTimeoutTimer?.cancel();
        _checkoutTimeoutTimer = null;
        _pollingTimer?.cancel();
        _pollingTimer = null;

        await _paymentHistoryStreamSub?.cancel();
        _paymentHistoryStreamSub = null;

        if (_currentPaymentHistoryId != null) {
          try {
            await supabase.from('payment_history').update({
              'status': 'canceled_by_user',
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', _currentPaymentHistoryId!);
            print('Payment history record $_currentPaymentHistoryId marked as canceled_by_user');
          } catch (e) {
            print('Error canceling payment: $e');
          }
        }

        setState(() {
          _processingTableName = null;
          _currentPaymentHistoryId = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('決済処理をキャンセルしました')),
          );
        }
      }
    });
  }

  /// Square用: 会計処理ボタンが押されたときのフロー
  Future<void> _handleCheckout(String tableName, double total) async {
    print('_handleCheckout: tableName=$tableName, total=$total');

    // 処理中のテーブル名をセット
    setState(() {
      _processingTableName = tableName;
    });

    // Square Terminal Checkoutの作成
    final success = await _createSquareCheckout(tableName, total);
    if (!success) {
      // 失敗した場合は処理中状態を解除
      setState(() {
        _processingTableName = null;
        _currentPaymentHistoryId = null;
      });
      return;
    }

    // タイムアウトタイマー(2分後)
    _checkoutTimeoutTimer?.cancel();
    _checkoutTimeoutTimer = Timer(const Duration(minutes: 2), () {
      _handleCheckoutTimeout(tableName);
    });

    // Webhook / payment_history サブスク完了を待つ
  }

  // チェックアウトタイムアウト処理 (Square)
  void _handleCheckoutTimeout(String tableName) {
    print('_handleCheckoutTimeout: Payment timed out for table $tableName');

    if (!mounted) return;
    if (_processingTableName != tableName) return; // 既に別の処理に移っている場合

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('決済タイムアウト'),
        content: Text('テーブル [$tableName] の決済処理が完了していません。\n\n'
            '・処理を継続する\n'
            '・キャンセルして初めからやり直す'),
        actions: [
          TextButton(
            onPressed: () {
              // タイマーを再設定して継続
              _checkoutTimeoutTimer?.cancel();
              _checkoutTimeoutTimer = Timer(const Duration(minutes: 2), () {
                _handleCheckoutTimeout(tableName);
              });
              Navigator.pop(c);
            },
            child: const Text('処理を継続'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    ).then((shouldCancel) {
      if (shouldCancel == true) {
        _cancelProcessing();
      }
    });
  }

  /// Square チェックアウトをサーバー側で作成し、 payment_history レコードID を受け取る
  Future<bool> _createSquareCheckout(String tableName, double total) async {
    print('_createSquareCheckout: tableName=$tableName, total=$total');
    try {
      final url = Uri.parse(
        'https://aff6-2400-4150-78a0-5300-8c17-49bd-4a79-cc83.ngrok-free.app/api/payments/terminal-checkout/', // ← 適宜修正
      );

      final payload = {
        'storeId': widget.storeId,
        'amount': total.toInt(),
        'referenceId': tableName,
      };

      print('Sending request to $url with payload $payload');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      print('Response status: ${resp.statusCode}');
      print('Response body: ${resp.body}');

      if (resp.statusCode == 200) {
        final jsonBody = jsonDecode(resp.body) as Map<String, dynamic>;
        if (jsonBody['success'] == true) {
          final checkout = jsonBody['checkout'] as Map<String, dynamic>?;
          final paymentHistoryId = jsonBody['paymentHistoryId'] as String?;
          if (checkout == null || paymentHistoryId == null) {
            throw Exception('checkout or paymentHistoryId is missing');
          }

          final cid = checkout['id'];
          final cstatus = checkout['status'];
          print('Checkout created: id=$cid status=$cstatus');

          // ペイメントID保存
          _currentPaymentHistoryId = paymentHistoryId;

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Square決済開始: checkoutId=$cid')),
            );
          }

          // payment_history をサブスク
          _subscribePaymentHistory(paymentHistoryId, tableName);

          return true;
        } else {
          final errorMsg = jsonBody['error'] ?? jsonBody.toString();
          print('Checkout creation failed. body=$errorMsg');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Checkout作成失敗: $errorMsg')),
            );
          }
          return false;
        }
      } else {
        print(
          'Checkout creation failed. code=${resp.statusCode}, body=${resp.body}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Checkout作成失敗: ${resp.body}')),
          );
        }
        return false;
      }
    } catch (e) {
      print('Error creating checkout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout作成エラー: $e')),
        );
      }
      return false;
    }
  }

  /// payment_history テーブルで指定IDの status を監視 (Square)
  void _subscribePaymentHistory(String paymentHistoryId, String tableName) {
    print('_subscribePaymentHistory: id=$paymentHistoryId, table=$tableName');

    // 現在の状態を一度確認
    _checkPaymentStatus(paymentHistoryId, tableName);

    // バックアップポーリング開始
    _startPollingBackup(paymentHistoryId, tableName);

    try {
      _paymentHistoryStreamSub?.cancel();
      _paymentHistoryStreamSub = supabase
          .from('payment_history')
          .stream(primaryKey: ['id'])
          .eq('id', paymentHistoryId)
          .listen((List<Map<String, dynamic>> data) async {
        print('Payment history stream received ${data.length} records');

        if (data.isEmpty) {
          print('Payment history stream: empty data');
          return;
        }

        final row = data.first;
        final status = row['status'] as String?;
        final updatedAt = row['updated_at'] as String?;
        print('PaymentHistory status: $status, updated: $updatedAt, id=$paymentHistoryId');

        if (status == 'completed') {
          await _handlePaymentCompleted(tableName);
        } else if (status == 'failed' ||
            status == 'canceled' ||
            status == 'canceled_by_user') {
          await _handlePaymentCanceled(tableName, status ?? 'unknown');
        }
      }, onError: (error) {
        print('Payment history stream error: $error');
        if (_pollingTimer == null || !_pollingTimer!.isActive) {
          _startPollingBackup(paymentHistoryId, tableName);
        }
      });
    } catch (e) {
      print('Error setting up payment history stream: $e');
      if (_pollingTimer == null || !_pollingTimer!.isActive) {
        _startPollingBackup(paymentHistoryId, tableName);
      }
    }
  }

  // 支払い完了時の処理 (Square)
  Future<void> _handlePaymentCompleted(String tableName) async {
    print('Payment completed! Resetting table and navigating to history');

    // タイマー停止
    _checkoutTimeoutTimer?.cancel();
    _checkoutTimeoutTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;

    // テーブルリセット
    await _resetTable(tableName);

    // table_occupancy を paid に更新
    try {
      final result = await supabase
          .from('table_occupancy')
          .select('id')
          .eq('table_id', tableName)
          .eq('store_id', widget.storeId)
          .order('created_at', ascending: false)
          .limit(1)
          .single();

      if (result != null) {
        await supabase.from('table_occupancy').update({
          'status': 'paid',
          'last_paid_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', result['id']);
        print('Table occupancy updated to paid: $tableName, id: ${result['id']}');
      }
    } catch (e) {
      print('Error updating table occupancy status: $e');
    }

    // サブスク解除
    await _paymentHistoryStreamSub?.cancel();
    _paymentHistoryStreamSub = null;

    if (!mounted) return;

    // 処理フラグをクリア & 会計完了フラグをセット
    setState(() {
      _processingTableName = null;
      _currentPaymentHistoryId = null;
      _paymentCompleted = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('[$tableName] の支払いが完了しました→リセット完了')),
    );
  }

  // 支払いキャンセル時の処理 (Square)
  Future<void> _handlePaymentCanceled(String tableName, String status) async {
    print('Payment $status. Clearing processing state.');

    _checkoutTimeoutTimer?.cancel();
    _checkoutTimeoutTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;

    await _paymentHistoryStreamSub?.cancel();
    _paymentHistoryStreamSub = null;

    if (!mounted) return;

    setState(() {
      _processingTableName = null;
      _currentPaymentHistoryId = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('[$tableName] の支払いが $status になりました')),
    );
  }

  // バックアップポーリング開始 (Square)
  void _startPollingBackup(String paymentHistoryId, String tableName) {
    print('Starting backup polling for payment $paymentHistoryId');

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_processingTableName != tableName) {
        timer.cancel();
        _pollingTimer = null;
        return;
      }
      print('Polling payment status: $paymentHistoryId');
      _checkPaymentStatus(paymentHistoryId, tableName);
    });
  }

  // payment_history テーブルの現在の状態を確認 (Square)
  Future<void> _checkPaymentStatus(String paymentHistoryId, String tableName) async {
    try {
      print('Checking current payment status for id=$paymentHistoryId');
      final result = await supabase
          .from('payment_history')
          .select('*')
          .eq('id', paymentHistoryId)
          .limit(1)
          .single();

      final status = result['status'] as String?;
      final updatedAt = result['updated_at'] as String?;
      print('Current payment status: $status (updated at: $updatedAt)');

      if (status == 'completed') {
        await _handlePaymentCompleted(tableName);
      } else if (status == 'failed' ||
          status == 'canceled' ||
          status == 'canceled_by_user') {
        await _handlePaymentCanceled(tableName, status!);
      }
    } catch (e) {
      print('Error checking payment status: $e');
    }
  }

  /// テーブルリセット - Supabase RPCを使用
  Future<void> _resetTable(String tableName) async {
    print('_resetTable: tableName=$tableName');
    try {
      // RPCでアーカイブ
      await supabase.rpc('archive_orders_by_table', params: {
        'p_table_name': tableName,
      });
      print('Table reset successful');

      // 新しいセッション作成 (必要に応じて)
      final newSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}_$tableName';

      try {
        await supabase.from('table_occupancy').insert({
          'table_id': tableName,
          'store_id': widget.storeId,
          'people_count': 0,
          'status': 'active',
          'session_id': newSessionId,
          'updated_at': DateTime.now().toIso8601String(),
        });
        print('New session created for reset table: $tableName, session: $newSessionId');
      } catch (sessionErr) {
        print('Error creating new session: $sessionErr');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$tableName をリセットしました(アーカイブ済み)')),
        );
      }

    } catch (e) {
      print('テーブルリセット失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('テーブルリセット失敗: $e')),
        );
      }
      throw e;
    }
  }

  // 会計履歴ページに遷移
  void _navigateToPaymentHistory() {
    print('_navigateToPaymentHistory');
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PaymentHistoryPage(storeId: widget.storeId),
      ),
    ).then((_) {
      setState(() {});
    });
  }

  /// フィルタに応じてオーダーを絞り込み
  List<Map<String, dynamic>> _filterOrders(List<Map<String, dynamic>> orders) {
    if (_selectedFilter == OrderFilter.all) return orders;

    return orders.where((o) {
      final items = o['items'] as List<dynamic>? ?? [];
      final hasUnprovided = items.any((i) {
        final status = (i as Map)['status'];
        return status != 'provided';
      });
      if (_selectedFilter == OrderFilter.hasUnprovided) {
        return hasUnprovided;
      } else {
        // fullyProvided
        return !hasUnprovided;
      }
    }).toList();
  }

  /// テーブル名でグルーピング
  Map<String, List<Map<String, dynamic>>> _groupByTable(
      List<Map<String, dynamic>> orders,
      ) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (var o in orders) {
      final tName = o['table_name'] as String? ?? '不明テーブル';
      map.putIfAbsent(tName, () => []);
      map[tName]!.add(o);
    }
    return map;
  }

  // --- ここから下は現金会計用の追加メソッド ---

  /// 支払い方法選択ダイアログを表示 → 現金 or Square
  Future<void> _showPaymentMethodDialog(String tableName, double total) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('支払い方法を選択'),
          content: const Text('どちらで会計しますか？'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                // 現金支払い
                await _handleCashPayment(tableName, total);
              },
              child: const Text('現金'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                // Square決済
                await _handleCheckout(tableName, total);
              },
              child: const Text('Square'),
            ),
          ],
        );
      },
    );
  }

  /// 現金支払いフロー
  Future<void> _handleCashPayment(String tableName, double total) async {
    try {
      // payment_history に status='completed', payment_method='cash' でINSERT
      final inserted = await supabase.from('payment_history').insert({
        'table_name': tableName,
        'store_id': widget.storeId,
        'amount': total,
        'status': 'completed',
        'payment_method': 'cash',
        'paid_at': DateTime.now().toIso8601String(),
      }).select().single();
      print('Cash payment inserted: $inserted');

      // テーブルリセット
      await _resetTable(tableName);

      // occupancyを paid に更新
      try {
        final result = await supabase
            .from('table_occupancy')
            .select('id')
            .eq('table_id', tableName)
            .eq('store_id', widget.storeId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        // result が null でなければデータあり
        if (result != null) {
          final occupancyId = result['id'];
          await supabase.from('table_occupancy').update({
            'status': 'paid',
            'last_paid_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', occupancyId);
        }
      } catch (e) {
        print('Error updating table occupancy status for cash: $e');
      }


      // 会計履歴ページへ遷移
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('[$tableName] 現金支払い完了')),
        );
        _navigateToPaymentHistory();
      }
    } catch (e) {
      print('Error in _handleCashPayment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('現金支払いエラー: $e')),
        );
      }
    }
  }
}

/// テーブルブロック
class _TableBlock extends StatelessWidget {
  final String tableName;
  final List<Map<String, dynamic>> orders;
  final bool isProcessing; // 処理中かどうかのフラグ

  const _TableBlock({
    required this.tableName,
    required this.orders,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    final tableColor = TableColorManager.getTableColor(tableName);
    final tableStatus = _getTableStatus(orders);
    final tableTotal = _calculateTableTotal(orders);
    final orderWidgets = _buildOrderWidgets(orders);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(width: 20, color: tableColor)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tableName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                // 処理中の場合はインジケーター
                if (isProcessing)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 14,
                    height: 14,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                _TableStatusBadge(tableStatus),
              ],
            ),
          ],
        ),
        children: [
          ...orderWidgets,

          // 合計表示
          Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '合計: ¥${tableTotal.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),

          // ボタン群
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // 会計に進む
                Expanded(
                  child: ElevatedButton(
                    onPressed: isProcessing
                        ? null
                        : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('会計確認'),
                          content: Text(
                            'テーブル [$tableName]\n'
                                '¥${tableTotal.toStringAsFixed(0)} の会計を行いますか？',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;

                      // 支払い方法を選択させる
                      final parent =
                      context.findAncestorStateOfType<_TableListPageState>();
                      if (parent != null) {
                        await parent._showPaymentMethodDialog(tableName, tableTotal);
                      }
                    },
                    style: _buttonStyle(),
                    child: const Text('会計に進む'),
                  ),
                ),
                const SizedBox(width: 8),

                // テーブルリセット
                Expanded(
                  child: ElevatedButton(
                    onPressed: isProcessing
                        ? null
                        : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('テーブルリセット'),
                          content: const Text(
                            '本当にリセットしますか？\n(注文データがアーカイブされます)',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        final parent =
                        context.findAncestorStateOfType<_TableListPageState>();
                        if (parent != null) {
                          try {
                            await parent._resetTable(tableName);
                            parent._navigateToPaymentHistory();
                          } catch (e) {
                            // エラー処理は _resetTable 内で行われる
                          }
                        }
                      }
                    },
                    style: _buttonStyle(),
                    child: const Text('テーブルリセット'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.blueAccent,
      foregroundColor: Colors.white,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      padding: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  /// テーブルのステータス
  String _getTableStatus(List<Map<String, dynamic>> orders) {
    bool hasUnprovided = false;
    bool hasPaid = false;

    for (var o in orders) {
      final items = o['items'] as List<dynamic>? ?? [];
      if (items.any((i) {
        final status = (i as Map)['status'];
        return status != 'provided' && status != 'canceled';
      })) {
        hasUnprovided = true;
      }

      if (o['status'] == 'paid') {
        hasPaid = true;
      }
    }

    if (hasUnprovided) {
      return 'unprovided';
    }
    if (hasPaid) {
      return 'paid';
    }
    return 'provided';
  }

  /// テーブル合計金額
  double _calculateTableTotal(List<Map<String, dynamic>> orders) {
    double sum = 0;
    for (final o in orders) {
      final items = o['items'] as List<dynamic>? ?? [];
      for (final it in items) {
        final itemMap = it as Map<String, dynamic>;
        final qty = (itemMap['quantity'] as int?) ?? 0;
        final price = (itemMap['itemPrice'] as num?)?.toDouble() ?? 0.0;
        final status = itemMap['status'] as String? ?? 'unprovided';

        if (status != 'canceled') {
          sum += price * qty;
        }
      }
    }
    return sum;
  }

  /// オーダー明細のウィジェットリスト
  List<Widget> _buildOrderWidgets(List<Map<String, dynamic>> orders) {
    final sorted = [...orders];
    sorted.sort((a, b) {
      final tA = a['created_at'] as String? ?? '';
      final tB = b['created_at'] as String? ?? '';
      return tA.compareTo(tB);
    });

    final widgets = <Widget>[];
    for (var i = 0; i < sorted.length; i++) {
      final order = sorted[i];
      final label = (i == 0) ? "初回オーダー" : "追加オーダー$i";
      widgets.add(_OrderBlock(orderData: order, orderLabel: label));
    }
    return widgets;
  }
}
