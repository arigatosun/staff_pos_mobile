import 'package:flutter/material.dart';
import '../../services/api_service.dart';
// ★ HomePage を利用するための import （パスはプロジェクト構成に合わせて調整）
import 'package:staff_pos_app/pages/home_page.dart';

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
