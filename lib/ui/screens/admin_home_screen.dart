import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../../models/trip_model.dart';
import '../../services/csv_export_service.dart';
import '../../services/firebase_sync_service.dart';
import '../theme/app_colors.dart';
import 'threshold_editor_screen.dart';
import 'driver_management_screen.dart';
import 'cluster_management_screen.dart';
import 'data_viewer_screen.dart';
import 'trip_history_screen.dart';

/// Admin Home Screen — dashboard for admin users.
///
/// Management + trip overview dashboard for admin users.
/// Logout button in AppBar.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  List<DataCollectionTrip> _trips = [];
  bool _loading = true;
  String? _exportingTripId;
  bool _exportingAll = false;
  final CsvExportService _csvExportService = CsvExportService();

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    try {
      // Firestore-authoritative read with local reconciliation (see
      // TripProvider.getAllDataCollectionTripsReconciled). Prevents stale
      // local-only trips from lingering after a manual Firestore delete.
      final trips = await context
          .read<TripProvider>()
          .getAllDataCollectionTripsReconciled();
      if (mounted) {
        setState(() {
          _trips = trips;
          _loading = false;
        });
      }
    } catch (e) {
      // Fallback to local database when Firestore is not available
      try {
        final localTrips = await context.read<TripProvider>().getAllDataCollectionTrips();
        if (mounted) {
          setState(() {
            _trips = localTrips;
            _loading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Showing collection trips from local database'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e2) {
        if (mounted) {
          setState(() {
            _trips = [];
            _loading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading collection trips: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _exportTripCsv(String tripId) async {
    setState(() => _exportingTripId = tripId);
    try {
      final normalizedTripId = tripId.trim();
      if (normalizedTripId.isEmpty) {
        throw Exception('Invalid trip ID for export');
      }

      final path = await _csvExportService.exportCollectionTripCSV(tripId);
      final exportedFile = XFile(path);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV saved to: $path'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Share',
            onPressed: () => Share.shareXFiles([exportedFile]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingTripId = null);
      }
    }
  }

  Future<void> _exportAllAsZip() async {
    setState(() => _exportingAll = true);
    try {
      final path = await _csvExportService.exportAllCollectionTripsAsZip();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ZIP file saved to: $path'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Share',
            onPressed: () => Share.shareXFiles([XFile(path)]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingAll = false);
      }
    }
  }

  Future<void> _confirmDeleteCollection(DataCollectionTrip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Collection Trip?'),
        content: const Text(
          'This will permanently delete all data for this collection trip including segments and sensor data.',
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
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deleting collection trip...'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      try {
        final success = await FirebaseSyncService.instance
            .deletePublishedCollectionTrip(trip.tripId);

        if (!mounted) return;
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Collection trip deleted successfully'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _loadTrips();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete collection trip'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete error: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _logout() {
    context.read<AuthProvider>().logout();
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadTrips,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
            // ─── Management Cards ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.7,
                children: [
                  _AdminActionCard(
                    icon: Icons.tune_rounded,
                    label: 'Threshold\nSettings',
                    color: AppColors.terrainUphill,
                    isDark: isDark,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ThresholdEditorScreen(),
                        ),
                      );
                    },
                  ),
                  _AdminActionCard(
                    icon: Icons.people_rounded,
                    label: 'Driver\nManagement',
                    color: AppColors.terrainDownhill,
                    isDark: isDark,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DriverManagementScreen(),
                        ),
                      );
                    },
                  ),
                  _AdminActionCard(
                    icon: Icons.track_changes_rounded,
                    label: 'Benchmarking\nTrips',
                    color: AppColors.success,
                    isDark: isDark,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TripHistoryScreen(),
                        ),
                      );
                    },
                  ),
                  _AdminActionCard(
                    icon: Icons.group_work_rounded,
                    label: 'Clusters',
                    color: AppColors.warning,
                    isDark: isDark,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ClusterManagementScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── Data Collection Header ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.dataset_rounded,
                    size: 20,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Collected Data',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textOnDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_trips.length} collections',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (!_loading && _trips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _exportingAll ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
                    label: Text(_exportingAll ? 'Exporting...' : 'Export All as ZIP'),
                    onPressed: _exportingAll ? null : _exportAllAsZip,
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // ─── Trip List ───────────────────────────────────────────
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_trips.isEmpty)
              _buildEmptyTrips(isDark)
            else
              ..._trips.map((trip) => _AdminCollectionCard(
                    trip: trip,
                    isDark: isDark,
                    exporting: _exportingTripId == trip.tripId,
                    onExportCsv: () => _exportTripCsv(trip.tripId),
                    onDelete: () => _confirmDeleteCollection(trip),
                    onViewData: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DataViewerScreen(
                            tripId: trip.tripId,
                            title:
                                '${trip.driverUsername.isEmpty ? 'Unknown' : trip.driverUsername} — ${trip.startTime.day}/${trip.startTime.month}/${trip.startTime.year}',
                          ),
                        ),
                      );
                    },
                  )),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildEmptyTrips(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.dataset_outlined,
              size: 56,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'No collection trips yet',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? AppColors.textOnDarkSecondary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }


}

// ═══════════════════════════════════════════════════════════════════════
// Admin Action Card (Threshold / Driver Management)
// ═══════════════════════════════════════════════════════════════════════

class _AdminActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _AdminActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textOnDark
                              : AppColors.textPrimary,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Admin Trip Card
// ═══════════════════════════════════════════════════════════════════════

class _AdminTripCard extends StatelessWidget {
  final TripSummary trip;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onExportCsv;
  final bool exporting;
  final VoidCallback onDelete;

  const _AdminTripCard({
    required this.trip,
    required this.isDark,
    required this.onTap,
    required this.onExportCsv,
    required this.exporting,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final duration = trip.endTime.difference(trip.startTime);
    final dateStr =
        '${trip.startTime.day}/${trip.startTime.month}/${trip.startTime.year}';
    final timeStr =
        '${trip.startTime.hour.toString().padLeft(2, '0')}:${trip.startTime.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Header ──────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.directions_bus_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.textOnDark
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? AppColors.textOnDarkSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: AppColors.alert.withOpacity(0.7),
                      ),
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),
                  ],
                ),

                // ─── Driver Info ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 14,
                        color: isDark
                            ? AppColors.textOnDarkSecondary
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        trip.driverName.isNotEmpty
                            ? trip.driverName
                            : 'Unknown Driver',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.textOnDarkSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.confirmation_number_outlined,
                        size: 14,
                        color: isDark
                            ? AppColors.textOnDarkSecondary
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        trip.busNumber.isNotEmpty
                            ? trip.busNumber
                            : 'Bus: Not assigned',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: trip.busNumber.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                          color: isDark
                              ? AppColors.textOnDarkSecondary
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                // ─── Stats ───────────────────────────────────────────
                Row(
                  children: [
                    _MiniStat(
                      'Deviation',
                      trip.overallAvgDeviation.toStringAsFixed(2),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 16),
                    _MiniStat(
                      'Segments',
                      '${trip.validSegments}',
                      isDark: isDark,
                    ),
                    const SizedBox(width: 16),
                    _MiniStat(
                      'Duration',
                      _formatDuration(duration),
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ─── Terrain chips ───────────────────────────────────
                Row(
                  children: [
                    if (trip.plainSegments > 0)
                      _TerrainChip('Plain', trip.plainSegments),
                    if (trip.uphillSegments > 0) ...[
                      const SizedBox(width: 6),
                      _TerrainChip('Uphill', trip.uphillSegments),
                    ],
                    if (trip.downhillSegments > 0) ...[
                      const SizedBox(width: 6),
                      _TerrainChip('Downhill', trip.downhillSegments),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: exporting ? null : onExportCsv,
                    icon: exporting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Export CSV'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _MiniStat(this.label, this.value, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _TerrainChip extends StatelessWidget {
  final String terrain;
  final int count;

  const _TerrainChip(this.terrain, this.count);

  @override
  Widget build(BuildContext context) {
    final color = AppColors.terrainColor(terrain);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.terrainBgColor(terrain),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$terrain · $count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Admin Collection Trip Card
// ═══════════════════════════════════════════════════════════════════════

class _AdminCollectionCard extends StatelessWidget {
  final DataCollectionTrip trip;
  final bool isDark;
  final bool exporting;
  final VoidCallback onExportCsv;
  final VoidCallback onDelete;
  final VoidCallback onViewData;

  const _AdminCollectionCard({
    required this.trip,
    required this.isDark,
    required this.exporting,
    required this.onExportCsv,
    required this.onDelete,
    required this.onViewData,
  });

  @override
  Widget build(BuildContext context) {
    final dateTimeText =
        '${trip.startTime.day}/${trip.startTime.month}/${trip.startTime.year} ${trip.startTime.hour.toString().padLeft(2, '0')}:${trip.startTime.minute.toString().padLeft(2, '0')}';
    final duration = trip.endTime?.difference(trip.startTime) ?? Duration.zero;
    final durationText = '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    final driverText = trip.driverUsername.isEmpty ? 'driver' : trip.driverUsername;
    final busText = trip.busNumber.isEmpty ? 'No bus' : trip.busNumber;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '$driverText • $busText',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.alert.withOpacity(0.8),
                ),
                tooltip: 'Delete collection trip',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$dateTimeText • ${trip.totalSegments} segments',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Segment distance: ${trip.segmentDistanceM.toStringAsFixed(0)}m • Duration: $durationText',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.textOnDarkSecondary : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: onViewData,
                icon: const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text('View Data'),
              ),
              TextButton.icon(
                onPressed: exporting ? null : onExportCsv,
                icon: exporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 16),
                label: const Text('Export CSV'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
