import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
// こちらが必須： PostgrestMap, PostgrestList, PostgrestException を使う
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:staff_pos_app/services/supabase_manager.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 「遅延表示を有効にする」フラグ
  /// DB取得前は不明なので null。値が取れたら true/false が入る。
  bool? _isDelayOn;

  /// 遅延閾値(分)
  /// こちらも DB 取得前は不明なので null。値が取れたら int が入る。
  int? _threshold1;
  int? _threshold2;
  int? _threshold3;

  /// テーブルカラー情報
  List<Map<String, dynamic>> _tableColorList = [];

  /// ローディング中かどうか
  bool _isLoading = false;

  /// store_settings テーブルで使用する固定ID
  static const fixedStoreSettingsId = '00000000-0000-0000-0000-000000000001';

  @override
  void initState() {
    super.initState();
    _fetchStoreSettings();
    _fetchTableColors();
  }

  //----------------------------------------------------------------------------
  // store_settingsを1行だけ取得
  //----------------------------------------------------------------------------
  Future<void> _fetchStoreSettings() async {
    setState(() => _isLoading = true);

    try {
      // ① Supabase から maybeSingle() で単一行を取得すると、
      //    成功時は PostgrestMap? が返る（無い場合は null）
      //    エラー時は PostgrestException が throw される
      final PostgrestMap? data = await supabase
          .from('store_settings')
          .select()
          .eq('id', fixedStoreSettingsId)
          .maybeSingle();

      // ② もし data == null なら該当行が存在しない
      if (data == null) {
        debugPrint('Error: store_settings not found for id=$fixedStoreSettingsId');
        setState(() => _isLoading = false);
        return;
      }

      debugPrint('Store Settings data => $data');

      // is_delay_highlight_on
      final rawDelayOn = data['is_delay_highlight_on'];
      if (rawDelayOn is bool) {
        _isDelayOn = rawDelayOn;
      } else if (rawDelayOn is String) {
        _isDelayOn = rawDelayOn.toLowerCase() == 'true';
      } else {
        debugPrint('Error: is_delay_highlight_on のパースに失敗 raw=$rawDelayOn');
      }

      // delay_threshold1
      final rawT1 = data['delay_threshold1'];
      if (rawT1 is int) {
        _threshold1 = rawT1;
      } else if (rawT1 is double) {
        _threshold1 = rawT1.toInt();
      } else if (rawT1 is String) {
        final parsed = int.tryParse(rawT1);
        if (parsed == null) {
          debugPrint('Error: delay_threshold1 のパースに失敗 raw=$rawT1');
        } else {
          _threshold1 = parsed;
        }
      } else {
        debugPrint('Error: delay_threshold1 のパースに失敗 raw=$rawT1');
      }

      // delay_threshold2
      final rawT2 = data['delay_threshold2'];
      if (rawT2 is int) {
        _threshold2 = rawT2;
      } else if (rawT2 is double) {
        _threshold2 = rawT2.toInt();
      } else if (rawT2 is String) {
        final parsed = int.tryParse(rawT2);
        if (parsed == null) {
          debugPrint('Error: delay_threshold2 のパースに失敗 raw=$rawT2');
        } else {
          _threshold2 = parsed;
        }
      } else {
        debugPrint('Error: delay_threshold2 のパースに失敗 raw=$rawT2');
      }

      // delay_threshold3
      final rawT3 = data['delay_threshold3'];
      if (rawT3 is int) {
        _threshold3 = rawT3;
      } else if (rawT3 is double) {
        _threshold3 = rawT3.toInt();
      } else if (rawT3 is String) {
        final parsed = int.tryParse(rawT3);
        if (parsed == null) {
          debugPrint('Error: delay_threshold3 のパースに失敗 raw=$rawT3');
        } else {
          _threshold3 = parsed;
        }
      } else {
        debugPrint('Error: delay_threshold3 のパースに失敗 raw=$rawT3');
      }

      setState(() {}); // 値を更新してUIに反映する
    } on PostgrestException catch (e) {
      // DBエラーなど
      debugPrint('Failed to fetch store_settings (PostgrestException): ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('store_settingsの取得に失敗: ${e.message}')),
        );
      }
    } catch (e) {
      // その他の予期せぬエラー
      debugPrint('Failed to fetch store_settings (Other): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('store_settingsの取得に失敗: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  //----------------------------------------------------------------------------
  // table_colors全件取得
  // ※ こちらは複数行を取得するので maybeSingle() は使わない
  //----------------------------------------------------------------------------
  Future<void> _fetchTableColors() async {
    setState(() => _isLoading = true);

    try {
      // ① select() で複数行を取得すると PostgrestList が返る（List<dynamic> として見れる）
      //    エラーなら PostgrestException が throw される
      final PostgrestList data = await supabase
          .from('table_colors')
          .select();

      debugPrint('===== fetchTableColors response =====');
      debugPrint(data.toString()); // PostgrestList([...]) のように見える

      // ② 実際には中身が List<dynamic> なので、forで回しつつ map に取り出す
      final tableList = <Map<String, dynamic>>[];
      for (final row in data) {
        // row は dynamic だが、実際は Map<String, dynamic>想定
        final mapRow = row as Map<String, dynamic>;
        tableList.add({
          'table_name': mapRow['table_name'],
          'hex_color': mapRow['hex_color'] ?? '#FF9E9E9E',
        });
      }

      setState(() => _tableColorList = tableList);
    } on PostgrestException catch (e) {
      debugPrint('Failed to fetch table_colors (PostgrestException): ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('table_colorsの取得に失敗: ${e.message}')),
        );
      }
    } catch (e) {
      debugPrint('Failed to fetch table_colors (Other): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('table_colorsの取得に失敗: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  //----------------------------------------------------------------------------
  // store_settings & table_colorsの保存
  //----------------------------------------------------------------------------
  Future<void> _saveAllSettings() async {
    setState(() => _isLoading = true);
    try {
      // store_settings の更新データを組み立てる
      final storeSettingsRow = <String, dynamic>{'id': fixedStoreSettingsId};

      // null でなければ DB に送る
      if (_isDelayOn != null) {
        storeSettingsRow['is_delay_highlight_on'] = _isDelayOn;
      }
      if (_threshold1 != null) {
        storeSettingsRow['delay_threshold1'] = _threshold1;
      }
      if (_threshold2 != null) {
        storeSettingsRow['delay_threshold2'] = _threshold2;
      }
      if (_threshold3 != null) {
        storeSettingsRow['delay_threshold3'] = _threshold3;
      }

      // upsert は「衝突時に更新する」処理
      // 新APIではそのまま実行すると 成功時には PostgrestList / PostgrestMap が返り、エラー時は例外が投げられます
      final result = await supabase
          .from('store_settings')
          .upsert(storeSettingsRow, onConflict: 'id');

      // 単数 or 複数行のリストが返るが、今回は使わないのでログだけ
      debugPrint('===== store_settings upsert result =====');
      debugPrint(result.toString());

      // table_colors の更新
      for (final t in _tableColorList) {
        final tName = t['table_name'] as String?;
        final hex = t['hex_color'] as String?;
        if (tName == null || hex == null) continue;

        final updateResp = await supabase
            .from('table_colors')
            .update({'hex_color': hex})
            .eq('table_name', tName);

        debugPrint('===== table_colors updateResp for $tName =====');
        debugPrint(updateResp.toString());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('設定を保存しました')),
        );
      }
    } on PostgrestException catch (e) {
      debugPrint('Failed to saveAllSettings (PostgrestException): ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('設定保存中にエラー: ${e.message}')),
        );
      }
    } catch (e) {
      debugPrint('Failed to saveAllSettings (Other): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('設定保存中にエラー: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  //----------------------------------------------------------------------------
  // カラーピッカー
  //----------------------------------------------------------------------------
  Future<void> _pickColor(Map<String, dynamic> tableInfo) async {
    final initialColor = _parseColor(tableInfo['hex_color']) ?? Colors.grey;
    var pickedColor = initialColor;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('${tableInfo['table_name']} の色を選択'),
          content: BlockPicker(
            pickerColor: initialColor,
            onColorChanged: (Color color) => pickedColor = color,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('決定'),
            ),
          ],
        );
      },
    );

    setState(() {
      tableInfo['hex_color'] =
      '#${pickedColor.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
    });
  }

  Color? _parseColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return null;
    try {
      return Color(int.parse(hexColor.substring(1), radix: 16));
    } catch (_) {
      return null;
    }
  }

  //----------------------------------------------------------------------------
  // UI
  //----------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // 遅延表示フラグが null の場合、スイッチは false 扱いにする
    final isDelayOnVal = _isDelayOn ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 2,
                color: Colors.white,  // 追加
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 横幅を他と合わせるため contentPadding をゼロに設定
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '未提供商品の遅延表示を有効',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        value: isDelayOnVal,
                        onChanged: (val) => setState(() => _isDelayOn = val),
                      ),
                      if (isDelayOnVal) ...[
                        // 説明テキストエリアの外側パディングを水平方向はなくし、縦方向のみとする
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Card(
                            color: Color(0xFFF5F5F5),
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                '※ここで設定した時間を超過した商品は、視覚的に色分けして表示されます。',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                        _buildThresholdField('遅延表示時間1', _threshold1,
                                (v) => _threshold1 = v, '最初の警告表示までの時間'),
                        _buildThresholdField('遅延表示時間2', _threshold2,
                                (v) => _threshold2 = v, '中間の警告表示までの時間'),
                        _buildThresholdField('遅延表示時間3', _threshold3,
                                (v) => _threshold3 = v, '最終の警告表示までの時間'),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),

              const Divider(height: 32),

              Card(
                elevation: 2,
                color: Colors.white,  // 追加
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'テーブルカラー設定',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'カラーボタンをタップして色を選択してください。',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final info in _tableColorList)
                        _buildTableColorTile(info),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _saveAllSettings,
                child: const Text('設定を保存'),
              ),
            ],
          ),

          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildThresholdField(
      String label,
      int? value,
      void Function(int?) onChanged,
      String helperText,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: value?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    suffixText: '分',
                    helperText: helperText,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (val) {
                    final parsed = int.tryParse(val);
                    onChanged(parsed);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableColorTile(Map<String, dynamic> info) {
    final tableName = info['table_name'] as String;
    final hexColor = info['hex_color'] as String?;
    final currentColor = _parseColor(hexColor) ?? Colors.grey;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      title: Text(
        tableName,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      trailing: SizedBox(
        width: 40,
        height: 40,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: currentColor,
            shape: const CircleBorder(),
            elevation: 2,
          ),
          onPressed: () => _pickColor(info),
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }
}
