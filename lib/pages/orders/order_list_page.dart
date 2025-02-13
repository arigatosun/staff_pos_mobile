import 'dart:async';
import 'dart:convert'; // ★ JSONデコード用
import 'dart:io' show Platform; // ★ Platform判定用
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // ★ 追加
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';

import '../../services/supabase_manager.dart';

/// テーブルカラー管理クラス:
/// - 20色のプリセットを持つ
/// - Supabase上の `table_colors` テーブルと同期する
class TableColorManager {
  static const List<Color> presetColors = [
    Color(0xFF1E88E5),  // 青
    Color(0xFF43A047),  // 緑
    Color(0xFFE53935),  // 赤
    Color(0xFF8E24AA),  // 紫
    Color(0xFFFFB300),  // オレンジ
    Color(0xFF00ACC1),  // シアン
    Color(0xFF5E35B1),  // ディープパープル
    Color(0xFF00897B),  // ティール
    Color(0xFFF4511E),  // ディープオレンジ
    Color(0xFF7CB342),  // ライトグリーン
    Color(0xFF3949AB),  // インディゴ
    Color(0xFFD81B60),  // ピンク
    Color(0xFF6D4C41),  // ブラウン
    Color(0xFF039BE5),  // ライトブルー
    Color(0xFF546E7A),  // ブルーグレー
    Color(0xFF8D6E63),  // ブラウン
    Color(0xFF616161),  // グレー
    Color(0xFF607D8B),  // ブルーグレー
    Color(0xFFFB8C00),  // オレンジ
    Color(0xFF0097A7),  // シアン
  ];

  static const Color defaultColor = Color(0xFF9E9E9E);
  static final Map<String, int> _tableColorMap = {};
  static bool _isLoaded = false;

  static Future<void> loadTableColorsFromSupabase() async {
    if (_isLoaded) return;
    try {
      final response = await supabase
          .from('table_colors')
          .select('table_name,color_index');
      if (response is List) {
        for (final row in response) {
          final name = row['table_name'] as String;
          final idx = row['color_index'] as int;
          _tableColorMap[name] = idx;
        }
      }
      _isLoaded = true;
      debugPrint('TableColorManager: Loaded ${_tableColorMap.length} entries.');
    } catch (error, stack) {
      debugPrint('loadTableColorsFromSupabase error: $error');
    }
  }

  static Future<Color> getTableColor(String tableName) async {
    if (!_isLoaded) {
      await loadTableColorsFromSupabase();
    }
    final existingIdx = _tableColorMap[tableName];
    if (existingIdx != null &&
        existingIdx >= 0 &&
        existingIdx < presetColors.length) {
      return presetColors[existingIdx];
    }

    // 新規割り当て
    final newIndex = _findUnusedColorIndex();
    if (newIndex == null) {
      debugPrint('No more preset colors available. Using defaultColor.');
      _tableColorMap[tableName] = -1;
      return defaultColor;
    }
    _tableColorMap[tableName] = newIndex;
    await _saveNewColorMapping(tableName, newIndex);
    return presetColors[newIndex];
  }

  static int? _findUnusedColorIndex() {
    for (int i = 0; i < presetColors.length; i++) {
      if (!_tableColorMap.values.contains(i)) {
        return i;
      }
    }
    return null;
  }

  static Future<void> _saveNewColorMapping(String tableName, int colorIndex) async {
    try {
      final inserted = await supabase.from('table_colors').insert({
        'table_name': tableName,
        'color_index': colorIndex,
      });
      if (inserted is List && inserted.isNotEmpty) {
        debugPrint('Assigned color_index=$colorIndex for table "$tableName".');
      }
    } catch (e) {
      debugPrint('Failed to insert table_colors: $e');
    }
  }
}

/// ---------------------------------------------------------
/// OrderListPage
/// ---------------------------------------------------------
class OrderListPage extends StatefulWidget {
  const OrderListPage({Key? key}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);

    // ★ 通知の初期化を追加
    _initializeNotifications();

    _initializeDeviceInfo();
    _setupFCM();
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateFCMToken);

    // リアルタイム
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    // 1分おきに再描画
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    // テーブルカラーの初期ロード
    TableColorManager.loadTableColorsFromSupabase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ---------------------- 通知初期化 ----------------------
  Future<void> _initializeNotifications() async {
    // Android用の初期化設定
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS用の初期化設定
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // 通知初期化
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        _handleNotificationTap(details);
      },
    );

    // Android の通知チャネル作成
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

  void _handleNotificationTap(NotificationResponse details) {
    // 通知をタップしたときのコールバック
    try {
      final payload = details.payload;
      if (payload != null) {
        final data = json.decode(payload);
        // ここで特定の画面への遷移やデータ処理を行う
        print('Notification tapped with payload: $data');
      }
    } catch (e) {
      print('Error handling notification tap: $e');
    }
  }

  // ---------------- デバイス情報 ----------------
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

  // ---------------- FCM ----------------
  Future<void> _updateFCMToken(String token) async {
    if (_currentFCMToken == token) return;
    try {
      if (_currentDeviceId.isEmpty) {
        final resp = await supabase
            .from('pos_devices')
            .insert({
          'device_name': _deviceName ?? 'POS Device',
          'fcm_token': token,
        })
            .select()
            .single();
        _currentDeviceId = resp['id'].toString();
      } else {
        await supabase
            .from('pos_devices')
            .update({
          'device_name': _deviceName ?? 'POS Device',
          'fcm_token': token,
        })
            .eq('id', _currentDeviceId);
      }
      _currentFCMToken = token;
      print('FCM token updated: $_currentDeviceId');
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
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
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

  /// 通知を受信した際にローカル通知を表示＆ダイアログ表示
  void _showNotificationDialog(RemoteMessage message) async {
    if (!mounted) return;

    // ローカル通知の表示
    await _notificationsPlugin.show(
      DateTime.now().millisecond, // 適当なID
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
          // iOS 側に組み込み済みのサウンドファイル名 (拡張子不要 / または .caf 等)
          sound: 'notification_sound.mp3',
        ),
      ),
      payload: json.encode(message.data),
    );

    // 既存の通知音再生（アプリがフォアグラウンドの場合用）
    if (_isSoundOn) {
      await _playNotificationSound();
    }

    // フォアグラウンド時はダイアログ表示
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
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('notification_sound.mp3'));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  // ---------------- ステータス更新 ----------------
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

      try {
        final result = await supabase
            .from('orders')
            .update({'items': items})
            .eq('id', orderId)
            .select();

        if (result is List && result.isNotEmpty) {
          final updatedRow = result.first;
          print('ステータス更新成功: $updatedRow');
        } else {
          throw Exception('ステータス更新失敗（更新後の行が返らなかった）');
        }
      } catch (e) {
        print('ステータス更新エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ステータス更新エラー: $e')),
          );
        }
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

  // ---------------- リスト生成・ソート・フィルタ ----------------
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

        // archived は除外
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

  /// 未提供で10分以上 => 遅延扱い
  int _calcDelayMinutes(_ItemData item) {
    if (item.status != 'unprovided') return -1;
    final diff = _elapsedMinutes(item.createdAt);
    return diff >= 10 ? diff : -1;
  }

  void _sortItems(List<_ItemData> items) {
    items.sort((a, b) {
      final delayA = _calcDelayMinutes(a);
      final delayB = _calcDelayMinutes(b);

      // 遅延大きい順
      final compareDelay = delayB.compareTo(delayA);
      if (compareDelay != 0) return compareDelay;

      // 作成日時 (古い or 新着)
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
    return dtUtc;
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

  Future<Color> _getTableColor(String tableName) async {
    return TableColorManager.getTableColor(tableName);
  }

  // ---------------- UI ----------------
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
                  activeColor: Theme.of(context).colorScheme.primary,
                  activeTrackColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.5),
                  inactiveThumbColor: Colors.grey[50],
                  inactiveTrackColor: Colors.grey[400],
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

          return TabBarView(
            controller: _tabController,
            children: _tabs.map((tab) {
              final filtered = _filterByStatus(allItems, tab);
              _sortItems(filtered);

              if (filtered.isEmpty) {
                return const _EmptyOrdersView();
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final item = filtered[i];
                  return FutureBuilder<Color>(
                    future: _getTableColor(item.tableName),
                    builder: (context, snapColor) {
                      final color =
                          snapColor.data ?? TableColorManager.defaultColor;
                      return _buildDismissible(item, color);
                    },
                  );
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }

  /// スワイプ操作 (未提供→提供済 or キャンセル など)
  Widget _buildDismissible(_ItemData item, Color tableColor) {
    final keyVal = ValueKey('${item.orderId}_${item.itemIndex}_${item.status}');
    final isUnprovided = item.status == 'unprovided';
    final isCanceled = item.status == 'canceled';
    final isProvided = item.status == 'provided';

    final canSwipe = isUnprovided || isCanceled || isProvided;
    final direction =
    canSwipe ? DismissDirection.horizontal : DismissDirection.none;

    return Dismissible(
      key: keyVal,
      direction: direction,
      confirmDismiss: (dir) async {
        // 未提供 → キャンセル
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
        }

        // キャンセル → 未提供
        if (isCanceled) {
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

        // 提供済 → 未提供
        if (isProvided) {
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
            // 右 => 提供済
            await _updateItemStatus(
              orderId: item.orderId,
              itemIndex: item.itemIndex,
              newStatus: 'provided',
            );
          } else {
            // 左 => キャンセル
            await _updateItemStatus(
              orderId: item.orderId,
              itemIndex: item.itemIndex,
              newStatus: 'canceled',
            );
          }
        } else if (isCanceled) {
          // キャンセル => 未提供
          await _updateItemStatus(
            orderId: item.orderId,
            itemIndex: item.itemIndex,
            newStatus: 'unprovided',
          );
        } else if (isProvided) {
          // 提供済 => 未提供
          await _updateItemStatus(
            orderId: item.orderId,
            itemIndex: item.itemIndex,
            newStatus: 'unprovided',
          );
        }
      },
      background: _buildSwipeBackground(item, isStartToEnd: true),
      secondaryBackground: _buildSwipeBackground(item, isStartToEnd: false),
      child: _OrderCard(itemData: item, tableColor: tableColor),
    );
  }

  Widget _buildSwipeBackground(_ItemData item, {required bool isStartToEnd}) {
    final isUnprovided = item.status == 'unprovided';
    final isCanceled = item.status == 'canceled';
    final isProvided = item.status == 'provided';

    if (isStartToEnd) {
      if (isUnprovided) {
        // 右 => 提供済
        return Container(
          color: Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.check, color: Colors.white),
              SizedBox(width: 8),
              Text("提供済にする",
                  style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      } else if (isCanceled || isProvided) {
        // 右 => 未提供に戻す
        return Container(
          color: Colors.blue,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.undo, color: Colors.white),
              SizedBox(width: 8),
              Text("未提供に戻す",
                  style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }
    } else {
      // 左 => キャンセル or 未提供に戻す
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
              Text("キャンセル",
                  style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              Text("未提供に戻す",
                  style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }
    }
    return const SizedBox.shrink();
  }
}

class _ItemData {
  final String orderId;
  final String tableName;
  final String createdAt; // DBにはUTCとして保存されている想定
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

  const _OrderCard({
    Key? key,
    required this.itemData,
    required this.tableColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final diffMin = _elapsedMinutes(itemData.createdAt);

    Color bgColor = Colors.white;
    if (itemData.status == 'unprovided') {
      if (diffMin >= 40) {
        bgColor = Colors.orange[400]!;
      } else if (diffMin >= 10) {
        bgColor = Colors.orange[100]!;
      }
    }

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
    if (status == 'unprovided') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          '未提供',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      );
    } else if (status == 'provided') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          '提供済',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      );
    } else if (status == 'canceled') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'キャンセル',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      );
    }
    // 想定外
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  bool _isNew(int diffMin) => diffMin < 3;

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
      final dtLocal = dtUtc.toLocal();
      return DateTime.now().difference(dtLocal).inMinutes;
    } catch (e) {
      print('Time parsing error: $e');
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
