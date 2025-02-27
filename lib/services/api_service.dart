// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

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
        // 正常時 -> storeId を返す
        return jsonBody['storeId'] as int;
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
}
