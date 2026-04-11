import 'package:flutter/material.dart';
import '../../database/db_helper.dart';
import '../../models/cluster_model.dart';
import '../../config/constants.dart';
import '../../utils/feature_display_utils.dart';
import '../theme/app_colors.dart';

/// Vehicle type icon mapping.
IconData vehicleTypeIcon(String vehicleType) {
  switch (vehicleType) {
    case 'Bus':
      return Icons.directions_bus_rounded;
    case 'Car':
      return Icons.directions_car_rounded;
    case 'Truck':
      return Icons.local_shipping_rounded;
    case 'Auto':
      return Icons.electric_rickshaw_rounded;
    case 'Bike':
      return Icons.two_wheeler_rounded;
    default:
      return Icons.commute_rounded;
  }
}

const _vehicleTypes = ['Bus', 'Minibus', 'Car', 'Auto', 'Bike', 'Other'];

/// Admin screen for managing benchmark clusters.
class ClusterManagementScreen extends StatefulWidget {
  const ClusterManagementScreen({super.key});

  @override
  State<ClusterManagementScreen> createState() =>
      _ClusterManagementScreenState();
}

class _ClusterManagementScreenState extends State<ClusterManagementScreen> {
  final DbHelper _db = DbHelper();
  List<ClusterDefinition> _clusters = [];
  Map<int, int> _featureCounts = {}; // clusterId → total feature count
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClusters();
  }

  Future<void> _loadClusters() async {
    final clusters = await _db.getAllClusters();
    final counts = <int, int>{};
    for (final c in clusters) {
      if (c.id != null) {
        final features = await _db.getAllClusterFeatures(c.id!);
        counts[c.id!] = features.length;
      }
    }
    if (mounted) {
      setState(() {
        _clusters = clusters;
        _featureCounts = counts;
        _loading = false;
      });
    }
  }

  Future<void> _toggleActive(ClusterDefinition cluster) async {
    final newActive = !cluster.isActive;
    await _db.updateCluster(cluster.copyWith(isActive: newActive));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newActive
              ? '${cluster.name} activated'
              : '${cluster.name} deactivated — will not be used in future trips'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    _loadClusters();
  }

  Future<void> _deleteCluster(ClusterDefinition cluster) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Cluster?'),
        content: const Text(
          'Deleting this cluster will not affect existing trip scores. '
          'The cluster will be deactivated and hidden from scoring. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.alert),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && cluster.id != null) {
      await _db.deleteCluster(cluster.id!);
      _loadClusters();
    }
  }

  Future<void> _openAddWizard() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const ClusterWizardScreen(),
      ),
    );
    if (result == true) _loadClusters();
  }

  Future<void> _openEditWizard(ClusterDefinition cluster) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClusterWizardScreen(existingCluster: cluster),
      ),
    );
    if (result == true) _loadClusters();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeCount = _clusters.where((c) => c.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cluster Management'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddWizard,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Cluster'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (activeCount == 0) _buildNoActiveWarning(isDark),
                  Expanded(
                    child: _clusters.isEmpty
                        ? _buildEmpty(isDark)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                            itemCount: _clusters.length,
                            itemBuilder: (_, i) => _ClusterCard(
                              cluster: _clusters[i],
                              featureCount: _featureCounts[_clusters[i].id] ?? 0,
                              isDark: isDark,
                              onToggleActive: () => _toggleActive(_clusters[i]),
                              onEdit: () => _openEditWizard(_clusters[i]),
                              onDelete: () => _deleteCluster(_clusters[i]),
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildNoActiveWarning(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No active clusters — trips cannot be scored.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_work_outlined,
              size: 56,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'No clusters yet.\nTap + to create one.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClusterCard extends StatelessWidget {
  final ClusterDefinition cluster;
  final int featureCount;
  final bool isDark;
  final VoidCallback onToggleActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClusterCard({
    required this.cluster,
    required this.featureCount,
    required this.isDark,
    required this.onToggleActive,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cluster.isActive
              ? AppColors.primary.withOpacity(0.3)
              : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
          width: cluster.isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    vehicleTypeIcon(cluster.vehicleType),
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cluster.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textOnDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        cluster.vehicleType,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textOnDarkSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: cluster.isActive,
                  activeColor: AppColors.primary,
                  onChanged: (_) => onToggleActive(),
                ),
              ],
            ),
            if (cluster.route.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.route_rounded,
                    size: 14,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      cluster.route,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.textOnDarkSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                _InfoChip(
                  label: '$featureCount features',
                  icon: Icons.data_object_rounded,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _InfoChip(
                  label: cluster.isActive ? 'Active' : 'Inactive',
                  icon: cluster.isActive
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  isDark: isDark,
                  color: cluster.isActive ? AppColors.success : null,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  onPressed: onEdit,
                  color: isDark
                      ? AppColors.textOnDarkSecondary
                      : AppColors.textSecondary,
                  tooltip: 'Edit cluster',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppColors.alert.withOpacity(0.7),
                  ),
                  onPressed: onDelete,
                  tooltip: 'Delete cluster',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final Color? color;

  const _InfoChip({
    required this.label,
    required this.icon,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ??
        (isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Cluster Wizard Screen (Add / Edit)
// ═══════════════════════════════════════════════════════════════════════

class ClusterWizardScreen extends StatefulWidget {
  final ClusterDefinition? existingCluster;

  const ClusterWizardScreen({super.key, this.existingCluster});

  @override
  State<ClusterWizardScreen> createState() => _ClusterWizardScreenState();
}

class _ClusterWizardScreenState extends State<ClusterWizardScreen> {
  final DbHelper _db = DbHelper();
  int _currentStep = 0;
  bool _saving = false;

  // Step 1 fields
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _routeController = TextEditingController();
  String _vehicleType = 'Bus';
  final _formKey = GlobalKey<FormState>();

  // Step 2 fields: terrain → list of feature ranges
  final Map<String, List<_FeatureEntry>> _featuresByTerrain = {
    AppConstants.terrainPlain: [],
    AppConstants.terrainUphill: [],
    AppConstants.terrainDownhill: [],
  };

  @override
  void initState() {
    super.initState();
    final c = widget.existingCluster;
    if (c != null) {
      _nameController.text = c.name;
      _descController.text = c.description;
      _routeController.text = c.route;
      _vehicleType = c.vehicleType;
      _loadExistingFeatures(c.id!);
    }
  }

  Future<void> _loadExistingFeatures(int clusterId) async {
    for (final terrain in _featuresByTerrain.keys) {
      final features = await _db.getClusterFeatures(clusterId, terrain);
      if (mounted) {
        setState(() {
          _featuresByTerrain[terrain] = features
              .map((f) => _FeatureEntry(
                    featureName: f.featureName,
                    minController:
                        TextEditingController(text: f.minValue.toString()),
                    maxController:
                        TextEditingController(text: f.maxValue.toString()),
                    existingId: f.id,
                  ))
              .toList();
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _routeController.dispose();
    for (final entries in _featuresByTerrain.values) {
      for (final e in entries) {
        e.minController.dispose();
        e.maxController.dispose();
      }
    }
    super.dispose();
  }

  bool get _isEditing => widget.existingCluster != null;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();

      if (_isEditing) {
        final updated = widget.existingCluster!.copyWith(
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          route: _routeController.text.trim(),
          vehicleType: _vehicleType,
          updatedAt: now,
        );
        await _db.updateCluster(updated);

        // Replace all features
        await _db.removeAllClusterFeatures(updated.id!);
        for (final terrain in _featuresByTerrain.keys) {
          for (final entry in _featuresByTerrain[terrain]!) {
            final minVal = double.tryParse(entry.minController.text) ?? 0.0;
            final maxVal = double.tryParse(entry.maxController.text) ?? 0.0;
            await _db.addClusterFeature(ClusterFeatureRange(
              clusterId: updated.id!,
              terrain: terrain,
              featureName: entry.featureName,
              minValue: minVal,
              maxValue: maxVal.isNaN || maxVal == minVal ? minVal + 1 : maxVal,
              updatedAt: now,
            ));
          }
        }
      } else {
        final newCluster = ClusterDefinition(
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          route: _routeController.text.trim(),
          vehicleType: _vehicleType,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        );
        final clusterId = await _db.createCluster(newCluster);

        for (final terrain in _featuresByTerrain.keys) {
          for (final entry in _featuresByTerrain[terrain]!) {
            final minVal = double.tryParse(entry.minController.text) ?? 0.0;
            final maxVal = double.tryParse(entry.maxController.text) ?? 0.0;
            await _db.addClusterFeature(ClusterFeatureRange(
              clusterId: clusterId,
              terrain: terrain,
              featureName: entry.featureName,
              minValue: minVal,
              maxValue: maxVal <= minVal ? minVal + 1 : maxVal,
              updatedAt: now,
            ));
          }
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _isEditing ? 'Edit Cluster' : 'Add Cluster';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStepHeader(isDark),
            Expanded(
              child: _buildStepContent(isDark),
            ),
            _buildNavButtons(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildStepHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: isDark ? AppColors.darkCard : AppColors.lightCard,
      child: Row(
        children: [
          ...[0, 1, 2].map((s) {
            final label = ['Basic Info', 'Features', 'Review'][s];
            final isActive = s == _currentStep;
            final isDone = s < _currentStep;
            return Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone || isActive
                                ? AppColors.primary
                                : (isDark
                                    ? AppColors.dividerDark
                                    : AppColors.dividerLight),
                          ),
                          child: Center(
                            child: isDone
                                ? const Icon(Icons.check_rounded,
                                    size: 14, color: Colors.white)
                                : Text(
                                    '${s + 1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isActive
                                          ? Colors.white
                                          : (isDark
                                              ? AppColors.textOnDarkSecondary
                                              : AppColors.textMuted),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isActive
                                ? AppColors.primary
                                : (isDark
                                    ? AppColors.textOnDarkSecondary
                                    : AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (s < 2)
                    Container(
                      width: 20,
                      height: 1,
                      color: isDark
                          ? AppColors.dividerDark
                          : AppColors.dividerLight,
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStepContent(bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildStep1(isDark);
      case 1:
        return _buildStep2(isDark);
      case 2:
        return _buildStep3(isDark);
      default:
        return const SizedBox();
    }
  }

  Widget _buildStep1(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Cluster Name *', isDark),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameController,
              decoration: _inputDecoration('e.g. Master Driver A', isDark),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),
            _label('Description', isDark),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descController,
              decoration: _inputDecoration('Optional description', isDark),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            _label('Route', isDark),
            const SizedBox(height: 6),
            TextFormField(
              controller: _routeController,
              decoration: _inputDecoration(
                  'e.g. Kozhikode → Sulthan Bathery', isDark),
            ),
            const SizedBox(height: 16),
            _label('Vehicle Type', isDark),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _vehicleTypes.map((type) {
                final selected = _vehicleType == type;
                return GestureDetector(
                  onTap: () => setState(() => _vehicleType = type),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkCard
                              : AppColors.lightCard),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.dividerDark
                                : AppColors.dividerLight),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          vehicleTypeIcon(type),
                          size: 20,
                          color: selected
                              ? Colors.white
                              : (isDark
                                  ? AppColors.textOnDarkSecondary
                                  : AppColors.textSecondary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          type,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: selected
                                ? Colors.white
                                : (isDark
                                    ? AppColors.textOnDark
                                    : AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppConstants.terrainPlain,
        AppConstants.terrainUphill,
        AppConstants.terrainDownhill,
      ].map((terrain) {
        final entries = _featuresByTerrain[terrain]!;
        return _TerrainSection(
          terrain: terrain,
          entries: entries,
          isDark: isDark,
          onAddFeature: () => _showAddFeatureSheet(terrain, isDark),
          onRemoveFeature: (i) {
            setState(() => entries.removeAt(i));
          },
        );
      }).toList(),
    );
  }

  Widget _buildStep3(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Review your cluster', isDark),
          const SizedBox(height: 16),
          _ReviewCard(
            label: 'Name',
            value: _nameController.text.trim(),
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _ReviewCard(
            label: 'Vehicle Type',
            value: _vehicleType,
            isDark: isDark,
          ),
          if (_routeController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ReviewCard(
              label: 'Route',
              value: _routeController.text.trim(),
              isDark: isDark,
            ),
          ],
          const SizedBox(height: 16),
          for (final terrain in _featuresByTerrain.keys) ...[
            _label('$terrain features', isDark),
            const SizedBox(height: 6),
            if (_featuresByTerrain[terrain]!.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'No features added',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                ),
              )
            else
              ...(_featuresByTerrain[terrain]!.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${FeatureDisplayUtils.getDisplayName(e.featureName)}:  '
                      '${e.minController.text} – ${e.maxController.text}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.textOnDark
                            : AppColors.textPrimary,
                      ),
                    ),
                  ))),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildNavButtons(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: isDark ? AppColors.darkCard : AppColors.lightCard,
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep--),
                child: const Text('Back'),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _saving ? null : _onNextOrSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _currentStep == 2 ? 'Save Cluster' : 'Next',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _onNextOrSave() {
    if (_currentStep == 0) {
      if (_formKey.currentState!.validate()) {
        setState(() => _currentStep = 1);
      }
    } else if (_currentStep == 1) {
      setState(() => _currentStep = 2);
    } else {
      _save();
    }
  }

  Future<void> _showAddFeatureSheet(String terrain, bool isDark) async {
    final allKeys = FeatureDisplayUtils.allFeatureKeys;
    final alreadyAdded = _featuresByTerrain[terrain]!
        .map((e) => e.featureName)
        .toSet();
    final available = allKeys.where((k) => !alreadyAdded.contains(k)).toList();

    String? selected;
    final minCtrl = TextEditingController();
    final maxCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    List<String> filtered = List.from(available);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Feature — $terrain',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search features...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                    onChanged: (q) {
                      setModal(() {
                        filtered = available
                            .where((k) =>
                                FeatureDisplayUtils.getDisplayName(k)
                                    .toLowerCase()
                                    .contains(q.toLowerCase()))
                            .toList();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final key = filtered[i];
                        final isSelected = selected == key;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          title: Text(
                            FeatureDisplayUtils.getDisplayName(key),
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_rounded,
                                  color: AppColors.primary)
                              : null,
                          onTap: () => setModal(() => selected = key),
                        );
                      },
                    ),
                  ),
                  if (selected != null) ...[
                    const Divider(),
                    Text(
                      'Range for ${FeatureDisplayUtils.getDisplayName(selected!)}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Min value',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Max value',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (selected != null) {
                            setState(() {
                              _featuresByTerrain[terrain]!.add(
                                _FeatureEntry(
                                  featureName: selected!,
                                  minController: TextEditingController(
                                      text: minCtrl.text),
                                  maxController: TextEditingController(
                                      text: maxCtrl.text),
                                ),
                              );
                            });
                            Navigator.of(ctx).pop();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Add Feature'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _label(String text, bool isDark) => Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
        ),
      );

  InputDecoration _inputDecoration(String hint, bool isDark) =>
      InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}

class _FeatureEntry {
  final String featureName;
  final TextEditingController minController;
  final TextEditingController maxController;
  final int? existingId;

  _FeatureEntry({
    required this.featureName,
    required this.minController,
    required this.maxController,
    this.existingId,
  });
}

class _TerrainSection extends StatefulWidget {
  final String terrain;
  final List<_FeatureEntry> entries;
  final bool isDark;
  final VoidCallback onAddFeature;
  final void Function(int index) onRemoveFeature;

  const _TerrainSection({
    required this.terrain,
    required this.entries,
    required this.isDark,
    required this.onAddFeature,
    required this.onRemoveFeature,
  });

  @override
  State<_TerrainSection> createState() => _TerrainSectionState();
}

class _TerrainSectionState extends State<_TerrainSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.terrainColor(widget.terrain);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDark
              ? AppColors.dividerDark
              : AppColors.dividerLight,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(Icons.terrain_rounded, color: color, size: 20),
            title: Text(
              widget.terrain,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.entries.length} features',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: widget.isDark
                      ? AppColors.textOnDarkSecondary
                      : AppColors.textMuted,
                ),
              ],
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (widget.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No features added. Tap below to add.',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: widget.isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                ),
              )
            else
              ...widget.entries.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          FeatureDisplayUtils.getDisplayName(e.featureName),
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.isDark
                                ? AppColors.textOnDark
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                          controller: e.minController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Min',
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                          controller: e.maxController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Max',
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 18,
                          color: AppColors.alert.withOpacity(0.8),
                        ),
                        onPressed: () => widget.onRemoveFeature(i),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onAddFeature,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Feature'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _ReviewCard({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
