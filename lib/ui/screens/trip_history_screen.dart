import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/trip_provider.dart';
import '../../models/trip_model.dart';
import '../../analytics/score_calculator.dart';
import '../widgets/summary_card.dart';
import '../widgets/terrain_badge.dart';
import '../theme/app_colors.dart';
import 'coaching_report_screen.dart';

/// Trip History Screen — list of all completed trips.
///
/// Shows each trip with overall deviation, cluster matching,
/// terrain distribution chips, and tap to view summary.
class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  List<TripSummary> _trips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    final provider = context.read<TripProvider>();
    final trips = await provider.getTripHistory();
    if (mounted) {
      setState(() {
        _trips = trips;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip History'),
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
                : _buildTripList(isDark),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.directions_bus_outlined,
            size: 64,
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'No trips recorded yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a trip from the home screen',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripList(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadTrips,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _trips.length,
        itemBuilder: (context, index) {
          final trip = _trips[index];
          return _TripCard(
            trip: trip,
            isDark: isDark,
            onDelete: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Trip?'),
                  content: const Text(
                    'This will permanently delete all trip data including segments and features.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.alert,
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await context.read<TripProvider>().deleteTrip(trip.tripId);
                _loadTrips();
              }
            },
          );
        },
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final TripSummary trip;
  final bool isDark;
  final VoidCallback onDelete;

  const _TripCard({
    required this.trip,
    required this.isDark,
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
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CoachingReportScreen(tripId: trip.tripId),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Header row ──────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _InlineScoreBadge(
                          score: trip.score >= 0
                              ? trip.score.round()
                              : ScoreCalculator.computeScore(
                                  trip.overallAvgDeviation),
                        ),
                        const SizedBox(width: 10),
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
                const SizedBox(height: 12),

                // ─── Stats row ───────────────────────────────────────
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

class _InlineScoreBadge extends StatelessWidget {
  final int score;
  const _InlineScoreBadge({required this.score});

  Color get _color {
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 50) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color.withOpacity(0.12),
        border: Border.all(color: _color, width: 2),
      ),
      child: Center(
        child: Text(
          '$score',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: _color,
          ),
        ),
      ),
    );
  }
}
