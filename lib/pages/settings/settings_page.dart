import 'package:flutter/material.dart';
import 'package:staff_pos_app/services/supabase_manager.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // 遅延表示設定
  bool _isDelayOn = true;
  int _threshold1 = 10;
  int _threshold2 = 40;
  int _threshold3 = 60;

  // テーブルカラーリスト
  // [{table_name: 'Table1', color_index: 2, hex_color: '#FF0000'}, ...]
  List<Map<String, dynamic>> _tableColorList = [];

  @override
  void initState() {
    super.initState();
    _fetchSettings();
    _fetchTableColors();
  }

  /// store_settings を単一レコード取得
  Future<void> _fetchSettings() async {
    try {
      final res = await supabase
          .from('store_settings')
          .select()
          .limit(1)
          .maybeSingle();

      if (res != null) {
        setState(() {
          _isDelayOn = res['is_delay_highlight_on'] as bool? ?? true;
          _threshold1 = res['delay_threshold1'] as int? ?? 10;
          _threshold2 = res['delay_threshold2'] as int? ?? 40;
          _threshold3 = res['delay_threshold3'] as int? ?? 60;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch store_settings: $e');
    }
  }

  /// table_colors から全データ取得
  Future<void> _fetchTableColors() async {
    try {
      final res = await supabase.from('table_colors').select();
      if (res is List) {
        setState(() {
          _tableColorList = res.map((r) => {
            'table_name': r['table_name'],
            'color_index': r['color_index'], // 旧ロジック用
            'hex_color': r['hex_color'],
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch table_colors: $e');
    }
  }

  /// 保存ボタン押下時に store_settings & table_colors を更新
  Future<void> _saveSettings() async {
    // 1) store_settings
    try {
      // 単一レコード運用なので、INSERT or UPDATE どちらでもOK: upsertで対応
      // id は必須; 今回は常に1つだけ使う想定なので、既に存在しなければ自動生成されたidが付与される
      await supabase
          .from('store_settings')
          .upsert({
        'id': '00000000-0000-0000-0000-000000000001', // 単店舗用の固定IDなど
        'is_delay_highlight_on': _isDelayOn,
        'delay_threshold1': _threshold1,
        'delay_threshold2': _threshold2,
        'delay_threshold3': _threshold3,
      })
          .eq('id', '00000000-0000-0000-0000-000000000001');
    } catch (e) {
      debugPrint('Failed to upsert store_settings: $e');
    }

    // 2) table_colors
    for (final t in _tableColorList) {
      final tName = t['table_name'];
      final hex = t['hex_color'];
      if (tName == null) continue;
      try {
        await supabase
            .from('table_colors')
            .update({'hex_color': hex}).eq('table_name', tName);
      } catch (e) {
        debugPrint('Failed to update table_colors: $e');
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('設定を保存しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 遅延表示 ON/OFF
          SwitchListTile(
            title: const Text('未提供商品の遅延表示を有効にする'),
            value: _isDelayOn,
            onChanged: (val) {
              setState(() => _isDelayOn = val);
            },
          ),

          // 遅延閾値設定 (3段階)
          if (_isDelayOn) ...[
            _buildThresholdField(
              label: '遅延閾値1 (分)',
              value: _threshold1,
              onChanged: (v) => _threshold1 = v,
            ),
            _buildThresholdField(
              label: '遅延閾値2 (分)',
              value: _threshold2,
              onChanged: (v) => _threshold2 = v,
            ),
            _buildThresholdField(
              label: '遅延閾値3 (分)',
              value: _threshold3,
              onChanged: (v) => _threshold3 = v,
            ),
          ],

          const Divider(height: 32),

          // テーブルカラー
          const Text(
            'テーブルカラー設定',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Column(
            children: _tableColorList.map((tableInfo) {
              final tableName = tableInfo['table_name'] as String;
              final hexColor = tableInfo['hex_color'] as String?;
              final currentColor = _parseColor(hexColor) ?? Colors.grey;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tableName),
                trailing: SizedBox(
                  width: 40,
                  height: 40,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: currentColor,
                      shape: const CircleBorder(),
                    ),
                    onPressed: () => _pickColor(tableInfo),
                    child: const SizedBox.shrink(),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saveSettings,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildThresholdField({
    required String label,
    required int value,
    required Function(int) onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 200, child: Text(label)),
        Expanded(
          child: TextFormField(
            initialValue: value.toString(),
            keyboardType: TextInputType.number,
            onChanged: (val) {
              final parsed = int.tryParse(val) ?? 0;
              onChanged(parsed);
            },
          ),
        ),
        const Text(' 分'),
      ],
    );
  }

  Future<void> _pickColor(Map<String, dynamic> tableInfo) async {
    Color initialColor = _parseColor(tableInfo['hex_color']) ?? Colors.grey;
    Color pickedColor = initialColor;

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
}
