import 'package:flutter/material.dart';
import '../supabase_manager.dart'; // Supabase Manager のパスは適宜調整
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:audioplayers/audioplayers.dart';

// バックグラウンドメッセージハンドラー（トップレベル関数）
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling a background message: ${message.messageId}");
  // 必要であれば、ここで追加の処理（ローカル通知の表示など）を行う。
  // ※ バックグラウンドでの音声再生には、通常、ネイティブ実装が必要。
}

class OrderListPage extends StatefulWidget {
  const OrderListPage({Key? key}) : super(key: key);

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  late final Stream<List<Map<String, dynamic>>> _ordersStream;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();

    _setupFCM();

    // 「orders」テーブルのリアルタイムストリームを取得
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  Future<void> _setupFCM() async {
    // 権限リクエスト（iOS, Web）
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false, // 必要に応じて true に
      provisional: false,
      sound: true,
    );

    print('User granted permission: ${settings.authorizationStatus}');

    // FCM トークンの取得とサーバーへの送信（必要に応じて）
    String? token = await _firebaseMessaging.getToken();
    print("Firebase Token: $token");
    // TODO: ここで、FCM トークンをサーバーに送信する処理を実装

    // フォアグラウンドメッセージのハンドリング
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');

      if (message.notification != null) {
        print('Message also contained a notification: ${message.notification}');
        _showNotification(message);
      }
    });

    // バックグラウンドからの復帰時の処理
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('A new onMessageOpenedApp event was published!');
      // TODO: 通知をタップしてアプリを開いた際の処理（例：特定の画面への遷移）
    });

    // バックグラウンドメッセージハンドラーの設定
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // 通知を表示する関数
  void _showNotification(RemoteMessage message) {
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

    // 音を鳴らす
    _audioPlayer.play(AssetSource('notification_sound.mp3'));
  }

  @override
  void dispose() {
    _audioPlayer.dispose(); // リソースの解放
    super.dispose();
  }

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
          // 通信中 or データ未取得
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // エラー時の表示
          if (snapshot.hasError) {
            return Center(
              child: Text('エラーが発生しました: ${snapshot.error}',
                  style: TextStyle(color: Colors.red)),
            );
          }

          // データ取得完了
          final orders = snapshot.data!;
          if (orders.isEmpty) {
            return const _EmptyOrdersView();
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final o = orders[index];
              final tableName = o['table_name'] as String?;
              final status = o['status'] as String?;
              final orderId = o['id'] as String?;
              final items = o['items'] as List<dynamic>?;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 上段: テーブル名とステータスバッジ
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

                      // 注文内容
                      if (items != null && items.isNotEmpty)
                        _OrderItemsView(items: items)
                      else
                        const Text(
                          "注文内容なし",
                          style: TextStyle(color: Colors.grey),
                        ),

                      const SizedBox(height: 12),

                      // ステータス変更ボタン
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (status != 'provided') ...[
                            ElevatedButton.icon(
                              onPressed: () async {
                                await _updateStatus(orderId!, 'provided');
                              },
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
                              onPressed: () async {
                                await _updateStatus(orderId!, 'paid');
                              },
                              icon: const Icon(Icons.payment),
                              label: const Text("会計済み"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[600],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// ステータス更新
  Future<void> _updateStatus(String orderId, String newStatus) async {
    try {
      final response = await supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);

      if (response is List || response is Map) {
        debugPrint('ステータス更新成功');
      } else {
        debugPrint('ステータス更新に失敗: $response');
        throw Exception('ステータス更新エラー');
      }
    } catch (e) {
      debugPrint('エラー: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ステータス更新中にエラーが発生しました: $e'))
      );
    }
  }
}

/// 注文アイテム表示用ウィジェット (変更なし)
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

/// ステータスバッジ（色分け）(変更なし)
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

/// 「まだ注文はありません」用のWidget (変更なし)
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