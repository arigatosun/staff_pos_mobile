import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseManager {
  static final SupabaseManager _instance = SupabaseManager._internal();
  static bool _initialized = false;

  // クライアントをstaticで保持
  static late final SupabaseClient _client;

  factory SupabaseManager() {
    return _instance;
  }

  SupabaseManager._internal();

  // 初期化メソッドを改善
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      print('Supabase初期化開始...');

      await Supabase.initialize(
        url: 'https://bwjvwohxwjbztaawcyxw.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ3anZ3b2h4d2pienRhYXdjeXh3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTcxMDkwMjA1OSwiZXhwIjoyMDI2NDc4MDU5fQ.EL3mHmMIBGUwwEUgBpw9ju4X2-w9qrY_P88ZpqFat8w',
      );

      _client = Supabase.instance.client;
      _initialized = true;

      print('Supabase初期化完了。権限: service_role');

      // 確認のため権限テスト
      try {
        final testResponse = await _client
            .from('pos_devices')
            .select('*')
            .limit(1);
        print('テーブルアクセステスト成功: $testResponse');
      } catch (e) {
        print('テーブルアクセステスト失敗: $e');
      }

    } catch (e) {
      print('Supabase初期化エラー: $e');
      rethrow; // エラーを上位に伝播
    }
  }

  // クライアントへのアクセサ
  static SupabaseClient get client {
    if (!_initialized) {
      throw Exception('Supabaseが初期化されていません。先にSupabaseManager.initialize()を呼び出してください。');
    }
    return _client;
  }
}

// グローバルアクセス用の関数 - 初期化チェック付き
SupabaseClient get supabase {
  return SupabaseManager.client;
}