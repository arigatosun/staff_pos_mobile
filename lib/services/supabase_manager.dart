import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseManager {
  static final SupabaseManager _instance = SupabaseManager._internal();
  late final SupabaseClient client;
  static bool _initialized = false;

  factory SupabaseManager() {
    return _instance;
  }

  SupabaseManager._internal();

  // 初期化メソッドを追加
  static Future<void> initialize() async {
    if (_initialized) return;

    await Supabase.initialize(
      url: 'https://bwjvwohxwjbztaawcyxw.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ3anZ3b2h4d2pienRhYXdjeXh3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTcxMDkwMjA1OSwiZXhwIjoyMDI2NDc4MDU5fQ.EL3mHmMIBGUwwEUgBpw9ju4X2-w9qrY_P88ZpqFat8w',
    );

    _instance.client = Supabase.instance.client;
    _initialized = true;
  }
}

// グローバルアクセス用のショートカット
final supabase = Supabase.instance.client;