import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../../services/supabase_manager.dart';

/// タブ: [未提供, 提供済, キャンセル]
/// ・archived非表示
/// ・未提供だけスワイプ(右→提供済, 左→キャンセル)
/// ・ソート: delayed(未提供遅延大が上), newest(新しい順)
/// ・タブの選択色は背景なし＋濃いグレー文字、周りにシャドウ。非選択は薄いグレー
/// ・切り替えスイッチON時は緑
/// ・新着表示: 商品名の右に黄色●+「新着!」、その右に時間
/// ・遅延してない未提供はステータスバッジがグレー、10分以上なら赤
class OrderListPage extends StatefulWidget {
  const OrderListPage({Key? key}) : super(key: key);

  @override
  State<OrderListPage> createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage>
    with SingleTickerProviderStateMixin {
  // ----- FCM関連 -----
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  String? _currentFCMToken;
  String _currentDeviceId = '';
  String? _deviceName;
  bool _isSoundOn = true; // 通知音 ON/OFF

  // ----- Supabaseストリーム -----
  late final Stream<List<Map<String, dynamic>>> _ordersStream;

  // ----- タブ (3つ) -----
  late TabController _tabController;
  final List<String> _tabs = [
    '未提供',
    '提供済',
    'キャンセル',
  ];

  // ----- ソート方法 -----
  // delayed -> 未提供(遅延大)が上, 提供済/キャンセルは下
  // newest -> createdAt desc
  String _sortMethod = 'delayed';

  // テーブル→色キャッシュ
  final Map<String, Color> _tableColorMap = {};

  Timer? _timer; // 1分おきに再描画

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);

    _initializeDeviceInfo();
    _setupFCM();
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateFCMToken);

    // Supabase リアルタイム
    _ordersStream = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    // 1分おきに再描画
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
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

  // ---------------- FCMセットアップ ----------------

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
        alert: true, badge: true, sound: true,
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

  void _showNotificationDialog(RemoteMessage message) {
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
    if (_isSoundOn) {
      _audioPlayer.play(AssetSource('notification_sound.mp3')).catchError((e) {
        print('Error playing sound: $e');
      });
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

      final updated = await supabase
          .from('orders')
          .update({'items': items})
          .eq('id', orderId)
          .select()
          .maybeSingle();
      if (updated == null) {
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

  // ---------------- リスト生成・ソート・フィルタ ----------------

  /// ordersを商品単位にフラット化; archivedは非表示
  List<_ItemData> _flattenOrders(List<Map<String, dynamic>> orders) {
    final result = <_ItemData>[];
    for (final o in orders) {
      // デバッグ用にログ出力
      print('Order data:');
      print('  ID: ${o['id']}');
      print('  Created at: ${o['created_at']}');
      print('  Current time: ${DateTime.now().toIso8601String()}');

      final orderId = o['id'] as String? ?? '';
      final tableName = o['table_name'] as String? ?? '不明テーブル';
      final createdAt = o['created_at'] as String? ?? '';
      final items = o['items'] as List<dynamic>? ?? [];

      for (int i = 0; i < items.length; i++) {
        final it = items[i] as Map<String, dynamic>;
        final name = it['name'] as String? ?? '';
        final qty = it['quantity'] as int? ?? 0;
        final status = it['status'] as String? ?? 'unprovided';

        if (status == 'archived') continue; // archived除外

        result.add(
          _ItemData(
            orderId: orderId,
            tableName: tableName,
            createdAt: createdAt,
            itemIndex: i,
            itemName: name,
            quantity: qty,
            status: status,
          ),
        );
      }
    }
    return result;
  }

  /// ソート
  /// delayed: 未提供 -> 遅延(2..0)が上, 提供済/キャンセルは -1
  /// newest: createdAt desc
  void _sortItems(List<_ItemData> items) {
    if (_sortMethod == 'delayed') {
      items.sort((a, b) {
        final rankA = _calcDelayRank(a);
        final rankB = _calcDelayRank(b);
        final diffRank = rankB.compareTo(rankA);
        if (diffRank != 0) return diffRank;
        // rank同じ -> createdAt desc
        return b.createdAt.compareTo(a.createdAt);
      });
    } else {
      // newest
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
  }

  int _calcDelayRank(_ItemData item) {
    if (item.status == 'unprovided') {
      final diff = _elapsedMinutes(item.createdAt);
      if (diff >= 20) return 2;
      if (diff >= 10) return 1;
      return 0;
    }
    // 提供済 or キャンセル
    return -1;
  }

  int _elapsedMinutes(String? createdAt) {
    if (createdAt == null) return 0;
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      return DateTime.now().difference(dt).inMinutes;
    } catch (_) {
      return 0;
    }
  }

  /// タブごとのフィルタ [未提供, 提供済, キャンセル]
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

  /// テーブルごとに色を一度だけ決定して使い回す
  Color _getTableColor(String tableName) {
    // すでにテーブル名がマップにあればそれを返す
    if (_tableColorMap.containsKey(tableName)) {
      return _tableColorMap[tableName]!;
    }
    // なければ初回生成して保存
    final rng = Random(tableName.hashCode);
    final hue = rng.nextDouble() * 360;
    final color = HSVColor.fromAHSV(1, hue, 0.5, 0.9).toColor();
    _tableColorMap[tableName] = color;
    return color;
  }

  void _toggleSortMethod() {
    setState(() {
      _sortMethod = (_sortMethod == 'delayed') ? 'newest' : 'delayed';
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
          // 通知音スイッチ + ソート
          Row(
            children: [
              const Icon(Icons.volume_up, size: 18),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _isSoundOn,
                  onChanged: (val) => setState(() => _isSoundOn = val),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  // Material Designの標準的なスイッチカラー
                  activeColor: Theme.of(context).colorScheme.primary,      // スイッチのつまみの色
                  activeTrackColor: Theme.of(context).colorScheme.primary.withOpacity(0.5),  // ONトラック色
                  inactiveThumbColor: Colors.grey[50],    // OFFつまみ色
                  inactiveTrackColor: Colors.grey[400],   // OFFトラック色
                ),
              ),
              IconButton(
                onPressed: _toggleSortMethod,
                icon: const Icon(Icons.swap_vert),
                tooltip: (_sortMethod == 'delayed')
                    ? '並び替え: 遅延順'
                    : '並び替え: 新着順',
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold
          ),
          // テキストカラーを変更
          labelColor: Colors.white,        // 選択中のタブの文字色を白に
          unselectedLabelColor: Colors.white.withOpacity(0.7),   // 非選択のタブの文字色を半透明の白に
          // インジケーター（下線）のスタイルを変更
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(
              width: 2,
              color: Colors.white,  // 下線の色を白に
            ),
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

          // 各タブの内容
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
                  return _buildDismissible(item);
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }

  /// 未提供のみスワイプ
  Widget _buildDismissible(_ItemData item) {
    final keyVal = ValueKey('${item.orderId}_${item.itemIndex}_${item.status}');
    final isUnprovided = (item.status == 'unprovided');

    final direction = isUnprovided ? DismissDirection.horizontal : DismissDirection.none;

    return Dismissible(
      key: keyVal,
      direction: direction,
      confirmDismiss: (dir) async {
        if (isUnprovided && dir == DismissDirection.endToStart) {
          // キャンセル確認
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
        return true;
      },
      onDismissed: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          // 右=>提供済
          await _updateItemStatus(
            orderId: item.orderId,
            itemIndex: item.itemIndex,
            newStatus: 'provided',
          );
        } else {
          // 左=>キャンセル
          await _updateItemStatus(
            orderId: item.orderId,
            itemIndex: item.itemIndex,
            newStatus: 'canceled',
          );
        }
      },
      background: Container(
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
      ),
      secondaryBackground: Container(
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
      ),
      child: _OrderCard(
        itemData: item,
        tableColor: _getTableColor(item.tableName),
      ),
    );
  }
}

// ----- モデル

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

// ----- カードUI

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

    // 未提供のみ遅延背景
    Color bgColor = Colors.white;
    if (itemData.status == 'unprovided') {
      if (diffMin >= 20) {
        bgColor = Colors.orange[300]!;
      } else if (diffMin >= 10) {
        bgColor = Colors.orange[100]!;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        // 左端の太い色付きボーダーを「テーブルごとの固定色」で表示
        border: Border(left: BorderSide(width: 6, color: tableColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1行目: テーブル名(左) + ステータス(右)
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
              _buildStatusBadge(itemData.status, diffMin),
            ],
          ),
          const SizedBox(height: 6),
          // 2行目: 商品名(左) + (新着 + 時間)(右)
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
                    // 黄色の● + 新着! の表示
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
                  // 時間
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

  Widget _buildStatusBadge(String status, int diffMin) {
    if (status == 'unprovided') {
      // 遅延(10分以上) -> 赤, それ未満 -> グレー
      final isDelayed = diffMin >= 10;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDelayed ? Colors.redAccent : Colors.grey,
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

  int _elapsedMinutes(String? createdAtStr) {
    if (createdAtStr == null) return 0;
    try {
      // created_atをUTCとして解析
      final utcDt = DateTime.parse(createdAtStr);

      // 現在時刻をUTCで取得
      final nowUtc = DateTime.now().toUtc();

      // UTC同士で差分を計算
      return nowUtc.difference(utcDt).inMinutes;
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
