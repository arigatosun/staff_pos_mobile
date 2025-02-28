import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:staff_pos_app/pages/orders/order_list_page.dart';
import 'package:staff_pos_app/pages/tables/table_list_page.dart';
import 'package:staff_pos_app/pages/history/payment_history_page.dart';
import 'package:staff_pos_app/pages/settings/settings_page.dart';
import 'package:staff_pos_app/services/supabase_manager.dart';

class HomePage extends StatefulWidget {
  final int storeId;
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
  late final List<Widget> _pageWidgets;
  late final List<String> _pageTitles;

  @override
  void initState() {
    super.initState();
    // ライフサイクル監視を追加
    WidgetsBinding.instance.addObserver(this);

    // ページタイトル
    _pageTitles = [
      '注文管理',
      'テーブル管理',
      '会計履歴',
      '設定',
    ];

    // 子ページに storeId を渡す
    _pageWidgets = [
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
              .eq('id', _deviceId!);

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
          .limit(1);

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
          .eq('device_id', _deviceId!)
          .eq('store_id', widget.storeId)
          .order('updated_at', ascending: false)
          .limit(1);

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
      _showSnackBar(
        message: 'デバイス情報が取得できないため、勤務状態を変更できません。',
        isError: true,
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
      _showSnackBar(
        message: newStatus ? '勤務を開始しました。通知を受信します。' : '勤務を終了しました。通知は受信しません。',
        isSuccess: newStatus,
      );
    } catch (e) {
      print('勤務状態の更新エラー: $e');
      _showSnackBar(
        message: '勤務状態の更新に失敗しました: $e',
        isError: true,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // モダンなスナックバーを表示する関数
  void _showSnackBar({
    required String message,
    bool isSuccess = false,
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline :
              isSuccess ? Icons.check_circle : Icons.info_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(12),
        backgroundColor: isError ? Colors.red.shade700 :
        isSuccess ? Colors.green.shade700 : Colors.grey.shade700,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '閉じる',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  // 不要なステータスインジケーターは削除

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(0), // 高さを0にしてAppBarを非表示に
        child: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
        ),
      ),
      // ページコンテンツの上に勤務状態コントロールを追加
      body: Column(
        children: [
          // 勤務状態コントロールエリア（モダンなUI）
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isWorking ? Colors.green.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isWorking ? Colors.green.shade300 : Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _isWorking ? Colors.green.shade100 : Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isWorking ? Icons.work_outline : Icons.work_off_outlined,
                            color: _isWorking ? Colors.green.shade800 : Colors.grey.shade700,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isWorking ? '現在勤務中です' : '現在休憩中です',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _isLoading
                            ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : ElevatedButton(
                          onPressed: _toggleWorkStatus,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isWorking ? Colors.red.shade600 : Colors.green.shade600,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isWorking ? Icons.pause : Icons.play_arrow,
                                size: 16,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                _isWorking ? '勤務終了' : '勤務開始',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // メインコンテンツ
          Expanded(
            child: _pageWidgets[_selectedIndex],
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        showUnselectedLabels: true,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            activeIcon: Icon(Icons.list_alt),
            label: '注文管理',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.table_bar),
            activeIcon: Icon(Icons.table_bar),
            label: 'テーブル管理',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            activeIcon: Icon(Icons.receipt_long),
            label: '会計履歴',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            activeIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}