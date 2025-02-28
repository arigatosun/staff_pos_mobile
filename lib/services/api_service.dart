// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:staff_pos_app/services/supabase_manager.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  // Next.js 側のベースURL (ローカルテスト用アドレスなど)
  static const String baseUrl = 'https://cf42-2400-4150-78a0-5300-a58e-41a-bed2-a718.ngrok-free.app';

  /// POSログインAPIを呼び出す
  /// 成功時 -> storeId を返す
  /// 失敗時 -> Exception を throw
  static Future<int> loginPos(String posLoginId, String posLoginPassword) async {
    final url = Uri.parse('$baseUrl/api/pos-login/');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'posLoginId': posLoginId,
        'posLoginPassword': posLoginPassword,
      }),
    );

    if (response.statusCode == 200) {
      final jsonBody = jsonDecode(response.body);
      if (jsonBody['success'] == true) {
        // 正常時 -> storeId を取得
        final int storeId = jsonBody['storeId'] as int;

        // ログイン成功時にStoreIDを保存
        SupabaseManager.setLoggedInStoreId(storeId);
        print('ログイン成功: store_id=$storeId をSupabaseManagerに保存しました');

        return storeId;
      } else if (jsonBody['error'] != null) {
        throw Exception(jsonBody['error']);
      } else {
        throw Exception('Unknown error from POS login');
      }
    } else {
      // ステータスコードが 200 以外
      try {
        final jsonBody = jsonDecode(response.body);
        final error = jsonBody['error'] ?? 'Login failed';
        throw Exception(error);
      } catch (e) {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    }
  }

  /// ログアウト処理
  static Future<void> logoutPos() async {
    // SupabaseManagerから店舗IDをクリア
    SupabaseManager.clearLoggedInStoreId();
    print('ログアウト: SupabaseManagerから店舗IDをクリアしました');

    // 必要に応じて他のログアウト処理を追加
    // - セッションクリア
    // - キャッシュクリア
    // - 認証トークンの削除 など
  }

  /// ログイン後にFCMトークンを更新する（完全実装）
  static Future<void> updateFcmTokenWithStoreId(int storeId) async {
    try {
      // FCMトークンを取得
      String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        print('FCMトークン取得失敗: null');
        return;
      }

      print('FCMトークン更新開始: $token、店舗ID: $storeId');

      // Supabaseクライアント取得
      final client = Supabase.instance.client;

      // 既存のトークンを検索
      final existingDevices = await client
          .from('pos_devices')
          .select()
          .eq('fcm_token', token);

      if (existingDevices.isEmpty) {
        // 新規登録
        final result = await client.from('pos_devices').insert({
          'fcm_token': token,
          'device_name': 'Android Device ${DateTime.now().millisecondsSinceEpoch}',
          'store_id': storeId,
          // updated_atカラムの削除
        }).select();
        print('FCMトークンを新規登録: $result');
      } else {
        // 既存のトークンを更新
        final result = await client
            .from('pos_devices')
            .update({
          'store_id': storeId,
          // updated_atカラムの削除
        })
            .eq('fcm_token', token)
            .select();
        print('FCMトークンの店舗IDを更新: $result');
      }

      print('FCMトークン更新完了: $token -> 店舗ID $storeId');
    } catch (e) {
      print('FCMトークン更新エラー: $e');
      if (e is PostgrestException) {
        print('PostgrestException: ${e.message}');
        print('詳細: ${e.details}');
      }
    }
  }

  /// 店舗の設定を取得
  static Future<Map<String, dynamic>> getStoreSettings(int storeId) async {
    final url = Uri.parse('$baseUrl/api/store-settings?storeId=$storeId');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonBody = jsonDecode(response.body);
        if (jsonBody['success'] == true) {
          return jsonBody['data'] as Map<String, dynamic>;
        } else {
          throw Exception(jsonBody['error'] ?? 'Failed to get store settings');
        }
      } else {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('店舗設定取得エラー: $e');
      rethrow;
    }
  }
}