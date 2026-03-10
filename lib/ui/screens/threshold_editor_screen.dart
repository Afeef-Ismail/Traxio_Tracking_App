import 'package:flutter/material.dart';
import '../../database/db_helper.dart';
import '../theme/app_colors.dart';

/// Threshold Editor Screen — admin config panel.
///
/// Loads all key-value pairs from the config table,
/// displays each as an editable TextField, and saves changes.
class ThresholdEditorScreen extends StatefulWidget {
  const ThresholdEditorScreen({super.key});

  @override
  State<ThresholdEditorScreen> createState() => _ThresholdEditorScreenState();
}

class _ThresholdEditorScreenState extends State<ThresholdEditorScreen> {
  final DbHelper _db = DbHelper();
  bool _loading = true;
  bool _saving = false;
  bool _hasChanges = false;

  /// Original values from DB (for change detection).
  final Map<String, String> _originalValues = {};

  /// Current edited values.
  final Map<String, TextEditingController> _controllers = {};

  /// Display-friendly labels for config keys.
  static const Map<String, String> _labels = {
    'terrain_slope_uphill_threshold': 'Uphill Slope Threshold',
    'terrain_slope_downhill_threshold': 'Downhill Slope Threshold',
    'segment_length_meters': 'Segment Length (meters)',
    'deviation_score_max': 'Max Deviation Score',
    'cluster0_label': 'Cluster 0 Label',
    'cluster1_label': 'Cluster 1 Label',
  };

  /// Descriptions for each config key.
  static const Map<String, String> _descriptions = {
    'terrain_slope_uphill_threshold':
        'Slope (Δalt/Δdist) above which terrain is classified as Uphill',
    'terrain_slope_downhill_threshold':
        'Slope below which terrain is classified as Downhill (negative value)',
    'segment_length_meters':
        'Distance in meters for each analysis segment',
    'deviation_score_max':
        'Maximum deviation score cap',
    'cluster0_label':
        'Display name for benchmark cluster 0',
    'cluster1_label':
        'Display name for benchmark cluster 1',
  };

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final configs = await _db.getAllConfig();
    _originalValues.clear();
    _controllers.clear();

    for (final row in configs) {
      final key = row['key'] as String;
      final value = row['value'] as String;
      _originalValues[key] = value;
      _controllers[key] = TextEditingController(text: value);
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _checkChanges() {
    bool changed = false;
    for (final key in _controllers.keys) {
      if (_controllers[key]!.text != _originalValues[key]) {
        changed = true;
        break;
      }
    }
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);

    for (final key in _controllers.keys) {
      final newValue = _controllers[key]!.text.trim();
      if (newValue != _originalValues[key]) {
        await _db.setConfig(key, newValue);
        _originalValues[key] = newValue;
      }
    }

    if (mounted) {
      setState(() {
        _saving = false;
        _hasChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Threshold Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _saving ? null : _saveConfig,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildConfigList(isDark),
      ),
    );
  }

  Widget _buildConfigList(bool isDark) {
    // Order keys deterministically
    final keys = _controllers.keys.toList()..sort();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      itemCount: keys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final key = keys[index];
        final label = _labels[key] ?? key;
        final description = _descriptions[key] ?? '';
        final controller = _controllers[key]!;

        // Determine if it's numeric
        final isNumeric = key != 'cluster0_label' && key != 'cluster1_label';

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Label
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textOnDark
                      : AppColors.textPrimary,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Value field
              TextField(
                controller: controller,
                keyboardType: isNumeric
                    ? const TextInputType.numberWithOptions(
                        decimal: true, signed: true)
                    : TextInputType.text,
                onChanged: (_) => _checkChanges(),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkBackground
                      : AppColors.lightBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.dividerDark
                          : AppColors.dividerLight,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.dividerDark
                          : AppColors.dividerLight,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                  ),
                  hintText: _originalValues[key],
                  hintStyle: TextStyle(
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                ),
              ),

              // Key reference
              const SizedBox(height: 6),
              Text(
                'key: $key',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: isDark
                      ? AppColors.textOnDarkSecondary.withOpacity(0.5)
                      : AppColors.textMuted.withOpacity(0.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
