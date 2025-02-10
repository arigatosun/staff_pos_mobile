import 'package:flutter/material.dart';
import '../supabase_manager.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';

class OrderListPage extends StatefulWidget {
  const OrderListPage({Key? key}) : super(key: key);

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  late final Stream<List<Map<String, dynamic>>> _ordersStream;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  String? _currentFCMToken;
  String _currentDeviceId = '';
  String? _deviceName;

  @override
  void initState() {
    super.initState();

    // デバイス情報の取得
    _initializeDeviceInfo();

    // FCMの初期設定 (フォアグラウンド専用)
    _setupFCM();

    // トークン更新時のリスナーを追加
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateFCMToken);

    // 「orders」テーブルのリアルタイムストリームを取得
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  /// 1) デバイス情報の初期化
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

  /// 2) FCMトークンの更新処理
  Future<void> _updateFCMToken(String token) async {
    if (_currentFCMToken == token) return;
    try {
      if (_currentDeviceId.isEmpty) {
        // 新規デバイスの登録
        final response = await supabase
            .from('pos_devices')
            .insert({
          'device_name': _deviceName ?? 'POS Device',
          'fcm_token': token,
        })
            .select()
            .single();

        _currentDeviceId = response['id'].toString();
        print('New device registered with ID: $_currentDeviceId');
      } else {
        // 既存デバイスの更新
        await supabase
            .from('pos_devices')
            .update({
          'fcm_token': token,
          'device_name': _deviceName ?? 'POS Device',
        })
            .eq('id', _currentDeviceId);
        print('Existing device updated: $_currentDeviceId');
      }

      _currentFCMToken = token;
      print('FCM token saved/updated successfully for device: $_currentDeviceId');
    } catch (e) {
      print('Error managing FCM token: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('FCMトークンの管理に失敗しました: $e')),
        );
      }
    }
  }

  /// 3) フォアグラウンドでのFCM設定
  Future<void> _setupFCM() async {
    try {
      // iOSなどでの通知許可リクエスト
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      print('User granted permission: ${settings.authorizationStatus}');

      // トークン取得
      String? token = await _firebaseMessaging.getToken();
      print("Firebase Token: $token");
      if (token != null && mounted) {
        await _updateFCMToken(token);
      }

      // フォアグラウンドメッセージのハンドリング
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Got a message whilst in the foreground!');
        print('Message data: ${message.data}');

        if (message.notification != null) {
          print('Message also contained a notification: ${message.notification}');
          if (mounted) {
            _showNotification(message);
          }
        }
      });

      // アプリがバックグラウンドから復帰したときに呼ばれる
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('A new onMessageOpenedApp event was published!');
        print('Message data: ${message.data}');
      });

      // ★ ここでは onBackgroundMessage は設定しない
      //   main.dart でトップレベル関数として登録済み
      //   FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    } catch (e) {
      print('FCM setup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通知の設定中にエラーが発生しました: $e')),
        );
      }
    }
  }

  /// 4) フォアグラウンド時の通知表示
  void _showNotification(RemoteMessage message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message.notification?.title ?? '新しい注文'),
        content: Text(message.notification?.body ?? '注文が入りました！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );

    // 音声再生 (assets/notification_sound.mp3) - フォアグラウンドのみ
    _audioPlayer.play(AssetSource('notification_sound.mp3')).catchError((error) {
      print('Error playing notification sound: $error');
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  /// 5) 注文ステータス更新
  Future<void> _updateStatus(String orderId, String newStatus) async {
    if (!mounted) return;
    try {
      final response = await supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);

      if (response is List || response is Map) {
        print('ステータス更新成功');
      } else {
        print('ステータス更新に失敗: $response');
        throw Exception('ステータス更新エラー');
      }
    } catch (e) {
      print('エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ステータス更新中にエラーが発生しました: $e')),
        );
      }
    }
  }

  /// 6) UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("スタッフ用POS"),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'エラーが発生しました: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final orders = snapshot.data!;
          if (orders.isEmpty) {
            return const _EmptyOrdersView();
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return _OrderCard(
                order: order,
                onStatusUpdate: _updateStatus,
              );
            },
          );
        },
      ),
    );
  }
}

// --- 以下はUI部品のみ変更なし ---

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final Future<void> Function(String, String) onStatusUpdate;

  const _OrderCard({
    required this.order,
    required this.onStatusUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final tableName = order['table_name'] as String?;
    final status = order['status'] as String?;
    final orderId = order['id'] as String?;
    final items = order['items'] as List<dynamic>?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // テーブル名とステータスバッジ
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.table_bar, color: Colors.teal),
                    const SizedBox(width: 6),
                    Text(
                      tableName ?? '不明',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                _StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 12),
            // 注文アイテム表示
            if (items != null && items.isNotEmpty)
              _OrderItemsView(items: items)
            else
              const Text(
                "注文内容なし",
                style: TextStyle(color: Colors.grey),
              ),
            const SizedBox(height: 12),
            // ステータス更新ボタン
            _StatusButtons(
              status: status,
              orderId: orderId,
              onStatusUpdate: onStatusUpdate,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusButtons extends StatelessWidget {
  final String? status;
  final String? orderId;
  final Future<void> Function(String, String) onStatusUpdate;

  const _StatusButtons({
    required this.status,
    required this.orderId,
    required this.onStatusUpdate,
  });

  @override
  Widget build(BuildContext context) {
    if (orderId == null) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (status != 'provided') ...[
          ElevatedButton.icon(
            onPressed: () => onStatusUpdate(orderId!, 'provided'),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text("提供完了"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber[800],
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (status != 'paid')
          ElevatedButton.icon(
            onPressed: () => onStatusUpdate(orderId!, 'paid'),
            icon: const Icon(Icons.payment),
            label: const Text("会計済み"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
            ),
          ),
      ],
    );
  }
}

class _EmptyOrdersView extends StatelessWidget {
  const _EmptyOrdersView();

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

class _StatusBadge extends StatelessWidget {
  final String? status;
  const _StatusBadge({Key? key, required this.status}) : super(key: key);

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
        bgColor = Colors.blueAccent;
        text = '提供済み';
        break;
      case 'paid':
        bgColor = Colors.green;
        text = '会計済み';
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
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _OrderItemsView extends StatelessWidget {
  final List<dynamic> items;
  const _OrderItemsView({Key? key, required this.items}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
          final itemName = itemMap['name'] as String?;
          final quantity = itemMap['quantity'] as int?;
          final price = itemMap['price'] as int?;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(itemName ?? '', maxLines: 1)),
                Text("×${quantity ?? 0}"),
                const SizedBox(width: 16),
                Text(
                  price != null ? "¥$price" : "-",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}
