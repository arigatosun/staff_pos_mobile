import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'package:staff_pos_app/pages/home_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:staff_pos_app/services/supabase_manager.dart';

class PosLoginPage extends StatefulWidget {
  const PosLoginPage({super.key});

  @override
  State<PosLoginPage> createState() => _PosLoginPageState();
}

class _PosLoginPageState extends State<PosLoginPage> {
  final _idController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLoading = false;
  String? _errorMsg;
  String? _deviceId;

  @override
  void dispose() {
    _idController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final posLoginId = _idController.text.trim();
      final posLoginPassword = _passController.text.trim();

      // APIを呼んで storeId を取得
      final storeId = await ApiService.loginPos(posLoginId, posLoginPassword);
      print('ログイン成功: storeId=$storeId');

      // 店舗IDをSupabaseManagerに保存
      await SupabaseManager.setLoggedInStoreId(storeId);

      // FCMトークン取得（重複削除は行わない）
      final token = await _getFCMToken();
      if (token == null) {
        setState(() {
          _errorMsg = 'FCMトークンの取得に失敗しました。通知機能が制限される可能性があります。';
        });
        return;
      }

      // デバイス登録・更新（安全な方法で）
      await _registerOrUpdateDevice(token, storeId);

      // ログイン成功後にFCMトークンを強制更新
      await ApiService.updateFcmTokenWithStoreId(storeId);

      // 勤務開始の確認ダイアログを表示
      if (!mounted) return;

      final startWork = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('勤務開始'),
          content: const Text('勤務を開始しますか？\n「はい」を選択すると通知を受信します。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('いいえ'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('はい'),
            ),
          ],
        ),
      ) ?? false;

      if (startWork && _deviceId != null) {
        // 勤務開始処理
        await _setWorkingStatus(storeId, true);
      } else {
        // 勤務開始しない場合も勤務状態をfalseに設定
        await SupabaseManager.setWorkingStatus(false);
      }

      // HomePage へ遷移
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(storeId: storeId),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMsg = e.toString();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // FCMトークンをシンプルに取得するだけ（重複削除はしない）
  Future<String?> _getFCMToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        print('FCMトークンを取得できませんでした');
        return null;
      }
      return token;
    } catch (e) {
      print('FCMトークン取得エラー: $e');
      return null;
    }
  }

  // デバイスを登録または更新（外部キー制約を考慮）
  Future<void> _registerOrUpdateDevice(String token, int storeId) async {
    try {
      // デバイス名を取得
      final deviceName = await _getDeviceName();
      final now = DateTime.now().toIso8601String();

      // 既存のデバイスをトークンで検索
      final existingDevicesByToken = await supabase
          .from('pos_devices')
          .select('id, store_id')
          .eq('fcm_token', token)
          .limit(1);

      if (existingDevicesByToken.isNotEmpty) {
        // トークンが一致するデバイスが存在する場合は、そのデバイスIDを使用
        _deviceId = existingDevicesByToken[0]['id'];
        print('既存デバイスを使用: $_deviceId (トークン一致)');

        // 店舗IDとデバイス名のみ更新
        await supabase
            .from('pos_devices')
            .update({
          'device_name': deviceName,
          'store_id': storeId,
          'updated_at': now,
        })
            .eq('id', _deviceId!);

        print('既存デバイス更新完了: $_deviceId');

        // デバイスIDを保存
        if (_deviceId != null) {
          await SupabaseManager.saveDeviceId(_deviceId!);
        }

        return;
      }

      // トークンでデバイスが見つからなかった場合、新規登録を試みる
      try {
        final result = await supabase
            .from('pos_devices')
            .insert({
          'device_name': deviceName,
          'fcm_token': token,
          'store_id': storeId,
          'created_at': now,
          'updated_at': now,
        })
            .select()
            .single();

        _deviceId = result['id'];
        print('新規デバイス登録成功: $_deviceId');

        // デバイスIDを保存
        if (_deviceId != null) {
          await SupabaseManager.saveDeviceId(_deviceId!);
        }
      } catch (insertError) {
        print('新規デバイス登録エラー: $insertError');

        // 外部キー制約エラーなど、何らかの理由で登録に失敗した場合
        // このデバイスが staff_work_status テーブルから参照されている可能性がある
        // 既存の work_status を検索し、関連するデバイスを再利用

        if (insertError.toString().contains('foreign key constraint')) {
          print('外部キー制約エラー: 既存の関連デバイスを検索します');

          // 既存の勤務状態レコードを探す
          final workStatusRecords = await supabase
              .from('staff_work_status')
              .select('device_id')
              .eq('store_id', storeId)
              .order('updated_at', ascending: false)
              .limit(3);

          if (workStatusRecords.isNotEmpty) {
            // 関連するデバイスIDを取得
            final deviceIds = workStatusRecords
                .map((record) => record['device_id'] as String)
                .toList();

            // これらのデバイスIDのうち最も新しいものを使用
            for (final deviceId in deviceIds) {
              try {
                await supabase
                    .from('pos_devices')
                    .update({
                  'device_name': deviceName,
                  'fcm_token': token,
                  'store_id': storeId,
                  'updated_at': now,
                })
                    .eq('id', deviceId);

                _deviceId = deviceId;
                print('既存の勤務状態に関連するデバイスを再利用: $_deviceId');

                // デバイスIDを保存
                await SupabaseManager.saveDeviceId(_deviceId!);

                break;
              } catch (updateError) {
                print('デバイス更新エラー ($deviceId): $updateError');
                continue;
              }
            }
          }
        }
      }
    } catch (e) {
      print('デバイス登録/更新処理エラー: $e');
      // _deviceIdがnullのままの場合、後続の処理でエラーに注意
    }
  }

  // 簡易的なデバイス名取得
  Future<String> _getDeviceName() async {
    try {
      return 'POS Device ${DateTime.now().millisecondsSinceEpoch % 10000}';
    } catch (e) {
      return 'Unknown Device';
    }
  }

  // 勤務状態を設定する処理
  Future<void> _setWorkingStatus(int storeId, bool isWorking) async {
    if (_deviceId == null) {
      print('デバイスIDが不明なため勤務状態を設定できません');
      return;
    }

    try {
      final now = DateTime.now().toIso8601String();

      // 既存の勤務状態レコードを確認
      final existingStatus = await supabase
          .from('staff_work_status')
          .select('id')
          .eq('device_id', _deviceId!)
          .eq('store_id', storeId)
          .order('updated_at', ascending: false)
          .limit(1);

      if (existingStatus.isNotEmpty) {
        // 既存レコードがある場合は更新
        final statusId = existingStatus[0]['id'];

        await supabase
            .from('staff_work_status')
            .update({
          'is_working': isWorking,
          'work_started_at': isWorking ? now : null,
          'work_ended_at': isWorking ? null : now,
          'updated_at': now,
        })
            .eq('id', statusId);

        print('既存の勤務状態を更新: $statusId -> $isWorking');
      } else {
        // 新規レコードを作成
        final result = await supabase
            .from('staff_work_status')
            .insert({
          'device_id': _deviceId!,
          'store_id': storeId,
          'is_working': isWorking,
          'work_started_at': isWorking ? now : null,
          'work_ended_at': isWorking ? null : now,
          'created_at': now,
          'updated_at': now,
        })
            .select();

        print('新規勤務状態を作成: ${result.isNotEmpty ? result[0]['id'] : 'Unknown'} -> $isWorking');
      }

      // ローカルの勤務状態も更新
      await SupabaseManager.setWorkingStatus(isWorking);

      // デバイスIDを保存
      await SupabaseManager.saveDeviceId(_deviceId!);

      // スナックバーでユーザーに通知
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isWorking ? '勤務を開始しました。通知を受信します。' : '勤務は開始していません。通知は受信しません。'),
            backgroundColor: isWorking ? Colors.green : Colors.grey,
          ),
        );
      }
    } catch (e) {
      print('勤務状態の設定エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('勤務状態の設定に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POSログイン'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _idController,
              decoration: const InputDecoration(
                labelText: 'POSログインID',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passController,
              decoration: const InputDecoration(
                labelText: 'POSログインパスワード',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_errorMsg != null)
              Text(
                _errorMsg!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('ログイン'),
            ),
          ],
        ),
      ),
    );
  }
}