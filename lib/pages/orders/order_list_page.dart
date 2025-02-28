import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../../services/supabase_manager.dart';

/// ---------------------------------------------------------
/// TableColorManager
/// ---------------------------------------------------------
class TableColorManager {
  static final Map<String, String> _tableColorMap = {};
  static const defaultHex = '#FF9E9E9E';

  static void updateTableColors(List<Map<String, dynamic>> rows) {
    _tableColorMap.clear();
    for (final row in rows) {
      final tableName = row['table_name'] as String?;
      final hexColor = row['hex_color'] as String? ?? defaultHex;
      if (tableName != null && tableName.isNotEmpty) {
        _tableColorMap[tableName] = hexColor;
      }
    }
    debugPrint('TableColorManager: updated (count=${_tableColorMap.length})');
  }

  static Color getTableColor(String tableName) {
    final hex = _tableColorMap[tableName] ?? defaultHex;
    return _parseColor(hex) ?? Colors.grey;
  }

  static Color? _parseColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return null;
    try {
      return Color(int.parse(hexColor.substring(1), radix: 16));
    } catch (_) {
      return null;
    }
  }
}

/// ---------------------------------------------------------
/// OrderListPage
/// ---------------------------------------------------------
class OrderListPage extends StatefulWidget {
  final int storeId;
  const OrderListPage({super.key, required this.storeId});

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage>
    with SingleTickerProviderStateMixin {
  // ---------------------- FCM関連 ----------------------
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  String? _currentFCMToken;
  String _currentDeviceId = '';
  String? _deviceName;
  bool _isSoundOn = true; // 通知音 ON/OFF

  // ---------------------- ローカル通知 ----------------------
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  late final Stream<List<Map<String, dynamic>>> _ordersStream;
  late TabController _tabController;
  final List<String> _tabs = ['未提供', '提供済', 'キャンセル'];

  // ソート方法
  String _sortMethod = 'oldest'; // or 'newest'
  Timer? _timer; // 1分おきに再描画

  // 遅延表示設定
  bool _isDelayOn = false;
  int _threshold1 = 10;
  int _threshold2 = 40;
  int _threshold3 = 60;

  StreamSubscription<List<Map<String, dynamic>>>? _tableColorStreamSub;
  StreamSubscription<List<Map<String, dynamic>>>? _storeSettingsStreamSub;

  // 通知の重複処理を防ぐためのセット
  final Set<String> _processedMessageIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);

    _initializeNotifications();
    _initializeDeviceInfo();
    _setupFCM();
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateFCMToken);

    // ★ ここで storeId を使用して絞り込み
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('store_id', widget.storeId)
        .order('created_at', ascending: false);

    // table_colors の購読
    _tableColorStreamSub = supabase
        .from('table_colors')
        .stream(primaryKey: ['table_name'])
        .eq('store_id', widget.storeId)
        .listen((rows) {
      TableColorManager.updateTableColors(rows);
      if (mounted) setState(() {});
    });

    // store_settings の購読
    _storeSettingsStreamSub = supabase
        .from('store_settings')
        .stream(primaryKey: ['store_id'])
        .eq('store_id', widget.storeId)
        .listen((rows) {
      // 最初の1行を参照 (想定)
      if (rows.isNotEmpty) {
        final row = rows.first;
        _parseStoreSettingsRow(row);
        if (mounted) setState(() {});
      }
    });

    // 1分おきに再描画
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    // 初期ロード
    _fetchStoreSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timer?.cancel();
    _audioPlayer.dispose();

    _tableColorStreamSub?.cancel();
    _storeSettingsStreamSub?.cancel();

    super.dispose();
  }

  // --------------------------------------------------------------------------
  // store_settings の読み込み
  // --------------------------------------------------------------------------
  Future<void> _fetchStoreSettings() async {
    try {
      final result = await supabase
          .from('store_settings')
          .select()
          .eq('store_id', widget.storeId)
          .maybeSingle();

      if (result != null) {
        _parseStoreSettingsRow(result);
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error fetching store_settings: $e');
    }
  }

  void _parseStoreSettingsRow(Map<String, dynamic> data) {
    final rawDelayOn = data['is_delay_highlight_on'];
    if (rawDelayOn is bool) {
      _isDelayOn = rawDelayOn;
    } else if (rawDelayOn is String) {
      _isDelayOn = (rawDelayOn.toLowerCase() == 'true');
    }

    final rawT1 = data['delay_threshold1'];
    if (rawT1 is int) {
      _threshold1 = rawT1;
    } else if (rawT1 is double) {
      _threshold1 = rawT1.toInt();
    } else if (rawT1 is String) {
      final parsed = int.tryParse(rawT1);
      if (parsed != null) _threshold1 = parsed;
    }

    final rawT2 = data['delay_threshold2'];
    if (rawT2 is int) {
      _threshold2 = rawT2;
    } else if (rawT2 is double) {
      _threshold2 = rawT2.toInt();
    } else if (rawT2 is String) {
      final parsed = int.tryParse(rawT2);
      if (parsed != null) _threshold2 = parsed;
    }

    final rawT3 = data['delay_threshold3'];
    if (rawT3 is int) {
      _threshold3 = rawT3;
    } else if (rawT3 is double) {
      _threshold3 = rawT3.toInt();
    } else if (rawT3 is String) {
      final parsed = int.tryParse(rawT3);
      if (parsed != null) _threshold3 = parsed;
    }

    debugPrint(
      '[store_settings loaded] storeId=${widget.storeId} '
          'isDelayOn=$_isDelayOn t1=$_threshold1, t2=$_threshold2, t3=$_threshold3',
    );
  }

  // --------------------------------------------------------------------------
  // 遅延ハイライト色を算出
  // --------------------------------------------------------------------------
  Color _calcDelayHighlightColor(String status, int diffMin) {
    if (!_isDelayOn || status != 'unprovided') {
      return Colors.white;
    }
    if (diffMin >= _threshold3) {
      return Colors.orange[600]!;
    } else if (diffMin >= _threshold2) {
      return Colors.orange[400]!;
    } else if (diffMin >= _threshold1) {
      return Colors.orange[100]!;
    }
    return Colors.white;
  }

  // ---------------------- FCM設定 / ローカル通知設定 など ----------------------
  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        try {
          final payload = details.payload;
          if (payload != null) {
            final data = json.decode(payload);
            print('Notification tapped with payload: $data');
          }
        } catch (e) {
          print('Error handling notification tap: $e');
        }
      },
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'orders',
        '注文通知',
        description: '新規注文の通知を受け取ります',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('notification_sound'),
      );
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> _initializeDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        _deviceName = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _deviceName = '${iosInfo.name} ${iosInfo.model}';
      }
    } catch (e) {
      print('Error getting device info: $e');
      _deviceName = 'Unknown Device';
    }
  }

  Future<void> _updateFCMToken(String token) async {
    if (_currentFCMToken == token) return;
    try {
      if (_currentDeviceId.isEmpty) {
        final resp = await supabase.from('pos_devices').insert({
          'device_name': _deviceName ?? 'POS Device',
          'fcm_token': token,
          'store_id': widget.storeId, // 店舗IDを明示的に保存
        }).select().single();
        _currentDeviceId = resp['id'].toString();
      } else {
        await supabase
            .from('pos_devices')
            .update({
          'device_name': _deviceName ?? 'POS Device',
          'fcm_token': token,
          'store_id': widget.storeId, // 店舗IDを明示的に更新
        })
            .eq('id', _currentDeviceId);
      }
      _currentFCMToken = token;
      print('FCM token updated: $_currentDeviceId with store ID ${widget.storeId}');
    } catch (e) {
      print('Error updating FCM token: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('FCMトークン管理エラー: $e')),
        );
      }
    }
  }

  Future<void> _setupFCM() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('User granted permission: ${settings.authorizationStatus}');

      final token = await _firebaseMessaging.getToken();
      print('FCM token: $token');
      if (token != null && mounted) {
        await _updateFCMToken(token);
      }

      FirebaseMessaging.onMessage.listen((message) {
        if (!mounted) return;
        _showNotificationDialog(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        print('onMessageOpenedApp: $message');
      });
    } catch (e) {
      print('FCM setup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('FCM初期化エラー: $e')),
        );
      }
    }
  }

  void _showNotificationDialog(RemoteMessage message) async {
    if (!mounted) return;

    // まず重複通知をチェック
    final String messageId = message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    if (_processedMessageIds.contains(messageId)) {
      print('通知 ${messageId.substring(0, 15)}... は既に処理済みです。スキップします。');
      return;
    }

    // 先に店舗IDの検証を行う
    final String? notificationStoreId = message.data['storeId'];
    final int? currentStoreId = SupabaseManager.getLoggedInStoreId();

    print('通知の店舗ID: $notificationStoreId');
    print('現在のログイン店舗ID: $currentStoreId');

    // 店舗IDが一致しない場合は通知をスキップ
    if (notificationStoreId != null && currentStoreId != null) {
      if (notificationStoreId != currentStoreId.toString()) {
        print('通知の店舗ID($notificationStoreId)が現在のログイン店舗ID($currentStoreId)と一致しないため、通知をスキップします');
        return;
      }
    }

    // 処理済みとしてマーク
    _processedMessageIds.add(messageId);
    // セットのサイズを制限（メモリ消費を防ぐため）
    if (_processedMessageIds.length > 100) {
      _processedMessageIds.remove(_processedMessageIds.first);
    }

    print('===== 通知表示処理開始 =====');
    print('MessageId: $messageId');
    print('通知データ: ${message.data}');

    // 店舗IDが一致した場合のみ通知を表示
    await _notificationsPlugin.show(
      DateTime.now().millisecond,
      message.notification?.title ?? '新規注文',
      message.notification?.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'orders',
          '注文通知',
          channelDescription: '新規注文の通知を受け取ります',
          importance: Importance.high,
          priority: Priority.high,
          sound: const RawResourceAndroidNotificationSound('notification_sound'),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'notification_sound.mp3',
        ),
      ),
      payload: json.encode(message.data),
    );

    if (_isSoundOn) {
      await _playNotificationSound();
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(message.notification?.title ?? '新規注文'),
        content: Text(message.notification?.body ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );

    print('===== 通知表示完了 =====');
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('notification_sound.mp3'));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  // --------------------------------------------------------------------------
  // 注文アイテムのステータス更新
  // --------------------------------------------------------------------------
  Future<void> _updateItemStatus({
    required String orderId,
    required int itemIndex,
    required String newStatus,
  }) async {
    try {
      final resp = await supabase
          .from('orders')
          .select('*')
          .eq('id', orderId)
          .maybeSingle();

      if (resp == null) throw Exception('注文が見つかりません');

      final items = resp['items'] as List;
      if (itemIndex < 0 || itemIndex >= items.length) {
        throw Exception('itemIndex範囲外');
      }

      items[itemIndex] = {
        ...items[itemIndex],
        'status': newStatus,
      };

      final result = await supabase
          .from('orders')
          .update({'items': items})
          .eq('id', orderId)
          .select();

      if (result.isNotEmpty) {
        print('ステータス更新成功: ${result.first}');
      } else {
        throw Exception('ステータス更新失敗');
      }
      print('ステータス更新: order=$orderId, index=$itemIndex => $newStatus');
    } catch (e) {
      print('ステータス更新エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ステータス更新エラー: $e')),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // StreamBuilder で受け取った orders を [未提供, 提供済, キャンセル] 用に分解
  // --------------------------------------------------------------------------
  List<_ItemData> _flattenOrders(List<Map<String, dynamic>> orders) {
    final result = <_ItemData>[];
    for (final o in orders) {
      final orderId = o['id'] as String? ?? '';
      final tableName = o['table_name'] as String? ?? '不明テーブル';
      final createdAt = o['created_at'] as String? ?? '';
      final items = o['items'] as List<dynamic>? ?? [];

      for (int i = 0; i < items.length; i++) {
        final it = items[i] as Map<String, dynamic>;
        final name = it['name'] as String? ?? '';
        final qty = it['quantity'] as int? ?? 0;
        final status = it['status'] as String? ?? 'unprovided';
        if (status == 'archived') continue;

        result.add(_ItemData(
          orderId: orderId,
          tableName: tableName,
          createdAt: createdAt,
          itemIndex: i,
          itemName: name,
          quantity: qty,
          status: status,
        ));
      }
    }
    return result;
  }

  int _calcDelayMinutes(_ItemData item) {
    if (item.status != 'unprovided') return -1;
    return _elapsedMinutes(item.createdAt);
  }

  void _sortItems(List<_ItemData> items) {
    items.sort((a, b) {
      // 遅延大きい順
      final delayA = _calcDelayMinutes(a);
      final delayB = _calcDelayMinutes(b);
      final compareDelay = delayB.compareTo(delayA);
      if (compareDelay != 0) return compareDelay;

      // 作成日時
      final localA = _parseNaiveTimestampAsUtc(a.createdAt).toLocal();
      final localB = _parseNaiveTimestampAsUtc(b.createdAt).toLocal();

      if (_sortMethod == 'oldest') {
        return localA.compareTo(localB);
      } else {
        return localB.compareTo(localA);
      }
    });
  }

  DateTime _parseNaiveTimestampAsUtc(String timeStr) {
    if (timeStr.isEmpty) {
      return DateTime.now();
    }
    final naive = DateTime.parse(timeStr);
    return DateTime.utc(
      naive.year,
      naive.month,
      naive.day,
      naive.hour,
      naive.minute,
      naive.second,
      naive.millisecond,
      naive.microsecond,
    );
  }

  int _elapsedMinutes(String? createdAtStr) {
    if (createdAtStr == null || createdAtStr.isEmpty) return 0;
    try {
      final localDt = _parseNaiveTimestampAsUtc(createdAtStr).toLocal();
      return DateTime.now().difference(localDt).inMinutes;
    } catch (_) {
      return 0;
    }
  }

  List<_ItemData> _filterByStatus(List<_ItemData> items, String tab) {
    switch (tab) {
      case '未提供':
        return items.where((i) => i.status == 'unprovided').toList();
      case '提供済':
        return items.where((i) => i.status == 'provided').toList();
      case 'キャンセル':
        return items.where((i) => i.status == 'canceled').toList();
      default:
        return items;
    }
  }

  void _toggleSortMethod() {
    setState(() {
      _sortMethod = (_sortMethod == 'oldest') ? 'newest' : 'oldest';
    });
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('注文管理'),
        centerTitle: true,
        actions: [
          Row(
            children: [
              const Icon(Icons.volume_up, size: 18),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _isSoundOn,
                  onChanged: (val) => setState(() => _isSoundOn = val),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeTrackColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.5),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.grey[400],
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  trackOutlineColor:
                  WidgetStateProperty.all(Colors.transparent),
                ),
              ),
              IconButton(
                onPressed: _toggleSortMethod,
                icon: const Icon(Icons.swap_vert),
                tooltip: (_sortMethod == 'oldest')
                    ? '並び替え: 古い順 → 新着順'
                    : '並び替え: 新着順 → 古い順',
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelStyle:
          const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(width: 2, color: Colors.white),
          ),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream,
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

          final allItems = _flattenOrders(snapshot.data!);

          // タブに応じてフィルタ・ソート
          return TabBarView(
            controller: _tabController,
            children: _tabs.map((tab) {
              final filtered = _filterByStatus(allItems, tab);
              _sortItems(filtered);

              if (filtered.isEmpty) {
                return const _EmptyOrdersView();
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final item = filtered[i];
                  final diffMin = _elapsedMinutes(item.createdAt);

                  final tableColor =
                  TableColorManager.getTableColor(item.tableName);
                  final bgColor =
                  _calcDelayHighlightColor(item.status, diffMin);

                  return _buildDismissible(item, tableColor, bgColor);
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildDismissible(_ItemData item, Color tableColor, Color bgColor) {
    final keyVal = ValueKey('${item.orderId}_${item.itemIndex}_${item.status}');
    final isUnprovided = (item.status == 'unprovided');
    final isCanceled = (item.status == 'canceled');
    final isProvided = (item.status == 'provided');

    final canSwipe = (isUnprovided || isCanceled || isProvided);
    final direction = canSwipe ? DismissDirection.horizontal : DismissDirection.none;

    return Dismissible(
      key: keyVal,
      direction: direction,
      confirmDismiss: (dir) async {
        if (isUnprovided && dir == DismissDirection.endToStart) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('キャンセル確認'),
              content: Text('「${item.itemName} ×${item.quantity}」をキャンセルしますか？'),
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
          );
          if (confirm != true) return false;
        } else if (isCanceled) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('未提供に戻す確認'),
              content: Text('「${item.itemName} ×${item.quantity}」を未提供に戻しますか？'),
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
          );
          if (confirm != true) return false;
        } else if (isProvided) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('未提供に戻す確認'),
              content: Text('「${item.itemName} ×${item.quantity}」を未提供に戻しますか？'),
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
          );
          if (confirm != true) return false;
        }
        return true;
      },
      onDismissed: (dir) async {
        if (isUnprovided) {
          if (dir == DismissDirection.startToEnd) {
            await _updateItemStatus(
              orderId: item.orderId,
              itemIndex: item.itemIndex,
              newStatus: 'provided',
            );
          } else {
            await _updateItemStatus(
              orderId: item.orderId,
              itemIndex: item.itemIndex,
              newStatus: 'canceled',
            );
          }
        } else if (isCanceled) {
          await _updateItemStatus(
            orderId: item.orderId,
            itemIndex: item.itemIndex,
            newStatus: 'unprovided',
          );
        } else if (isProvided) {
          await _updateItemStatus(
            orderId: item.orderId,
            itemIndex: item.itemIndex,
            newStatus: 'unprovided',
          );
        }
      },
      background: _buildSwipeBackground(item, isStartToEnd: true),
      secondaryBackground: _buildSwipeBackground(item, isStartToEnd: false),
      child: _OrderCard(
        itemData: item,
        tableColor: tableColor,
        bgColor: bgColor,
      ),
    );
  }

  Widget _buildSwipeBackground(_ItemData item, {required bool isStartToEnd}) {
    final isUnprovided = (item.status == 'unprovided');
    final isCanceled = (item.status == 'canceled');
    final isProvided = (item.status == 'provided');

    if (isStartToEnd) {
      if (isUnprovided) {
        return Container(
          color: Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.check, color: Colors.white),
              SizedBox(width: 8),
              Text(
                "提供済にする",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      } else if (isCanceled || isProvided) {
        return Container(
          color: Colors.blue,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.undo, color: Colors.white),
              SizedBox(width: 8),
              Text(
                "未提供に戻す",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      }
    } else {
      // DismissDirection.endToStart
      if (isUnprovided) {
        return Container(
          color: Colors.red,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.cancel_outlined, color: Colors.white),
              SizedBox(width: 8),
              Text(
                "キャンセル",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      } else if (isCanceled || isProvided) {
        return Container(
          color: Colors.blue,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.undo, color: Colors.white),
              SizedBox(width: 8),
              Text(
                "未提供に戻す",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      }
    }
    return const SizedBox.shrink();
  }
}

// モデルクラス
class _ItemData {
  final String orderId;
  final String tableName;
  final String createdAt;
  final int itemIndex;
  final String itemName;
  final int quantity;
  final String status;

  _ItemData({
    required this.orderId,
    required this.tableName,
    required this.createdAt,
    required this.itemIndex,
    required this.itemName,
    required this.quantity,
    required this.status,
  });
}

class _OrderCard extends StatelessWidget {
  final _ItemData itemData;
  final Color tableColor;
  final Color bgColor;

  const _OrderCard({
    required this.itemData,
    required this.tableColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    final diffMin = _elapsedMinutes(itemData.createdAt);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(width: 20, color: tableColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 上段
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                itemData.tableName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              _buildStatusBadge(itemData.status),
            ],
          ),
          const SizedBox(height: 6),
          // 下段
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${itemData.itemName} ×${itemData.quantity}",
                style: const TextStyle(fontSize: 13),
              ),
              Row(
                children: [
                  if (_isNew(diffMin)) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.yellow,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "新着!",
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    _formatElapsedTime(diffMin),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    switch (status) {
      case 'unprovided':
        return _badge('未提供', Colors.grey);
      case 'provided':
        return _badge('提供済', Colors.green);
      case 'canceled':
        return _badge('キャンセル', Colors.redAccent);
      default:
        return _badge(status, Colors.grey);
    }
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  bool _isNew(int diffMin) => (diffMin < 3);

  int _elapsedMinutes(String createdAtStr) {
    if (createdAtStr.isEmpty) return 0;
    try {
      final naive = DateTime.parse(createdAtStr);
      final dtUtc = DateTime.utc(
        naive.year,
        naive.month,
        naive.day,
        naive.hour,
        naive.minute,
        naive.second,
        naive.millisecond,
        naive.microsecond,
      );
      return DateTime.now().difference(dtUtc.toLocal()).inMinutes;
    } catch (e) {
      print('Time parsing error: $e');
      return 0;
    }
  }

  String _formatElapsedTime(int minutes) {
    if (minutes < 1) return "たった今";
    if (minutes < 60) return "$minutes分前";
    final hours = minutes ~/ 60;
    if (hours < 24) return "$hours時間前";
    final days = hours ~/ 24;
    return "$days日前";
  }
}

class _EmptyOrdersView extends StatelessWidget {
  const _EmptyOrdersView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '該当の注文はありません',
        style: TextStyle(color: Colors.grey, fontSize: 16),
      ),
    );
  }
}