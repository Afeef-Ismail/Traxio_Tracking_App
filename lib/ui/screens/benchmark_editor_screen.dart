import 'package:flutter/material.dart';
import '../../database/db_helper.dart';
import '../../config/constants.dart';
import '../theme/app_colors.dart';

/// Benchmark Ranges Editor — admin can view and edit cluster ranges
/// for each terrain type's 10 benchmark features.
class BenchmarkEditorScreen extends StatefulWidget {
  const BenchmarkEditorScreen({super.key});

  @override
  State<BenchmarkEditorScreen> createState() => _BenchmarkEditorScreenState();
}

class _BenchmarkEditorScreenState extends State<BenchmarkEditorScreen>
    with SingleTickerProviderStateMixin {
  final DbHelper _db = DbHelper();
  late TabController _tabController;

  static const _terrains = [
    AppConstants.terrainPlain,
    AppConstants.terrainUphill,
    AppConstants.terrainDownhill,
  ];

  /// Raw benchmark rows per terrain, keyed by terrain name.
  final Map<String, List<Map<String, dynamic>>> _data = {};

  /// TextEditingControllers per terrain+feature+field
  /// Key: "terrain|featureKey|field" where field is c0min, c0max, c1min, c1max
  final Map<String, TextEditingController> _controllers = {};

  bool _loading = true;
  bool _saving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _terrains.length, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    for (final terrain in _terrains) {
      final rows = await _db.getBenchmarkConfigRaw(terrain);
      _data[terrain] = rows;

      for (final row in rows) {
        final fk = row['feature_key'] as String;
        final prefix = '$terrain|$fk';
        _controllers['$prefix|c0min'] =
            TextEditingController(text: _fmt(row['cluster0_min']));
        _controllers['$prefix|c0max'] =
            TextEditingController(text: _fmt(row['cluster0_max']));
        _controllers['$prefix|c1min'] =
            TextEditingController(text: _fmt(row['cluster1_min']));
        _controllers['$prefix|c1max'] =
            TextEditingController(text: _fmt(row['cluster1_max']));
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  String _fmt(dynamic v) {
    final d = (v as num).toDouble();
    // Show enough precision but trim trailing zeros
    String s = d.toStringAsFixed(6);
    // Remove trailing zeros after decimal point
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  void _onChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);

    for (final terrain in _terrains) {
      final rows = _data[terrain] ?? [];
      for (final row in rows) {
        final fk = row['feature_key'] as String;
        final prefix = '$terrain|$fk';
        final c0min =
            double.tryParse(_controllers['$prefix|c0min']!.text) ?? 0;
        final c0max =
            double.tryParse(_controllers['$prefix|c0max']!.text) ?? 0;
        final c1min =
            double.tryParse(_controllers['$prefix|c1min']!.text) ?? 0;
        final c1max =
            double.tryParse(_controllers['$prefix|c1max']!.text) ?? 0;

        await _db.updateBenchmarkRange(
          terrain: terrain,
          featureKey: fk,
          cluster0Min: c0min,
          cluster0Max: c0max,
          cluster1Min: c1min,
          cluster1Max: c1max,
        );
      }
    }

    if (mounted) {
      setState(() {
        _saving = false;
        _hasChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Benchmark ranges saved'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _resetTerrain(String terrain) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Defaults?'),
        content: Text(
            'Reset all $terrain benchmark ranges to the original research values?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _db.resetBenchmarkDefaults(terrain);

    // Reload data for this terrain
    final rows = await _db.getBenchmarkConfigRaw(terrain);
    _data[terrain] = rows;

    for (final row in rows) {
      final fk = row['feature_key'] as String;
      final prefix = '$terrain|$fk';
      _controllers['$prefix|c0min']?.text = _fmt(row['cluster0_min']);
      _controllers['$prefix|c0max']?.text = _fmt(row['cluster0_max']);
      _controllers['$prefix|c1min']?.text = _fmt(row['cluster1_min']);
      _controllers['$prefix|c1max']?.text = _fmt(row['cluster1_max']);
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$terrain ranges reset to defaults'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Benchmark Ranges'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _saving ? null : _saveAll,
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
        bottom: TabBar(
          controller: _tabController,
          tabs: _terrains
              .map((t) => Tab(text: t))
              .toList(),
          indicatorColor: AppColors.primary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: _terrains
                  .map((t) => _buildTerrainTab(t, isDark))
                  .toList(),
            ),
    );
  }

  Widget _buildTerrainTab(String terrain, bool isDark) {
    final rows = _data[terrain] ?? [];

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, index) =>
                _buildFeatureCard(terrain, rows[index], isDark),
          ),
        ),
        // Reset button at bottom
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => _resetTerrain(terrain),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Reset to Defaults'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.alert,
              side: BorderSide(color: AppColors.alert.withOpacity(0.5)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard(
      String terrain, Map<String, dynamic> row, bool isDark) {
    final fk = row['feature_key'] as String;
    final prefix = '$terrain|$fk';
    final unit = AppConstants.getFeatureUnit(fk);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feature name + unit
          Row(
            children: [
              Text(
                fk,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color:
                      isDark ? AppColors.textOnDark : AppColors.textPrimary,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  '($unit)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Cluster 0
          Text(
            'Cluster 0',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _rangeField(
                    '$prefix|c0min', 'Min', isDark),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _rangeField(
                    '$prefix|c0max', 'Max', isDark),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Cluster 1
          Text(
            'Cluster 1',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.terrainUphill,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _rangeField(
                    '$prefix|c1min', 'Min', isDark),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _rangeField(
                    '$prefix|c1max', 'Max', isDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rangeField(String key, String hint, bool isDark) {
    return TextField(
      controller: _controllers[key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => _onChanged(),
      style: TextStyle(
        fontSize: 13,
        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(
          fontSize: 12,
          color: isDark
              ? AppColors.textOnDarkSecondary
              : AppColors.textMuted,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color:
                isDark ? AppColors.dividerDark : AppColors.dividerLight,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color:
                isDark ? AppColors.dividerDark : AppColors.dividerLight,
          ),
        ),
      ),
    );
  }
}
