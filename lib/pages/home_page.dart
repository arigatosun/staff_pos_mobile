import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:staff_pos_app/pages/orders/order_list_page.dart';
import 'package:staff_pos_app/pages/tables/table_list_page.dart';
import 'package:staff_pos_app/pages/history/payment_history_page.dart';
import 'package:staff_pos_app/pages/settings/settings_page.dart';
import 'package:staff_pos_app/services/supabase_manager.dart';

class HomePage extends StatefulWidget {
  final int storeId; // 受け取り用
  const HomePage({super.key, required this.storeId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _isWorking = false;
  bool _isLoading = false;
  String? _workStatusId;
  String? _deviceId;

  // 後から初期化するため late
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // ライフサイクル監視を追加
    WidgetsBinding.instance.addObserver(this);

    // 子ページに storeId を渡す
    _pages = [
      OrderListPage(storeId: widget.storeId),
      TableListPage(storeId: widget.storeId),
      PaymentHistoryPage(storeId: widget.storeId),
      SettingsPage(storeId: widget.storeId),
    ];

    // 店舗IDをSupabaseManagerに保存
    SupabaseManager.setLoggedInStoreId(widget.storeId);

    // FCMトークン登録と勤務状態を取得
    _initFCMAndWorkStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached || state == AppLifecycleState.paused) {
      // アプリがバックグラウンドに行った場合、長時間勤務の自動終了をチェック
      _checkAndUpdateWorkStatus();
    } else if (state == AppLifecycleState.resumed) {
      // アプリが再開されたときに勤務状態を再取得
      _loadWorkStatus();
    }
  }

  // FCMトークン登録と勤務状態の初期化
  Future<void> _initFCMAndWorkStatus() async {
    try {
      setState(() => _isLoading = true);

      // FCMトークンを取得
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        print('FCMトークンが取得できませんでした');
        return;
      }

      // トークン重複チェックとデバイスの登録/更新
      await _registerOrUpdateDeviceToken(token);

      // 勤務状態をロード
      await _loadWorkStatus();

    } catch (e) {
      print('初期化エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // FCMトークンを登録または更新する
  Future<void> _registerOrUpdateDeviceToken(String token) async {
    try {
      // 同じトークンを持つデバイスを検索
      final devices = await supabase
          .from('pos_devices')
          .select('id, updated_at')
          .eq('fcm_token', token)
          .order('updated_at', ascending: false);

      if (devices.isEmpty) {
        // 新規デバイス登録
        final result = await supabase
            .from('pos_devices')
            .insert({
          'device_name': 'Mobile Device',
          'fcm_token': token,
          'store_id': widget.storeId,
          'updated_at': DateTime.now().toIso8601String(),
        })
            .select('id')
            .single();

        _deviceId = result['id'];
        print('新規デバイス登録: $_deviceId');

        // デバイスIDを保存
        if (_deviceId != null) {
          await SupabaseManager.saveDeviceId(_deviceId!);
        }
      } else {
        // 既存デバイスを更新
        _deviceId = devices[0]['id'];

        // _deviceIdがnullでないことを確認
        if (_deviceId != null) {
          // 最新のレコードを更新
          await supabase
              .from('pos_devices')
              .update({
            'store_id': widget.storeId,
            'updated_at': DateTime.now().toIso8601String(),
          })
              .eq('id', _deviceId!);  // <- ここに非null断言演算子(!)を追加

          print('既存デバイス更新: $_deviceId');

          // デバイスIDを保存
          await SupabaseManager.saveDeviceId(_deviceId!);
        }

        // 重複があれば削除（念のため）
        if (devices.length > 1) {
          final toDelete = devices.sublist(1).map((d) => d['id'] as String).toList();

          // in_の代わりにfilterを使用
          for (final id in toDelete) {
            await supabase
                .from('pos_devices')
                .delete()
                .eq('id', id);
          }

          print('重複デバイス削除: ${toDelete.length}件');
        }
      }
    } catch (e) {
      print('デバイス登録/更新エラー: $e');
      // エラーをスローせず、次の処理に進む
    }
  }

  Future<void> _checkAndUpdateWorkStatus() async {
    if (!_isWorking || _workStatusId == null) return;

    try {
      // Nullチェック後に安全に使用
      final statusId = _workStatusId!;

      // 最後の勤務開始時間を取得
      final response = await supabase
          .from('staff_work_status')
          .select('work_started_at')
          .eq('id', statusId)
          .limit(1);  // 複数行返ってきても1つだけ処理

      if (response.isNotEmpty && response[0]['work_started_at'] != null) {
        final startedAt = DateTime.parse(response[0]['work_started_at']);
        final now = DateTime.now();

        // 8時間以上経過していれば自動終了
        if (now.difference(startedAt).inHours >= 8) {
          await supabase
              .from('staff_work_status')
              .update({
            'is_working': false,
            'work_ended_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          })
              .eq('id', statusId);

          // 状態を更新（UI更新用）
          if (mounted) {
            setState(() => _isWorking = false);
          }

          // ローカルの勤務状態も更新
          await SupabaseManager.setWorkingStatus(false);

          print('8時間経過: 勤務状態を自動終了しました');
        }
      }
    } catch (e) {
      print('勤務状態確認エラー: $e');
    }
  }

  Future<void> _loadWorkStatus() async {
    if (_deviceId == null) {
      print('デバイスIDが設定されていないため勤務状態を取得できません');
      return;
    }

    try {
      setState(() => _isLoading = true);

      // デバイスIDに関連付けられた勤務状態を取得
      final statusResponse = await supabase
          .from('staff_work_status')
          .select('*')
          .eq('device_id', _deviceId!) // ここで非null断言を使用
          .eq('store_id', widget.storeId)
          .order('updated_at', ascending: false)
          .limit(1);  // 最新のステータスのみ取得

      if (statusResponse.isNotEmpty) {
        final latestStatus = statusResponse[0];
        final bool isWorking = latestStatus['is_working'] ?? false;

        setState(() {
          _workStatusId = latestStatus['id'];
          _isWorking = isWorking;
        });

        // ローカルの勤務状態も更新
        await SupabaseManager.setWorkingStatus(isWorking);

        print('勤務状態を取得: ${_isWorking ? "勤務中" : "休憩中"}');
      } else {
        // 勤務状態が未設定の場合は初期状態を作成（オプション）
        print('勤務状態が見つかりません。初期状態では休憩中です。');
        setState(() {
          _isWorking = false;
          _workStatusId = null;
        });

        // ローカルの勤務状態も更新
        await SupabaseManager.setWorkingStatus(false);
      }
    } catch (e) {
      print('勤務状態の読み込みエラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleWorkStatus() async {
    if (_deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('デバイス情報が取得できないため、勤務状態を変更できません。'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);

      // 状態を反転
      final newStatus = !_isWorking;
      final now = DateTime.now().toIso8601String();

      // 既存の勤務状態レコードがあればそれを更新、なければ新規作成
      if (_workStatusId != null) {
        // nullでないことが確認できたので安全に使用
        final statusId = _workStatusId!;

        await supabase
            .from('staff_work_status')
            .update({
          'is_working': newStatus,
          'work_started_at': newStatus ? now : null,
          'work_ended_at': !newStatus ? now : null,
          'updated_at': now,
        })
            .eq('id', statusId);

        print('勤務状態を更新: ${newStatus ? "勤務開始" : "勤務終了"}');
      } else {
        // 新規勤務状態レコードを作成
        final deviceId = _deviceId!; // 非null断言

        final result = await supabase
            .from('staff_work_status')
            .insert({
          'device_id': deviceId,
          'store_id': widget.storeId,
          'is_working': newStatus,
          'work_started_at': newStatus ? now : null,
          'work_ended_at': !newStatus ? now : null,
          'created_at': now,
          'updated_at': now,
        })
            .select();

        if (result.isNotEmpty) {
          setState(() => _workStatusId = result[0]['id']);
          print('新規勤務状態を作成: ${newStatus ? "勤務開始" : "勤務終了"}');
        }
      }

      // ローカルの勤務状態も同時に更新
      await SupabaseManager.setWorkingStatus(newStatus);

      setState(() => _isWorking = newStatus);

      // 勤務状態の変更を通知
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus ? '勤務を開始しました。通知を受信します。' : '勤務を終了しました。通知は受信しません。'),
          backgroundColor: newStatus ? Colors.green : Colors.grey,
        ),
      );
    } catch (e) {
      print('勤務状態の更新エラー: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('勤務状態の更新に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 勤務状態バーを追加
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56.0),
        child: Container(
          color: _isWorking ? Colors.green[100] : Colors.red[100],
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: SafeArea(
            child: Row(
              children: [
                Icon(
                  _isWorking ? Icons.check_circle : Icons.not_interested,
                  color: _isWorking ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _isWorking ? '勤務中' : '休憩中',
                  style: TextStyle(
                    color: _isWorking ? Colors.green[800] : Colors.red[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _isLoading
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : ElevatedButton(
                  onPressed: _toggleWorkStatus,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isWorking ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: Text(_isWorking ? '勤務終了' : '勤務開始'),
                ),
              ],
            ),
          ),
        ),
      ),
      // 既存同様、メインコンテンツは画面を切り替える
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.teal,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: '注文管理',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.table_bar),
            label: 'テーブル管理',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: '会計履歴',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}