import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/trip_model.dart';
import '../../providers/trip_provider.dart';
import '../../services/csv_export_service.dart';
import '../../services/firebase_sync_service.dart';
import '../theme/app_colors.dart';
import 'data_viewer_screen.dart';

class AdminCollectionScreen extends StatefulWidget {
  const AdminCollectionScreen({super.key});

  @override
  State<AdminCollectionScreen> createState() => _AdminCollectionScreenState();
}

class _AdminCollectionScreenState extends State<AdminCollectionScreen> {
  final CsvExportService _csvExportService = CsvExportService();
  bool _loading = true;
  bool _exportingAll = false;
  String? _exportingTripId;
  List<DataCollectionTrip> _trips = [];

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    try {
      // Firestore-authoritative read with local reconciliation: if a trip
      // exists locally but was deleted from Firestore, it is re-synced (or
      // queued) rather than shown as a stale local-only entry.
      final trips = await context
          .read<TripProvider>()
          .getAllDataCollectionTripsReconciled();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _loading = false;
      });
    } catch (e) {
      // Fallback to local database when Firestore is not available
      try {
        final localTrips = await context.read<TripProvider>().getAllDataCollectionTrips();
        if (!mounted) return;
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
      } catch (e2) {
        if (!mounted) return;
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

  String _formatDuration(DataCollectionTrip trip) {
    if (trip.endTime == null) return 'In progress';
    final d = trip.endTime!.difference(trip.startTime);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }

  Future<void> _exportTrip(String tripId) async {
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
        const SnackBar(
          content: Text(
            'Could not save the file. Please check your storage space and try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingTripId = null);
      }
    }
  }

  Future<void> _confirmDelete(DataCollectionTrip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Trip?'),
        content: const Text(
          'This will permanently delete all data for this collection trip including segments and raw data.',
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
    if (confirmed == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deleting trip...'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final success = await FirebaseSyncService.instance
          .deletePublishedCollectionTrip(trip.tripId);

      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip deleted successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadTrips(); // Reload the trip list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete trip'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _exportAll() async {
    setState(() => _exportingAll = true);
    try {
      final path = await _csvExportService.exportAllCollectionCSV();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Combined CSV saved to: $path'),
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
        const SnackBar(
          content: Text(
            'Could not save the file. Please check your storage space and try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingAll = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Collection Trips'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _exportingAll ? null : _exportAll,
                        icon: _exportingAll
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.file_download_rounded),
                        label: const Text('Export All'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadTrips,
                      child: _trips.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 120),
                              Center(
                                child: Text(
                                  'No data collection trips found',
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.textOnDarkSecondary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _trips.length,
                            itemBuilder: (context, index) {
                              final trip = _trips[index];
                              final dt = trip.startTime;
                              final dateText =
                                  '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                padding: const EdgeInsets.all(14),
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
                                    Text(
                                      '${trip.driverUsername.isEmpty ? 'Unknown' : trip.driverUsername} • ${trip.busNumber.isEmpty ? 'No bus' : trip.busNumber}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$dateText • ${trip.totalSegments} segments',
                                      style: TextStyle(
                                        color: isDark
                                            ? AppColors.textOnDarkSecondary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Segment distance: ${trip.segmentDistanceM.toStringAsFixed(0)}m • Duration: ${_formatDuration(trip)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? AppColors.textOnDarkSecondary
                                            : AppColors.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        alignment: WrapAlignment.end,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () => Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => DataViewerScreen(
                                                  tripId: trip.tripId,
                                                  title: '${trip.driverUsername.isEmpty ? 'Unknown' : trip.driverUsername} — ${dateText}',
                                                ),
                                              ),
                                            ),
                                            icon: const Icon(Icons.table_chart_rounded, size: 16),
                                            label: const Text('View Data'),
                                          ),
                                          TextButton.icon(
                                            onPressed: _exportingTripId == trip.tripId
                                                ? null
                                                : () => _exportTrip(trip.tripId),
                                            icon: _exportingTripId == trip.tripId
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                : const Icon(Icons.download_rounded, size: 16),
                                            label: const Text('Export CSV'),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20,
                                              color: AppColors.alert.withOpacity(0.7),
                                            ),
                                            onPressed: () => _confirmDelete(trip),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
