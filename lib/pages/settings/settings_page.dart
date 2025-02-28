import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:staff_pos_app/services/supabase_manager.dart';

class SettingsPage extends StatefulWidget {
  final int storeId;
  const SettingsPage({super.key, required this.storeId});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 「遅延表示を有効にする」フラグ
  bool? _isDelayOn;

  /// 遅延閾値(分)
  int? _threshold1;
  int? _threshold2;
  int? _threshold3;

  /// テーブルカラー情報: [ { table_name: '...', hex_color: '#FFFF...' }, ... ]
  List<Map<String, dynamic>> _tableColorList = [];

  /// 店舗テーブル情報: [ { table_id: '...', table_name: '...', color_info: {...} }, ... ]
  List<Map<String, dynamic>> _storeTableList = [];

  /// ローディング中かどうか
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchStoreSettings();
    _fetchStoreTables();
  }

  // ------------------------------------------------------------------------
  // 1) store_settings を読み込み (store_id = widget.storeId で1行を特定)
  // ------------------------------------------------------------------------
  Future<void> _fetchStoreSettings() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('store_settings')
          .select()
          .eq('store_id', widget.storeId) // store_id で絞り込み
          .maybeSingle();

      if (data == null) {
        // store_settings がまだ存在しない場合もある
        debugPrint('No store_settings found for store_id=${widget.storeId}');
        setState(() => _isLoading = false);
        return;
      }

      // 取得成功時: データをパース
      _isDelayOn = data['is_delay_highlight_on'] as bool? ?? false;
      _threshold1 = data['delay_threshold1'] as int? ?? 10;
      _threshold2 = data['delay_threshold2'] as int? ?? 40;
      _threshold3 = data['delay_threshold3'] as int? ?? 60;

    } on PostgrestException catch (e) {
      debugPrint('PostgrestException: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('store_settings取得エラー: ${e.message}')),
        );
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ------------------------------------------------------------------------
  // 2) store_table からテーブル一覧を取得し、table_colors と結合する
  // ------------------------------------------------------------------------
  Future<void> _fetchStoreTables() async {
    setState(() => _isLoading = true);
    try {
      // 2-1) store_table から店舗のテーブル一覧を取得
      final tableData = await supabase
          .from('store_table')
          .select('id, "tableId", "tableName"')
          .eq('"storeId"', widget.storeId)
          .order('"tableName"', ascending: true);

      // 2-2) table_colors からテーブルの色情報を取得
      final colorData = await supabase
          .from('table_colors')
          .select()
          .eq('store_id', widget.storeId);

      // テーブルカラー情報をマップに変換（O(1)検索用）
      final colorMap = <String, String>{};
      for (final color in colorData) {
        final tableName = color['table_name'] as String;
        final hexColor = color['hex_color'] as String? ?? '#FF9E9E9E';
        colorMap[tableName] = hexColor;
      }

      // テーブル情報と色情報を結合
      final combinedList = <Map<String, dynamic>>[];
      for (final table in tableData) {
        final tableId = table['tableId'] as String;
        final tableName = table['tableName'] as String? ?? tableId;

        // 色情報を検索（なければデフォルト色）
        // tableName で検索するように変更
        final hexColor = colorMap[tableName] ?? '#FF9E9E9E';

        combinedList.add({
          'table_id': tableId,
          'table_name': tableName,
          'hex_color': hexColor,
        });
      }

      // テーブルカラー情報も別途保持（従来の処理との互換性のため）
      _tableColorList = combinedList.map((table) {
        return {
          'table_name': table['table_name'], // tableName を使用
          'hex_color': table['hex_color'],
        };
      }).toList();

      setState(() {
        _storeTableList = combinedList;
      });

    } on PostgrestException catch (e) {
      debugPrint('テーブル一覧取得エラー: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('テーブル一覧取得エラー: ${e.message}')),
        );
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ------------------------------------------------------------------------
  // 3) store_settings & table_colors を保存
  // ------------------------------------------------------------------------
  Future<void> _saveAllSettings() async {
    setState(() => _isLoading = true);
    try {
      // 3-1) 既存のstore_settingsレコードがあるか確認
      final existingSettings = await supabase
          .from('store_settings')
          .select('id')
          .eq('store_id', widget.storeId)
          .maybeSingle();

      final settingsData = <String, dynamic>{
        'store_id': widget.storeId,
        'is_delay_highlight_on': _isDelayOn ?? false,
        'delay_threshold1': _threshold1 ?? 10,
        'delay_threshold2': _threshold2 ?? 40,
        'delay_threshold3': _threshold3 ?? 60,
      };

      // 既存レコードがある場合は更新、なければ新規作成
      if (existingSettings != null) {
        await supabase
            .from('store_settings')
            .update(settingsData)
            .eq('store_id', widget.storeId);
      } else {
        await supabase
            .from('store_settings')
            .insert(settingsData);
      }

      // 3-2) table_colorsの保存（upsertを使用）
      final colorUpserts = <Map<String, dynamic>>[];

      for (final table in _storeTableList) {
        final tableId = table['table_id'];
        final tableName = table['table_name'];
        final hexColor = table['hex_color'];

        colorUpserts.add({
          'store_id': widget.storeId,
          'table_name': tableName, // tableIdではなくtableNameを使用
          'hex_color': hexColor,
          'color_index': 0, // デフォルト値
        });
      }

      if (colorUpserts.isNotEmpty) {
        await supabase
            .from('table_colors')
            .upsert(colorUpserts, onConflict: 'store_id,table_name');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('設定を保存しました')),
        );
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('設定保存エラー: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ------------------------------------------------------------------------
  // カラーピッカー
  // ------------------------------------------------------------------------
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
            onColorChanged: (Color color) {
              pickedColor = color;
            },
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

    // ピッカーで選択された色を反映
    setState(() {
      final newHexColor = '#${pickedColor.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
      tableInfo['hex_color'] = newHexColor;

      // テーブルカラーリストにも反映（同期を保つ）
      for (final colorInfo in _tableColorList) {
        if (colorInfo['table_name'] == tableInfo['table_name']) { // table_id ではなく table_name で比較
          colorInfo['hex_color'] = newHexColor;
          break;
        }
      }
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

  // ------------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // 遅延表示フラグが null の場合はとりあえず false 扱い
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
              // 遅延設定
              Card(
                elevation: 2,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '未提供商品の遅延表示を有効',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        value: isDelayOnVal,
                        onChanged: (val) {
                          setState(() => _isDelayOn = val);
                        },
                      ),
                      if (isDelayOnVal) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Card(
                            color: Color(0xFFF5F5F5),
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                '※ここで設定した時間を超過した商品は色分けされます。',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                        _buildThresholdField(
                          label: '遅延表示時間1',
                          value: _threshold1,
                          onChanged: (v) => _threshold1 = v,
                          helperText: '最初の警告表示までの時間(分)',
                        ),
                        _buildThresholdField(
                          label: '遅延表示時間2',
                          value: _threshold2,
                          onChanged: (v) => _threshold2 = v,
                          helperText: '中間の警告表示までの時間(分)',
                        ),
                        _buildThresholdField(
                          label: '遅延表示時間3',
                          value: _threshold3,
                          onChanged: (v) => _threshold3 = v,
                          helperText: '最終の警告表示までの時間(分)',
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // テーブルカラー設定
              Card(
                elevation: 2,
                color: Colors.white,
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
                          'カラーボタンをタップして色を選択できます。',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_storeTableList.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('設定可能なテーブルがありません'),
                          ),
                        )
                      else
                        for (final tableInfo in _storeTableList)
                          _buildTableColorTile(tableInfo),
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

          // ローディング中インジケータ
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  // 入力フィールド
  Widget _buildThresholdField({
    required String label,
    required int? value,
    required void Function(int?) onChanged,
    required String helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
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

  Widget _buildTableColorTile(Map<String, dynamic> tableInfo) {
    final tableId = tableInfo['table_id'] as String;
    final tableName = tableInfo['table_name'] as String;
    final hexColor = tableInfo['hex_color'] as String?;
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
          onPressed: () => _pickColor(tableInfo),
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }
  }