import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../database/db_helper.dart';
import '../../models/trip_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../../services/csv_export_service.dart';
import '../../utils/landmark_utils.dart';
import '../theme/app_colors.dart';
import '../widgets/big_speed_display.dart';
import '../widgets/buttons.dart';
import '../widgets/map_widget.dart';
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
    final serviceEnabled = await _ensureLocationServiceEnabledForCollectionStart();
    if (!serviceEnabled || !mounted) return;

    setState(() => _starting = true);
    await context.read<TripProvider>().startCollectionTrip(_segmentDistanceM);
    if (!mounted) return;
    setState(() => _starting = false);
  }

  Future<bool> _ensureLocationServiceEnabledForCollectionStart() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (serviceEnabled) return true;

    if (!mounted) return false;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return AlertDialog(
        title: Text(l10n.locationServiceDisabled),
        content: Text(l10n.locationServiceMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('open_settings'),
            child: Text(l10n.openSettings),
          ),
        ],
      );
      },
    );

    if (action == 'open_settings') {
      await Geolocator.openLocationSettings();
    }

    return false;
  }

  Future<void> _stopCollection() async {
    await context.read<TripProvider>().stopCollectionTrip();
    await _loadInitialData();
  }

  Future<void> _exportTrip(String tripId) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _exportingTripId = tripId);
    try {
      final path = await _csvExportService.exportTripCSV(tripId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.csvSaved}: ksrtc_collection_$tripId.csv'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l10n.shareCSV,
            onPressed: () {
              Share.shareXFiles([XFile(path)]);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = _friendlyExportErrorMessage(l10n, e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingTripId = null);
      }
    }
  }

  String _friendlyExportErrorMessage(AppLocalizations l10n, String rawError) {
    final normalized = rawError.toLowerCase();
    if (normalized.contains('permission')) {
      return l10n.permissionDenied;
    }
    return l10n.exportFailed;
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showCollectionHelpSheet(AppLocalizations l10n, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dataCollectionHelpTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _FaqItem(
                  question: l10n.faqWhatRecordedQ,
                  answer: l10n.faqWhatRecordedA,
                  isDark: isDark,
                ),
                _FaqItem(
                  question: l10n.faqInternetQ,
                  answer: l10n.faqInternetA,
                  isDark: isDark,
                ),
                _FaqItem(
                  question: l10n.faqShareDataQ,
                  answer: l10n.faqShareDataA,
                  isDark: isDark,
                ),
                _FaqItem(
                  question: l10n.faqStorageQ,
                  answer: l10n.faqStorageA,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<TripProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final recording = provider.isCollectionMode && provider.state == TripState.recording;

    return recording
          ? _buildRecordingState(provider, isDark, l10n)
          : _buildIdleState(isDark, l10n);
  }

  Widget _buildIdleState(bool isDark, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.dataCollection,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
              ),
            ),
            IconButton(
              tooltip: l10n.help,
              onPressed: () => _showCollectionHelpSheet(l10n, isDark),
              icon: const Icon(Icons.help_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
                l10n.segmentDistance,
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
          label: l10n.startCollection,
          icon: Icons.play_arrow_rounded,
          color: AppColors.success,
          loading: _starting,
          onPressed: _starting ? null : _startCollection,
        ),
        const SizedBox(height: 22),
        Text(
          l10n.recentTrips,
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
              l10n.noTripsYet,
              style: TextStyle(
                color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
              ),
            ),
          )
        else
          ..._recentTrips.map((trip) {
          final dateText = _formatDateTime(trip.startTime);
          final totalDistanceKm =
            (trip.totalSegments * trip.segmentDistanceM) / 1000.0;
          final duration = (trip.endTime ?? trip.startTime)
            .difference(trip.startTime);
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
                    '${l10n.distance}: ${totalDistanceKm.toStringAsFixed(1)} km',
                    style: TextStyle(
                      color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.duration}: ${_formatDuration(duration)}',
                    style: TextStyle(
                      color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.segments}: ${trip.totalSegments}',
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
                      label: Text(l10n.exportCSV),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildRecordingState(
      TripProvider provider, bool isDark, AppLocalizations l10n) {
    final nearest = _nearestLandmarkLabel(provider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: l10n.help,
                onPressed: () => _showCollectionHelpSheet(l10n, isDark),
                icon: const Icon(Icons.help_outline_rounded),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
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
          const SizedBox(height: 12),
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MapWidget(
                latitude: provider.currentLat,
                longitude: provider.currentLon,
                trail: provider.gpsTrail,
                segmentMarkers: provider.segmentMarkers,
                zoom: 16.0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                        l10n.nearestLandmark,
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
                        '${l10n.segments}: ${provider.segmentsCompleted}',
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
                  label: l10n.stopCollection,
                  icon: Icons.stop_rounded,
                  color: AppColors.alert,
                  onPressed:
                      provider.state == TripState.recording ? _stopCollection : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;
  final bool isDark;

  const _FaqItem({
    required this.question,
    required this.answer,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            answer,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
