import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../services/supabase_manager.dart';
import '../../widgets/empty_orders_view.dart';

/// フィルタ種類
enum OrderFilter {
  all('すべて'),
  hasUnprovided('未提供あり'),
  fullyProvided('全提供済み');

  final String label;
  const OrderFilter(this.label);
}

class TableListPage extends StatefulWidget {
  const TableListPage({Key? key}) : super(key: key);

  @override
  State<TableListPage> createState() => _TableListPageState();
}

class _TableListPageState extends State<TableListPage> {
  late final Stream<List<Map<String, dynamic>>> _ordersStream;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  String? _currentFCMToken;
  String _currentDeviceId = '';
  String? _deviceName;

  Timer? _timer; // 1分ごとに再ビルド
  OrderFilter _selectedFilter = OrderFilter.all;

  @override
  void initState() {
    super.initState();
    _initializeDeviceInfo();
    _setupFCM();
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateFCMToken);

    // リアルタイムストリーム
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    // 1分おきに再ビルド
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// デバイス情報の取得
  Future<void> _initializeDeviceInfo() async {
    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        _deviceName = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _deviceName = '${iosInfo.name} ${iosInfo.model}';
      }
    } catch (e) {
      print('Error getting device info: $e');
      _deviceName = 'Unknown Device';
    }
  }

  /// FCMトークン更新
  Future<void> _updateFCMToken(String token) async {
    if (_currentFCMToken == token) return;
    try {
      if (_currentDeviceId.isEmpty) {
        // 新規
        final response = await supabase
            .from('pos_devices')
            .insert({
          'device_name': _deviceName ?? 'POS Device',
          'fcm_token': token,
        })
            .select()
            .single();
        _currentDeviceId = response['id'].toString();
      } else {
        // 更新
        await supabase
            .from('pos_devices')
            .update({
          'fcm_token': token,
          'device_name': _deviceName ?? 'POS Device',
        })
            .eq('id', _currentDeviceId);
      }
      _currentFCMToken = token;
      print('FCM token saved: $_currentDeviceId');
    } catch (e) {
      print('Error managing FCM token: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('FCMトークン管理エラー: $e')),
        );
      }
    }
  }

  /// FCMセットアップ
  Future<void> _setupFCM() async {
    try {
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true, badge: true, sound: true,
      );
      print('Granted: ${settings.authorizationStatus}');

      final token = await _firebaseMessaging.getToken();
      if (token != null && mounted) {
        await _updateFCMToken(token);
      }

      FirebaseMessaging.onMessage.listen((m) {
        if (mounted) _showNotificationDialog(m);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        print('onMessageOpenedApp: $m');
      });
    } catch (e) {
      print('FCM setup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通知設定エラー: $e')),
        );
      }
    }
  }

  void _showNotificationDialog(RemoteMessage message) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(message.notification?.title ?? '新しい注文'),
        content: Text(message.notification?.body ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );

    _audioPlayer.play(AssetSource('notification_sound.mp3')).catchError((e) {
      print('Error playing sound: $e');
    });
  }

  /// アイテムステータス更新
  Future<void> updateItemStatus(String orderId, int itemIndex, String newStatus) async {
    try {
      final selectResp = await supabase
          .from('orders')
          .select('*')
          .eq('id', orderId)
          .maybeSingle();
      if (selectResp == null) throw Exception('対象注文なし');

      final items = selectResp['items'] as List;
      if (itemIndex < 0 || itemIndex >= items.length) {
        throw Exception('itemIndex範囲外');
      }
      items[itemIndex] = {...items[itemIndex], 'status': newStatus};

      final updateResp = await supabase
          .from('orders')
          .update({'items': items})
          .eq('id', orderId)
          .select()
          .maybeSingle();
      if (updateResp == null) throw Exception('更新失敗');
    } catch (e) {
      print('Item status update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('アイテム更新エラー: $e')),
        );
      }
    }
  }

  /// フィルタ切り替え
  void _changeFilter(OrderFilter filter) {
    setState(() => _selectedFilter = filter);
  }

  /// フィルタ適用
  List<Map<String, dynamic>> _filterOrders(List<Map<String, dynamic>> orders) {
    if (_selectedFilter == OrderFilter.all) return orders;

    return orders.where((o) {
      final items = o['items'] as List<dynamic>? ?? [];
      final unp = items.any((i) => (i as Map)['status'] == 'unprovided');
      if (_selectedFilter == OrderFilter.hasUnprovided) {
        return unp;
      } else {
        // fullyProvided
        return !unp;
      }
    }).toList();
  }

  /// テーブル名 => [orders...]
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('エラー: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = snapshot.data!;
        if (orders.isEmpty) {
          return const EmptyOrdersView();
        }

        final filtered = _filterOrders(orders);
        final tableMap = _groupByTable(filtered);
        final tableNames = tableMap.keys.toList();

        return Column(
          children: [
            // フィルタUI
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  const Text("フィルタ: "),
                  DropdownButton<OrderFilter>(
                    value: _selectedFilter,
                    items: OrderFilter.values.map((f) {
                      return DropdownMenuItem(
                        value: f,
                        child: Text(f.label),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) _changeFilter(val);
                    },
                  ),
                ],
              ),
            ),

            // テーブルごとの表示
            Expanded(
              child: ListView.builder(
                itemCount: tableNames.length,
                itemBuilder: (context, index) {
                  final tName = tableNames[index];
                  final tOrders = tableMap[tName]!;

                  return _TableBlock(
                    tableName: tName,
                    orders: tOrders,
                    onItemStatusUpdate: updateItemStatus,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TableBlock extends StatelessWidget {
  final String tableName;
  final List<Map<String, dynamic>> orders;
  final Future<void> Function(String orderId, int itemIndex, String newStatus)
  onItemStatusUpdate;

  const _TableBlock({
    Key? key,
    required this.tableName,
    required this.orders,
    required this.onItemStatusUpdate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tableStatus = _getTableStatus(orders);
    final hasNewOrder = orders.any((o) => _isNewOrder(o['created_at'] as String?));

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        // title
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tableName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                // ステータスバッジ
                _TableStatusBadge(tableStatus),
                const SizedBox(width: 6),
                // NEW(3分以内)
                if (hasNewOrder)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "NEW!",
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ],
        ),
        subtitle: null,
        children: _buildOrderWidgets(orders),
      ),
    );
  }

  String _getTableStatus(List<Map<String, dynamic>> orders) {
    // 1つでも未提供アイテムがあれば "unprovided"
    for (var o in orders) {
      final items = o['items'] as List<dynamic>? ?? [];
      if (items.any((i) => (i as Map)['status'] == 'unprovided')) {
        return 'unprovided';
      }
    }
    return 'provided';
  }

  bool _isNewOrder(String? createdAtStr) {
    if (createdAtStr == null) return false;
    try {
      final t = DateTime.parse(createdAtStr).toLocal();
      final diff = DateTime.now().difference(t).inMinutes;
      return diff < 3;
    } catch (_) {
      return false;
    }
  }

  /// テーブル内のordersを「初回オーダー / 追加オーダーn」に変換
  List<Widget> _buildOrderWidgets(List<Map<String, dynamic>> orders) {
    final sorted = [...orders];
    // created_at昇順（古い順）
    sorted.sort((a, b) {
      final tA = a['created_at'] as String? ?? '';
      final tB = b['created_at'] as String? ?? '';
      return tA.compareTo(tB);
    });

    final widgets = <Widget>[];
    for (var i = 0; i < sorted.length; i++) {
      final order = sorted[i];
      final orderLabel = i == 0 ? "初回オーダー" : "追加オーダー$i";
      widgets.add(_OrderBlock(
        orderData: order,
        orderLabel: orderLabel,
        onItemStatusUpdate: onItemStatusUpdate,
      ));
    }
    // 逆順にして初回オーダーが一番下に表示されるようにする
    return widgets.reversed.toList();
  }
}

class _TableStatusBadge extends StatelessWidget {
  final String status; // unprovided or provided
  const _TableStatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final isUnprovided = (status == 'unprovided');
    final color = isUnprovided ? Colors.redAccent : Colors.green;
    final text = isUnprovided ? '未提供' : '提供済み';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _OrderBlock extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final String orderLabel; // 初回オーダー / 追加オーダー n
  final Future<void> Function(String orderId, int itemIndex, String newStatus)
  onItemStatusUpdate;

  const _OrderBlock({
    Key? key,
    required this.orderData,
    required this.orderLabel,
    required this.onItemStatusUpdate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final orderId = orderData['id'] as String? ?? '';
    final createdAtStr = orderData['created_at'] as String?;
    final items = orderData['items'] as List<dynamic>? ?? [];

    final diffMin = _getElapsedMinutes(createdAtStr);
    final hasUnprovided = items.any((i) => (i as Map)['status'] == 'unprovided');

    return Container(
      margin: const EdgeInsets.only(top: 6, left: 8, right: 8, bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // オーダー名と経過時間
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                orderLabel,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              // 経過時間表示：遅延の場合は背景赤、テキスト白
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: (hasUnprovided && diffMin >= 10)
                    ? BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                )
                    : null,
                child: Text(
                  _formatElapsedTime(diffMin),
                  style: TextStyle(
                    fontSize: 12,
                    color: (hasUnprovided && diffMin >= 10) ? Colors.white : Colors.grey,
                    fontWeight: (hasUnprovided && diffMin >= 10) ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 商品一覧をグリッド線付きTableで表示
          _buildItemsTable(orderId, items, diffMin),
        ],
      ),
    );
  }

  /// 商品一覧を Table(枠線つき) で表示
  Widget _buildItemsTable(String orderId, List<dynamic> items, int diffMin) {
    if (items.isEmpty) {
      return const SizedBox();
    }

    final rows = <TableRow>[];

    // 1) ヘッダ行
    rows.add(
      TableRow(
        decoration: BoxDecoration(color: Colors.grey[200]),
        children: [
          _cellHeader("商品名"),
          _cellHeader("数量"),
          _cellHeader("ステータス"),
        ],
      ),
    );

    // 2) データ行
    for (var i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      final name = item['name'] as String? ?? '';
      final qty = item['quantity'] as int? ?? 0;
      final status = item['status'] as String? ?? 'unprovided';

      // 未提供かつ経過時間10分以上なら遅延表示
      final isDelayed = (status == 'unprovided' && diffMin >= 10);
      rows.add(
        TableRow(
          children: [
            _cellBody(name, isDelayed: isDelayed),
            _cellBody("$qty"),
            _cellStatusOrButton(orderId, i, status),
          ],
        ),
      );
    }

    return Table(
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      columnWidths: const {
        0: FlexColumnWidth(2.5),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.5),
      },
      children: rows,
    );
  }

  Widget _cellHeader(String text) {
    return Container(
      padding: const EdgeInsets.all(6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _cellBody(String text, {bool isDelayed = false}) {
    if (isDelayed) {
      return Container(
        padding: const EdgeInsets.all(6),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(6),
        alignment: Alignment.centerLeft,
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );
    }
  }

  Widget _cellStatusOrButton(String orderId, int itemIndex, String status) {
    if (status == 'provided') {
      // 提供済み
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            "済",
            style: TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      );
    } else if (status == 'canceled') {
      // キャンセル済み
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            "キャンセル済",
            style: TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      );
    } else {
      // 未提供なので「提供完了ボタン」と「キャンセル」ボタンを表示
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              onPressed: () => onItemStatusUpdate(orderId, itemIndex, 'provided'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                backgroundColor: Colors.blueAccent,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text("提供完了"),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () => onItemStatusUpdate(orderId, itemIndex, 'canceled'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                backgroundColor: Colors.grey,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text("キャンセル"),
            ),
          ],
        ),
      );
    }
  }

  int _getElapsedMinutes(String? createdAtStr) {
    if (createdAtStr == null) return 0;
    try {
      final dt = DateTime.parse(createdAtStr).toLocal();
      return DateTime.now().difference(dt).inMinutes;
    } catch (_) {
      return 0;
    }
  }

  String _formatElapsedTime(int minutes) {
    if (minutes < 1) return "たった今";
    if (minutes < 60) return "${minutes}分前";
    final hours = minutes ~/ 60;
    if (hours < 24) return "${hours}時間前";
    final days = hours ~/ 24;
    return "${days}日前";
  }
}
