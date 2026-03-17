import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/trip_model.dart';
import '../../providers/trip_provider.dart';
import '../../services/csv_export_service.dart';
import '../theme/app_colors.dart';

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
    final trips = await context.read<TripProvider>().getAllDataCollectionTrips();
    if (!mounted) return;
    setState(() {
      _trips = trips;
      _loading = false;
    });
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
      final path = await _csvExportService.exportTripCSV(tripId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV saved to Downloads: ksrtc_collection_$tripId.csv'),
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
          content: Text('Export failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingTripId = null);
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
          content: const Text('Combined CSV saved to Downloads'),
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
          content: Text('Export failed: $e'),
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
                    child: _trips.isEmpty
                        ? Center(
                            child: Text(
                              'No data collection trips found',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.textOnDarkSecondary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          )
                        : ListView.builder(
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
                                      child: TextButton.icon(
                                        onPressed: _exportingTripId == trip.tripId
                                            ? null
                                            : () => _exportTrip(trip.tripId),
                                        icon: _exportingTripId == trip.tripId
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.download_rounded),
                                        label: const Text('Export CSV'),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
