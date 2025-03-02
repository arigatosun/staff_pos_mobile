import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SupabaseManager {
  static final SupabaseManager _instance = SupabaseManager._internal();
  static bool _initialized = false;
  static late final SupabaseClient _client;

  // 現在ログインしている店舗のIDを保持する変数
  static int? _currentStoreId;
  static bool _isWorking = false;

  // SharedPreferencesのキー
  static const String _storeIdKey = 'current_store_id';
  static const String _isWorkingKey = 'is_working';
  static const String _deviceIdKey = 'current_device_id';

  factory SupabaseManager() {
    return _instance;
  }

  SupabaseManager._internal();

  // 初期化メソッドを改良
  static Future<void> initialize() async {
    if (_initialized) {
      print('Supabase既に初期化済み、再初期化をスキップします');
      return;
    }

    try {
      print('Supabase初期化開始...');

      // 先に保存された値を読み込む - 初期化前に状態を設定
      await _loadSavedValues();
      print('保存された値を事前読み込み: storeId=$_currentStoreId, isWorking=$_isWorking');

      await Supabase.initialize(
        url: 'https://bwjvwohxwjbztaawcyxw.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ3anZ3b2h4d2pienRhYXdjeXh3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTA5MDIwNTksImV4cCI6MjAyNjQ3ODA1OX0.FEjg5lpYEQYzJA_JfH_2Q1Dx8gBExoO97ch2JYE_bRw',
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

      // 初期化後に保存値との整合性チェック - デバッグ用
      print('SupabaseManager初期化後のステータス: storeId=$_currentStoreId, isWorking=$_isWorking');

    } catch (e) {
      print('Supabase初期化エラー: $e');
      rethrow;
    }
  }

// 保存されている値を読み込む（独立した関数として実装）
  static Future<void> _loadSavedValues() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 店舗ID
      final storeId = prefs.getInt(_storeIdKey);
      if (storeId != null) {
        _currentStoreId = storeId;
        print('保存された店舗IDを読み込みました: $storeId');
      } else {
        print('保存された店舗IDがありません');
      }

      // 勤務状態
      final isWorking = prefs.getBool(_isWorkingKey);
      if (isWorking != null) {
        _isWorking = isWorking;
        print('保存された勤務状態を読み込みました: ${isWorking ? "勤務中" : "休憩中"}');
      } else {
        print('保存された勤務状態がありません');
      }
    } catch (e) {
      print('保存値の読み込みエラー: $e');
    }
  }

  // クライアントへのアクセサ
  static SupabaseClient get client {
    if (!_initialized) {
      throw Exception('Supabaseが初期化されていません。先にSupabaseManager.initialize()を呼び出してください。');
    }
    return _client;
  }

  // 店舗IDを設定するメソッド - ログイン成功時に呼び出す
  static Future<void> setLoggedInStoreId(int storeId) async {
    _currentStoreId = storeId;
    print('店舗ID設定: $_currentStoreId');

    // ローカルストレージに保存
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_storeIdKey, storeId);
      print('店舗IDをローカルストレージに保存しました: $storeId');
    } catch (e) {
      print('店舗ID保存エラー: $e');
    }
  }

  // 店舗IDを取得するメソッド
  static int? getLoggedInStoreId() {
    return _currentStoreId;
  }

  // 勤務状態を設定するメソッド
  static Future<void> setWorkingStatus(bool isWorking) async {
    _isWorking = isWorking;
    print('勤務状態設定: ${isWorking ? "勤務中" : "休憩中"}');

    // ローカルストレージに保存
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isWorkingKey, isWorking);
      print('勤務状態をローカルストレージに保存しました: ${isWorking ? "勤務中" : "休憩中"}');
    } catch (e) {
      print('勤務状態保存エラー: $e');
    }
  }

  // 勤務状態を取得するメソッド
  static bool getWorkingStatus() {
    return _isWorking;
  }

  // デバイスIDを保存するメソッド
  static Future<void> saveDeviceId(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceIdKey, deviceId);
      print('デバイスIDをローカルストレージに保存しました: $deviceId');
    } catch (e) {
      print('デバイスID保存エラー: $e');
    }
  }

  // デバイスIDを取得するメソッド
  static Future<String?> getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_deviceIdKey);
    } catch (e) {
      print('デバイスID取得エラー: $e');
      return null;
    }
  }

  // ログアウト時にクリアするメソッド - 既存実装
  static Future<void> clearLoggedInData() async {
    _currentStoreId = null;
    _isWorking = false;
    print('ログイン情報をクリアしました');

    // ローカルストレージからも削除
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storeIdKey);
      await prefs.remove(_isWorkingKey);
      // デバイスIDは削除しないで保持（再ログイン時に利用するため）
      print('ログイン情報をローカルストレージからクリアしました');
    } catch (e) {
      print('ログイン情報クリアエラー: $e');
    }
  }

  // 後方互換性のために追加したメソッド - 既存APIとの互換性維持
  static Future<void> clearLoggedInStoreId() async {
    // clearLoggedInDataを呼び出して処理を統一
    await clearLoggedInData();
    print('clearLoggedInStoreId: 互換性のためclearLoggedInDataを呼び出しました');
  }

  // リアルタイム購読の状態をリセット
  static void resetRealtimeSubscriptions() {
    if (_initialized) {
      _client.realtime.removeAllChannels();
      print('リアルタイム購読をリセットしました');
    }
  }
}

// グローバルアクセス用の関数 - 初期化チェック付き
SupabaseClient get supabase {
  return SupabaseManager.client;
}