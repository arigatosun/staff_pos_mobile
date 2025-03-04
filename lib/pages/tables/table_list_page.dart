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

      // 変更: キャンセルされたアイテムは小計を0円として表示
      final subTotal = isCanceled ? 0.0 : price * qty;
      final subTotalText = isCanceled
          ? '¥0'  // キャンセルされた場合は0円と表示
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

  // payment_history の該当レコードを購読するサブスク
  StreamSubscription<List<Map<String, dynamic>>>? _paymentHistoryStreamSub;

  // 現在処理中のテーブル名（支払い処理が進行中かどうかを追跡）
  String? _processingTableName;

  // 支払い処理が完了したかどうかのフラグ
  bool _paymentCompleted = false;

  // タイムアウト用タイマー
  Timer? _checkoutTimeoutTimer;

  // ポーリング用タイマー
  Timer? _pollingTimer;

  // 現在処理中のペイメントID
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
        .stream(primaryKey: ['store_id', 'table_name']) // 複合主キーの指定
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
    // 支払い完了フラグがtrueなら会計履歴ページに遷移
    if (_paymentCompleted && mounted) {
      print('TableListPage: payment completed, navigating to payment history');
      // フラグをリセットして遷移後に再度遷移しないようにする
      _paymentCompleted = false;

      // 遷移処理を非同期で行う（build中に直接Navigatorを使うのは避ける）
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

          // アーカイブされていない注文のみをフィルタリング
          final orders = allOrders.where((order) =>
          order['archived'] != true
          ).toList();

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

              // 処理中のテーブルがある場合、通知バーを表示
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

                    // 処理中のテーブルかどうかを判定
                    final isProcessing = _processingTableName == tName;

                    return _TableBlock(
                      tableName: tName,
                      orders: tOrders,
                      isProcessing: isProcessing,
                      onRequestCheckout: _handleCheckout,
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

  // 処理中表示用の通知バー
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

  // 処理をキャンセル
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
        // タイマーをキャンセル
        _checkoutTimeoutTimer?.cancel();
        _checkoutTimeoutTimer = null;
        _pollingTimer?.cancel();
        _pollingTimer = null;

        // サブスク解除
        await _paymentHistoryStreamSub?.cancel();
        _paymentHistoryStreamSub = null;

        // もし現在処理中のペイメントIDがあれば、キャンセル状態に更新
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

  /// 会計処理ボタンが押されたときのフロー
  Future<void> _handleCheckout(String tableName, double total) async {
    print('_handleCheckout: tableName=$tableName, total=$total');

    // 処理中のテーブル名をセット
    setState(() {
      _processingTableName = tableName;
    });

    // 会計ボタン押下 → Square Terminal Checkout作成
    final success = await _createSquareCheckout(tableName, total);
    if (!success) {
      // 失敗した場合は処理中状態を解除
      setState(() {
        _processingTableName = null;
        _currentPaymentHistoryId = null;
      });
      return; // API失敗時は何もしない
    }

    // タイムアウトタイマーをセット（2分後）
    _checkoutTimeoutTimer?.cancel();
    _checkoutTimeoutTimer = Timer(const Duration(minutes: 2), () {
      _handleCheckoutTimeout(tableName);
    });

    // → Webhook で支払いが 'completed' になるのを待つ (サブスクで待機)
    // テーブルリセットはWebhook完了後に行う
  }

  // チェックアウトタイムアウト処理
  void _handleCheckoutTimeout(String tableName) {
    print('_handleCheckoutTimeout: Payment timed out for table $tableName');

    if (!mounted) return;
    if (_processingTableName != tableName) return; // 既に別の処理に移っている場合

    // 確認ダイアログを表示
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
              // タイマーをリセット（継続）
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
      // Next.js API の URL
      final url = Uri.parse(
        'https://a4f3-2400-4150-78a0-5300-c8e5-3419-b8b2-3238.ngrok-free.app/api/payments/terminal-checkout/',
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

          // 現在処理中のペイメントIDを保存
          _currentPaymentHistoryId = paymentHistoryId;

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Square決済開始: checkoutId=$cid')),
            );
          }

          // payment_history のレコードをサブスク
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

  /// payment_history テーブルで、指定IDの status を監視し 'completed' になったらテーブルリセット
  void _subscribePaymentHistory(String paymentHistoryId, String tableName) {
    print('_subscribePaymentHistory: id=$paymentHistoryId, table=$tableName');

    // 現在の状態を一度確認
    _checkPaymentStatus(paymentHistoryId, tableName);

    // バックアップポーリングを開始
    _startPollingBackup(paymentHistoryId, tableName);

    try {
      // すでに購読中なら一旦キャンセル
      _paymentHistoryStreamSub?.cancel();
      _paymentHistoryStreamSub = supabase
          .from('payment_history')
          .stream(primaryKey: ['id'])
          .eq('id', paymentHistoryId)
          .listen(
            (List<Map<String, dynamic>> data) async {
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
          } else if (status == 'failed' || status == 'canceled' || status == 'canceled_by_user') {
            // null-safety対応
            await _handlePaymentCanceled(tableName, status ?? 'unknown');
          }
        },
        onError: (error) {
          // エラーハンドリング
          print('Payment history stream error: $error');
          // エラー時にポーリングが動作していることを確認
          if (_pollingTimer == null || !_pollingTimer!.isActive) {
            _startPollingBackup(paymentHistoryId, tableName);
          }
        },
      );
    } catch (e) {
      print('Error setting up payment history stream: $e');
      // エラー時にポーリングが動作していることを確認
      if (_pollingTimer == null || !_pollingTimer!.isActive) {
        _startPollingBackup(paymentHistoryId, tableName);
      }
    }
  }

  // 支払い完了時の処理
  Future<void> _handlePaymentCompleted(String tableName) async {
    print('Payment completed! Resetting table and navigating to history');

    // タイマーをキャンセル
    _checkoutTimeoutTimer?.cancel();
    _checkoutTimeoutTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;

    // 支払い完了 → テーブルリセット
    await _resetTable(tableName);

    // ★ ここに追加: 該当テーブルの最新のoccupancyレコードを取得して状態を更新
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

    // 処理中フラグをクリアして会計完了フラグをセット
    setState(() {
      _processingTableName = null;
      _currentPaymentHistoryId = null;
      _paymentCompleted = true;
    });

    // ユーザーに通知
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('[$tableName] の支払いが完了しました→リセット完了')),
    );
  }

  // 支払いキャンセル時の処理
  Future<void> _handlePaymentCanceled(String tableName, String status) async {
    print('Payment $status. Clearing processing state.');

    // タイマーをキャンセル
    _checkoutTimeoutTimer?.cancel();
    _checkoutTimeoutTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;

    // サブスク解除
    await _paymentHistoryStreamSub?.cancel();
    _paymentHistoryStreamSub = null;

    if (!mounted) return;

    // 処理中フラグをクリア
    setState(() {
      _processingTableName = null;
      _currentPaymentHistoryId = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('[$tableName] の支払いが $status になりました')),
    );
  }

  // バックアップポーリング開始
  void _startPollingBackup(String paymentHistoryId, String tableName) {
    print('Starting backup polling for payment $paymentHistoryId');

    // 既存のタイマーをキャンセル
    _pollingTimer?.cancel();

    // 5秒ごとにステータスをポーリング
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      // 処理中でなくなったらポーリングを停止
      if (_processingTableName != tableName) {
        timer.cancel();
        _pollingTimer = null;
        return;
      }

      print('Polling payment status: $paymentHistoryId');
      _checkPaymentStatus(paymentHistoryId, tableName);
    });
  }

  // payment_historyテーブルの現在の状態を確認
  Future<void> _checkPaymentStatus(String paymentHistoryId, String tableName) async {
    try {
      print('Checking current payment status for id=$paymentHistoryId');

      // キャッシュを避けるためのランダム値
      final uniqueValue = DateTime.now().millisecondsSinceEpoch;

      final result = await supabase
          .from('payment_history')
          .select('*')
          .eq('id', paymentHistoryId)
          .limit(1)
          .single();

      final status = result['status'] as String?;
      final updatedAt = result['updated_at'] as String?;
      print('Current payment status: $status (updated at: $updatedAt)');

      // すでに完了状態なら即座に処理
      if (status == 'completed') {
        await _handlePaymentCompleted(tableName);
      } else if (status == 'failed' || status == 'canceled' || status == 'canceled_by_user') {
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
      // Supabase RPCを呼び出し、テーブルリセット処理を実行
      await supabase.rpc('archive_orders_by_table', params: {
        'p_table_name': tableName,
      });
      print('Table reset successful');

      // ★ ここに追加: 新しいセッションを作成（オプション - システム自動管理方式では不要かも）
      final newSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}_$tableName';

      try {
        await supabase.from('table_occupancy').insert({
          'table_id': tableName,
          'store_id': widget.storeId,
          'people_count': 0, // 初期値
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
      throw e; // エラーを上位に伝播させる
    }
  }

  // 会計履歴ページに遷移
  void _navigateToPaymentHistory() {
    print('_navigateToPaymentHistory');
    if (!mounted) return;

    // ウィジェットがマウントされているか確認してからナビゲーション
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PaymentHistoryPage(storeId: widget.storeId),
      ),
    ).then((_) {
      // 画面に戻ってきたときにデータを強制リフレッシュ
      setState(() {
        // 状態更新をトリガー
      });
    });
  }

  /// フィルタに応じてオーダーを絞り込み
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
}

/// テーブルブロック
class _TableBlock extends StatelessWidget {
  final String tableName;
  final List<Map<String, dynamic>> orders;
  final bool isProcessing; // 処理中かどうかのフラグを追加
  final Future<void> Function(String tableName, double total) onRequestCheckout;

  const _TableBlock({
    required this.tableName,
    required this.orders,
    this.isProcessing = false,
    required this.onRequestCheckout,
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
                // 処理中の場合はインジケーターを表示
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

          // 会計 & リセットボタン
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // 会計に進む
                Expanded(
                  child: ElevatedButton(
                    onPressed: isProcessing
                        ? null // 処理中は押せないように
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

                      // 会計に進むときは onRequestCheckout を呼ぶ
                      await onRequestCheckout(tableName, tableTotal);
                    },
                    style: _buttonStyle(),
                    child: const Text('会計に進む'),
                  ),
                ),
                const SizedBox(width: 8),

                // テーブルリセット (任意: Webhook完了前に操作しないよう注意が必要)
                Expanded(
                  child: ElevatedButton(
                    onPressed: isProcessing
                        ? null // 処理中は押せないように
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
                        // _TableListPageState を取得
                        final parent = context.findAncestorStateOfType<_TableListPageState>();
                        if (parent != null) {
                          try {
                            // テーブルリセット実行
                            await parent._resetTable(tableName);

                            // リセット成功後、会計履歴ページに遷移
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

  /// テーブルのステータスを判定
  String _getTableStatus(List<Map<String, dynamic>> orders) {
    bool hasUnprovided = false;
    bool hasPaid = false;

    for (var o in orders) {
      final items = o['items'] as List<dynamic>? ?? [];

      // 一つでも「未提供」かつ「キャンセルされていない」商品があればフラグを立てる
      if (items.any((i) {
        final status = (i as Map)['status'];
        return status != 'provided' && status != 'canceled';
      })) {
        hasUnprovided = true;
      }

      // 一つでも paid 状態のオーダーがあればフラグを立てる
      if (o['status'] == 'paid') {
        hasPaid = true;
      }
    }

    // 未提供があるならテーブル全体を 'unprovided' とみなす
    if (hasUnprovided) {
      return 'unprovided';
    }
    // それ以外で一つでも paid があれば 'paid'
    if (hasPaid) {
      return 'paid';
    }
    // 上記に該当しなければ全提供済み
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

        // 変更: キャンセルされた場合は0円として扱う（マイナス計算しない）
        if (status != 'canceled') {
          sum += price * qty;
        }
        // キャンセルの場合は何も加算しない
      }
    }
    return sum;
  }

  /// オーダー明細のウィジェットリストを生成
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
