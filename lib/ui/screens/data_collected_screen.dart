import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../database/db_helper.dart';
import '../../models/trip_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/csv_export_service.dart';
import '../theme/app_colors.dart';
import 'data_viewer_screen.dart';

class DataCollectedScreen extends StatefulWidget {
  final bool embedded;

  const DataCollectedScreen({super.key, this.embedded = false});

  @override
  State<DataCollectedScreen> createState() => _DataCollectedScreenState();
}

class _DataCollectedScreenState extends State<DataCollectedScreen> {
  final DbHelper _db = DbHelper();
  final CsvExportService _csvExportService = CsvExportService();
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  bool _loading = true;
  String? _exportingTripId;
  List<DataCollectionTrip> _trips = [];

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    final userId = context.read<AuthProvider>().currentUser?['id'] as int? ?? 0;
    final trips = await _db.getDataCollectionTripsForUser(userId);
    if (!mounted) return;
    setState(() {
      _trips = trips;
      _loading = false;
    });
  }

  Future<void> _exportTripCsv(String tripId) async {
    setState(() => _exportingTripId = tripId);
    try {
      final path = await _csvExportService.exportCollectionTripCSV(tripId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV saved to: $path'),
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
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingTripId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Data Collected'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _trips.isEmpty
                ? _buildEmptyState(isDark)
                : RefreshIndicator(
                    onRefresh: _loadTrips,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _trips.length,
                      itemBuilder: (context, index) {
                        final trip = _trips[index];
                        return _DataCollectedCard(
                          trip: trip,
                          isDark: isDark,
                          dateTimeFormat: _dateTimeFormat,
                          exporting: _exportingTripId == trip.tripId,
                          onExportCsv: () => _exportTripCsv(trip.tripId),
                          onViewData: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DataViewerScreen(
                                  tripId: trip.tripId,
                                  title: 'Data Collected',
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 68,
              color: isDark ? AppColors.textOnDarkSecondary : AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'No data collected yet. Go to Data Collection to start recording.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataCollectedCard extends StatelessWidget {
  final DataCollectionTrip trip;
  final bool isDark;
  final DateFormat dateTimeFormat;
  final bool exporting;
  final VoidCallback onExportCsv;
  final VoidCallback onViewData;

  const _DataCollectedCard({
    required this.trip,
    required this.isDark,
    required this.dateTimeFormat,
    required this.exporting,
    required this.onExportCsv,
    required this.onViewData,
  });

  @override
  Widget build(BuildContext context) {
    final duration = trip.endTime?.difference(trip.startTime) ?? Duration.zero;
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    final vehicleType = trip.vehicleType.isEmpty ? 'Unknown' : trip.vehicleType;
    final dateTimeText = dateTimeFormat.format(trip.startTime);
    final distanceText = '${((trip.totalSegments * trip.segmentDistanceM) / 1000.0).toStringAsFixed(1)} km';
    final durationText = '${minutes}m ${seconds}s';

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
          Text(
            dateTimeText,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _InfoChip(label: 'Vehicle', value: vehicleType, isDark: isDark),
              _InfoChip(label: 'Distance', value: distanceText, isDark: isDark),
              _InfoChip(label: 'Duration', value: durationText, isDark: isDark),
              _InfoChip(label: 'Segments', value: '${trip.totalSegments}', isDark: isDark),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
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
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onViewData,
                  icon: const Icon(Icons.visibility_rounded, size: 16),
                  label: const Text('View Data'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.textOnDarkSecondary : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}