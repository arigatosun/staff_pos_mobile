import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseManager {
  static final SupabaseManager _instance = SupabaseManager._internal();
  static bool _initialized = false;
  static late final SupabaseClient _client;

  factory SupabaseManager() {
    return _instance;
  }

  SupabaseManager._internal();

  // 初期化メソッドを改良
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      print('Supabase初期化開始...');

      await Supabase.initialize(
        url: 'https://bwjvwohxwjbztaawcyxw.supabase.co',
        // anonキーを使用 (公開アプリではservice_roleキーを使用するのは危険です)
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ3anZ3b2h4d2pienRhYXdjeXh3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTA5MDIwNTksImV4cCI6MjAyNjQ3ODA1OX0.FEjg5lpYEQYzJA_JfH_2Q1Dx8gBExoO97ch2JYE_bRw',
        // リアルタイム接続のデバッグを有効化
        realtimeClientOptions: const RealtimeClientOptions(
          logLevel: RealtimeLogLevel.info,
        ),
      );

      _client = Supabase.instance.client;
      _initialized = true;

      print('Supabase初期化完了');

      // リアルタイム接続デバッグ
      _client.realtime.onOpen(() {
        print('✅ リアルタイム接続オープン');
      });

      _client.realtime.onClose((event) {
        print('❌ リアルタイム接続クローズ: $event');
      });

      _client.realtime.onError((error) {
        print('❌ リアルタイム接続エラー: $error');
      });

      // リアルタイム接続を明示的に確立
      _client.realtime.connect();

    } catch (e) {
      print('Supabase初期化エラー: $e');
      rethrow;
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