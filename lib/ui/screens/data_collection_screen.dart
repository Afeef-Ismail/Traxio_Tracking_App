import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../database/db_helper.dart';
import '../../models/trip_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../../services/csv_export_service.dart';
import '../../utils/landmark_utils.dart';
import '../theme/app_colors.dart';
import '../widgets/big_speed_display.dart';
import '../widgets/buttons.dart';
import '../widgets/terrain_badge.dart';

class DataCollectionScreen extends StatefulWidget {
  const DataCollectionScreen({super.key});

  @override
  State<DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<DataCollectionScreen> {
  final DbHelper _db = DbHelper();
  final CsvExportService _csvExportService = CsvExportService();

  double _segmentDistanceM = 100.0;
  bool _loading = true;
  bool _starting = false;
  String? _exportingTripId;
  List<DataCollectionTrip> _recentTrips = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final auth = context.read<AuthProvider>();
    final tripProvider = context.read<TripProvider>();
    final userId = auth.currentUser?['id'] as int? ?? 0;

    final configured = await _db.getConfig('collection_segment_distance_m');
    final parsed = double.tryParse(configured ?? '100.0') ?? 100.0;

    final trips = await tripProvider.getDataCollectionTripsForUser(userId);
    if (!mounted) return;

    setState(() {
      _segmentDistanceM = _normalizeDistance(parsed);
      _recentTrips = trips.take(5).toList();
      _loading = false;
    });
  }

  double _normalizeDistance(double value) {
    final clamped = value.clamp(50.0, 500.0).toDouble();
    final stepped = (clamped / 10).round() * 10;
    return stepped.toDouble();
  }

  String _nearestLandmarkLabel(TripProvider provider) {
    final lat = provider.currentLat;
    final lon = provider.currentLon;
    if (lat == null || lon == null) return '—';

    final nearest = LandmarkUtils.getNearestLandmark(lat, lon);
    if (nearest == 'NH-766') {
      final ns = lat >= 0 ? 'N' : 'S';
      final ew = lon >= 0 ? 'E' : 'W';
      return '${lat.abs().toStringAsFixed(4)}°$ns, ${lon.abs().toStringAsFixed(4)}°$ew';
    }
    return nearest;
  }

  Future<void> _startCollection() async {
    setState(() => _starting = true);
    await context.read<TripProvider>().startCollectionTrip(_segmentDistanceM);
    if (!mounted) return;
    setState(() => _starting = false);
  }

  Future<void> _stopCollection() async {
    await context.read<TripProvider>().stopCollectionTrip();
    await _loadInitialData();
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
            onPressed: () {
              Share.shareXFiles([XFile(path)]);
            },
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final recording = provider.isCollectionMode && provider.state == TripState.recording;

    return recording
        ? _buildRecordingState(provider, isDark)
        : _buildIdleState(isDark);
  }

  Widget _buildIdleState(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
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
              Text(
                'Segment Distance',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_segmentDistanceM.toInt()} m',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
                ),
              ),
              Slider(
                min: 50,
                max: 500,
                divisions: 45,
                value: _segmentDistanceM,
                label: '${_segmentDistanceM.toInt()} m',
                onChanged: (v) {
                  setState(() => _segmentDistanceM = _normalizeDistance(v));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: 'Start Data Collection',
          icon: Icons.play_arrow_rounded,
          color: AppColors.success,
          loading: _starting,
          onPressed: _starting ? null : _startCollection,
        ),
        const SizedBox(height: 22),
        Text(
          'Recent Collection Trips',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        if (_recentTrips.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
              ),
            ),
            child: Text(
              'No collection trips yet.',
              style: TextStyle(
                color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
              ),
            ),
          )
        else
          ..._recentTrips.map((trip) {
            final date = trip.startTime;
            final dateText =
                '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
            final route = trip.routeDescription.isEmpty ? 'Route not available' : trip.routeDescription;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
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
                    dateText,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${trip.totalSegments} segments • ${trip.segmentDistanceM.toStringAsFixed(0)}m',
                    style: TextStyle(
                      color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    route,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.textOnDarkSecondary : AppColors.textMuted,
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
          }),
      ],
    );
  }

  Widget _buildRecordingState(TripProvider provider, bool isDark) {
    final nearest = _nearestLandmarkLabel(provider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'DATA COLLECTION RECORDING',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BigSpeedDisplay(speedMs: provider.currentSpeed, compact: false),
              TerrainBadge(terrain: provider.currentTerrain, large: true),
            ],
          ),
          const SizedBox(height: 14),
          Container(
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
                  'Nearest Landmark',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textOnDarkSecondary : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nearest,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Segments: ${provider.segmentsCompleted}',
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          PrimaryButton(
            label: 'Stop Collection',
            icon: Icons.stop_rounded,
            color: AppColors.alert,
            onPressed: provider.state == TripState.recording ? _stopCollection : null,
          ),
        ],
      ),
    );
  }
}
