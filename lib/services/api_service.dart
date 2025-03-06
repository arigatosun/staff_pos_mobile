// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:staff_pos_app/services/supabase_manager.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  // Supabaseクライアント取得
  static SupabaseClient get supabase => Supabase.instance.client;

  /// POSログインAPIを呼び出す
  /// 成功時 -> storeId を返す
  /// 失敗時 -> Exception を throw
  static Future<int> loginPos(String posLoginId, String posLoginPassword) async {
    try {
      // 入力検証
      if (posLoginId.isEmpty || posLoginPassword.isEmpty) {
        throw Exception('ログインIDとパスワードを入力してください');
      }

      // posLoginSettingsテーブルからログインIDで検索
      final response = await supabase
          .from('pos_login_settings')
          .select()
          .eq('posloginid', posLoginId)  // 小文字に修正
          .maybeSingle();

      // レコードが存在しない場合
      if (response == null) {
        throw Exception('無効なログインIDです');
      }

      // パスワード検証
      if (response['posloginpassword'] != posLoginPassword) {  // 小文字に修正
        throw Exception('パスワードが一致しません');
      }

      // 認証成功、storeIdを取得
      final int storeId = response['storeId'];  // 引用符付きだがJSONとして取得する場合は引用符なしでOK

      // ログイン成功時にStoreIDを保存
      await SupabaseManager.setLoggedInStoreId(storeId);
      print('ログイン成功: store_id=$storeId をSupabaseManagerに保存しました');

      return storeId;
    } catch (e) {
      // SupabaseのPostgrestExceptionの場合は詳細なエラー情報を出力
      if (e is PostgrestException) {
        print('Supabaseエラー: ${e.message}');
        print('詳細: ${e.details}');
        throw Exception('データベース接続エラー: ${e.message}');
      }

      // その他の例外をそのまま投げる
      rethrow;
    }
  }

  /// ログアウト処理
  static Future<void> logoutPos() async {
    // SupabaseManagerから店舗IDをクリア
    await SupabaseManager.clearLoggedInStoreId();
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

      // 既存のトークンを検索
      final existingDevices = await supabase
          .from('pos_devices')
          .select()
          .eq('fcm_token', token);

      if (existingDevices.isEmpty) {
        // 新規登録
        final result = await supabase.from('pos_devices').insert({
          'fcm_token': token,
          'device_name': 'Android Device ${DateTime.now().millisecondsSinceEpoch}',
          'store_id': storeId,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).select();
        print('FCMトークンを新規登録: $result');
      } else {
        // 既存のトークンを更新
        final result = await supabase
            .from('pos_devices')
            .update({
          'store_id': storeId,
          'updated_at': DateTime.now().toIso8601String(),
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
    try {
      final response = await supabase
          .from('store_settings')
          .select()
          .eq('storeId', storeId)
          .maybeSingle();

      if (response == null) {
        throw Exception('店舗設定が見つかりません');
      }

      return response as Map<String, dynamic>;
    } catch (e) {
      print('店舗設定取得エラー: $e');
      if (e is PostgrestException) {
        print('PostgrestException: ${e.message}');
        print('詳細: ${e.details}');
      }
      rethrow;
    }
  }
}