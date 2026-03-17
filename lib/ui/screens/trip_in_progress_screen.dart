import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../widgets/map_widget.dart';
import '../widgets/big_speed_display.dart';
import '../widgets/terrain_badge.dart';
import '../widgets/stat_card.dart';
import '../widgets/buttons.dart';
import '../theme/app_colors.dart';
import 'trip_summary_screen.dart';

/// Trip In Progress Screen — THE most important screen.
///
/// Layout:
///   Top: Map (60%+ height)
///   Middle: Large speed display, terrain badge
///   Bottom overlay: Deviation, elapsed time, distance
///   Bottom buttons: Pause, Stop Trip
///
/// UI refresh capped at 1 Hz despite 10 Hz sensor data.
class TripInProgressScreen extends StatefulWidget {
  const TripInProgressScreen({super.key});

  @override
  State<TripInProgressScreen> createState() => _TripInProgressScreenState();
}

class _TripInProgressScreenState extends State<TripInProgressScreen> {
  Timer? _elapsedTimer;
  Timer? _sessionTimer;
  DateTime? _tripStartTime;
  Duration _elapsed = Duration.zero;
  bool _navigatedToSummary = false;

  @override
  void initState() {
    super.initState();
    _tripStartTime = DateTime.now();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(_tripStartTime!);
        });
      }
    });
    // Update activity every minute during trip (keeps session alive)
    _sessionTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      context.read<AuthProvider>().updateActivity();
    });
    // Mark activity at trip start
    context.read<AuthProvider>().updateActivity();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _sessionTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final distanceKm = provider.currentDistance / 1000.0;

    // Handle trip completion — navigate to summary
    if (provider.state == TripState.completed && !_navigatedToSummary) {
      _navigatedToSummary = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const TripSummaryScreen(),
          ),
          (route) => route.settings.name == '/home' || route.isFirst,
        );
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ─── Map (60%+) ──────────────────────────────────────────
            Expanded(
              flex: 6,
              child: Stack(
                children: [
                  MapWidget(
                    latitude: provider.currentLat,
                    longitude: provider.currentLon,
                    trail: provider.gpsTrail,
                    segmentMarkers: provider.segmentMarkers,
                    zoom: 16.0,
                  ),

                  // ─── Recording indicator ─────────────────────────────
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: provider.state == TripState.recording
                            ? AppColors.alert
                            : AppColors.warning,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            provider.state == TripState.recording
                                ? 'RECORDING'
                                : 'PROCESSING...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ─── Segment count ───────────────────────────────────
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (isDark ? AppColors.darkCard : Colors.white)
                            .withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? AppColors.dividerDark
                              : AppColors.dividerLight,
                        ),
                      ),
                      child: Text(
                        '${provider.segmentsCompleted} segments',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textOnDark
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ─── Bottom Panel ────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ─── Speed + Terrain ──────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        BigSpeedDisplay(
                          speedMs: provider.currentSpeed,
                          compact: false,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            TerrainBadge(
                              terrain: provider.currentTerrain,
                              large: true,
                            ),
                            if (provider.lastMatchedCluster >= 0) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Cluster ${provider.lastMatchedCluster}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Stats Row ───────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: 'Distance',
                            value: distanceKm.toStringAsFixed(1),
                            unit: 'km',
                            icon: Icons.straighten_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatCard(
                            label: 'Elapsed',
                            value: _formatDuration(_elapsed),
                            icon: Icons.timer_outlined,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatCard(
                            label: 'Deviation',
                            value: provider.lastDeviation > 0
                                ? provider.lastDeviation.toStringAsFixed(1)
                                : '—',
                            icon: Icons.analytics_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Stop Button ─────────────────────────────────
                    PrimaryButton(
                      label: 'Stop Trip',
                      icon: Icons.stop_rounded,
                      color: AppColors.alert,
                      loading: provider.state == TripState.processing,
                      onPressed: provider.state == TripState.recording
                          ? () async {
                              await provider.stopTrip();
                            }
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
