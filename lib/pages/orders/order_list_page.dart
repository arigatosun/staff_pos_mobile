import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';

// ★ v2 系の Supabase 型定義
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase_manager.dart';

/// ---------------------------------------------------------
/// TableColorManager (リアルタイム更新に対応するよう修正)
/// ---------------------------------------------------------
class TableColorManager {
  static final Map<String, String> _tableColorMap = {}; // table_name -> hex_color
  static const defaultHex = '#FF9E9E9E';

  /// Supabaseから受け取った最新のrows(List<Map>)をもとにローカルマップを更新
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

  /// テーブル名からカラーを取得
  static Color getTableColor(String tableName) {
    final hex = _tableColorMap[tableName] ?? defaultHex;
    return _parseColor(hex) ?? Colors.grey;
  }

  /// Hex (#AARRGGBB) → Color 変換
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

  // ---------------------- 遅延表示用の設定値 ----------------------
  bool _isDelayOn = false; // 遅延表示を有効にするか
  int _threshold1 = 10;    // しきい値1
  int _threshold2 = 40;    // しきい値2
  int _threshold3 = 60;    // しきい値3

  // ---------------------- 追加: table_colors & store_settings 購読用 ----------------------
  StreamSubscription<List<Map<String, dynamic>>>? _tableColorStreamSub;
  StreamSubscription<List<Map<String, dynamic>>>? _storeSettingsStreamSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);

    _initializeNotifications();
    _initializeDeviceInfo();
    _setupFCM();
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateFCMToken);

    // ordersをリアルタイム購読
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    // ---------------------- table_colors を購読してリアルタイム反映 ----------------------
    _tableColorStreamSub = supabase
        .from('table_colors')
        .stream(primaryKey: ['id'])
        .listen((rows) {
      // 取得したテーブルカラー情報を更新
      TableColorManager.updateTableColors(rows);
      // UI再描画
      if (mounted) setState(() {});
    });

    // ---------------------- store_settings を購読してリアルタイム反映 ----------------------
    _storeSettingsStreamSub = supabase
        .from('store_settings')
        .stream(primaryKey: ['id'])
        .listen((rows) {
      // store_settings は基本1行の想定として、先頭行を参照
      if (rows.isNotEmpty) {
        final row = rows.first;
        _parseStoreSettingsRow(row);
        if (mounted) setState(() {});
      }
    });

    // 1分おきに再描画（経過時間のハイライトを更新するため）
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    // 初回起動時に「現在のstore_settings」を取得（DBが空の場合などもあるため）
    _fetchStoreSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timer?.cancel();
    _audioPlayer.dispose();

    // Stream購読を解除
    _tableColorStreamSub?.cancel();
    _storeSettingsStreamSub?.cancel();

    super.dispose();
  }

  //----------------------------------------------------------------------------
  // store_settings の「遅延表示 ON/OFF」「threshold1/2/3」を取得
  //----------------------------------------------------------------------------
  Future<void> _fetchStoreSettings() async {
    try {
      final PostgrestMap? data = await supabase
          .from('store_settings')
          .select()
          .eq('id', '00000000-0000-0000-0000-000000000001')
          .maybeSingle();

      if (data != null) {
        _parseStoreSettingsRow(data);
        setState(() {});
      }
    } on PostgrestException catch (e) {
      debugPrint('_fetchStoreSettings PostgrestException: ${e.message}');
    } catch (e) {
      debugPrint('_fetchStoreSettings error: $e');
    }
  }

  /// store_settingsの行オブジェクトから遅延関連の値をセットする
  void _parseStoreSettingsRow(Map<String, dynamic> data) {
    // 遅延フラグ
    final rawDelayOn = data['is_delay_highlight_on'];
    if (rawDelayOn is bool) {
      _isDelayOn = rawDelayOn;
    } else if (rawDelayOn is String) {
      _isDelayOn = (rawDelayOn.toLowerCase() == 'true');
    }

    // threshold1
    final rawT1 = data['delay_threshold1'];
    if (rawT1 is int) {
      _threshold1 = rawT1;
    } else if (rawT1 is double) {
      _threshold1 = rawT1.toInt();
    } else if (rawT1 is String) {
      final parsed = int.tryParse(rawT1);
      if (parsed != null) _threshold1 = parsed;
    }

    // threshold2
    final rawT2 = data['delay_threshold2'];
    if (rawT2 is int) {
      _threshold2 = rawT2;
    } else if (rawT2 is double) {
      _threshold2 = rawT2.toInt();
    } else if (rawT2 is String) {
      final parsed = int.tryParse(rawT2);
      if (parsed != null) _threshold2 = parsed;
    }

    // threshold3
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
        '[store_settings loaded] isDelayOn=$_isDelayOn '
            't1=$_threshold1, t2=$_threshold2, t3=$_threshold3'
    );
  }

  //----------------------------------------------------------------------------
  // 遅延しきい値に応じた色を返す
  //----------------------------------------------------------------------------
  Color _calcDelayHighlightColor(String status, int diffMin) {
    // 遅延表示OFF or 「未提供」以外なら白背景で統一
    if (!_isDelayOn || status != 'unprovided') {
      return Colors.white;
    }
    if (diffMin >= _threshold3) {
      // 3段階目
      return Colors.orange[600]!;
    } else if (diffMin >= _threshold2) {
      // 2段階目
      return Colors.orange[400]!;
    } else if (diffMin >= _threshold1) {
      // 1段階目
      return Colors.orange[100]!;
    }
    // まだしきい値に達していない
    return Colors.white;
  }

  // ---------------------- 通知周りなど従来ロジックは基本そのまま ----------------------
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
        _handleNotificationTap(details);
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

  void _handleNotificationTap(NotificationResponse details) {
    try {
      final payload = details.payload;
      if (payload != null) {
        final data = json.decode(payload);
        print('Notification tapped with payload: $data');
      }
    } catch (e) {
      print('Error handling notification tap: $e');
    }
  }

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

  Future<void> _updateFCMToken(String token) async {
    if (_currentFCMToken == token) return;
    try {
      if (_currentDeviceId.isEmpty) {
        final resp = await supabase.from('pos_devices').insert({
          'device_name': _deviceName ?? 'POS Device',
          'fcm_token': token,
        }).select().single();
        _currentDeviceId = resp['id'].toString();
      } else {
        await supabase.from('pos_devices').update({
          'device_name': _deviceName ?? 'POS Device',
          'fcm_token': token,
        }).eq('id', _currentDeviceId);
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

  void _showNotificationDialog(RemoteMessage message) async {
    if (!mounted) return;
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
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('notification_sound.mp3'));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

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
    final diff = _elapsedMinutes(item.createdAt);
    return diff;
  }

  void _sortItems(List<_ItemData> items) {
    items.sort((a, b) {
      // 遅延大きい順
      final delayA = _calcDelayMinutes(a);
      final delayB = _calcDelayMinutes(b);
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
                  activeTrackColor: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.grey[400],
                  // 以下の2行を追加
                  overlayColor: MaterialStateProperty.all(Colors.transparent),
                  trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
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
                  final diffMin = _elapsedMinutes(item.createdAt);

                  // テーブルの色をリアルタイムで取得
                  final tableColor =
                  TableColorManager.getTableColor(item.tableName);

                  // しきい値に応じた遅延ハイライト色
                  final bgColor = _calcDelayHighlightColor(item.status, diffMin);

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
    final isUnprovided = item.status == 'unprovided';
    final isCanceled = item.status == 'canceled';
    final isProvided = item.status == 'provided';

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

///
/// _OrderCard: 受け取った色情報をただ反映するだけ
///
class _OrderCard extends StatelessWidget {
  final _ItemData itemData;
  final Color tableColor;
  final Color bgColor;

  const _OrderCard({
    Key? key,
    required this.itemData,
    required this.tableColor,
    required this.bgColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final diffMin = _elapsedMinutes(itemData.createdAt);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        // 左側の太い色付きボーダーをテーブルカラーに
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
