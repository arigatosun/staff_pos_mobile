import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../../services/supabase_manager.dart'; // Supabaseクライアントを取得するファイル
import '../../widgets/order_card.dart';
import '../../widgets/empty_orders_view.dart';

class OrderListPage extends StatefulWidget {
  const OrderListPage({Key? key}) : super(key: key);

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  late final Stream<List<Map<String, dynamic>>> _ordersStream;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ★ 修正箇所: DeviceInfoPlugin() のコンストラクタを使用
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  String? _currentFCMToken;
  String _currentDeviceId = '';
  String? _deviceName;

  @override
  void initState() {
    super.initState();

    _initializeDeviceInfo();
    _setupFCM();
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateFCMToken);

    // 「orders」テーブルのリアルタイムストリームを取得
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
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

  /// FCMトークンの更新処理
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

  /// フォアグラウンドでのFCM設定
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

      // フォアグラウンドメッセージ受信
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Got a message in the foreground!');
        print('Message data: ${message.data}');

        if (message.notification != null) {
          print('Notification: ${message.notification}');
          if (mounted) {
            _showNotificationDialog(message);
          }
        }
      });

      // アプリがバックグラウンドから復帰したとき
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('onMessageOpenedApp event was published!');
        print('Message data: ${message.data}');
      });
    } catch (e) {
      print('FCM setup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通知の設定中にエラーが発生しました: $e')),
        );
      }
    }
  }

  /// フォアグラウンド時の通知ダイアログ + 音声再生
  void _showNotificationDialog(RemoteMessage message) {
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

    _audioPlayer
        .play(AssetSource('notification_sound.mp3'))
        .catchError((error) {
      print('Error playing notification sound: $error');
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  /// ステータス更新 (未提供 → 提供済み)
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    try {
      final updateResponse = await supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId)
          .select()
          .maybeSingle();

      print('--- Debug: updateResponse ---');
      print('Data: $updateResponse');

      if (updateResponse == null) {
        throw Exception('ステータス更新エラー: No data returned');
      }
      // 簡易的に成功判定
      if (updateResponse is List && updateResponse.isEmpty) {
        throw Exception('ステータス更新エラー: Empty list');
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

  @override
  Widget build(BuildContext context) {
    // 注文一覧をリアルタイムに受け取る
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'エラーが発生しました: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = snapshot.data!;
        if (orders.isEmpty) {
          return const EmptyOrdersView();
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return OrderCard(
              orderData: order,
              onStatusUpdate: updateOrderStatus,
            );
          },
        );
      },
    );
  }
}
