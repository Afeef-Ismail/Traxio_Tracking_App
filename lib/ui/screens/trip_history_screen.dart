import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../providers/trip_provider.dart';
import '../../models/trip_model.dart';
import '../../analytics/score_calculator.dart';
import '../../services/csv_export_service.dart';
import '../theme/app_colors.dart';
import 'coaching_report_screen.dart';

/// Trip History Screen — list of all completed trips.
///
/// Shows each trip with overall deviation, cluster matching,
/// terrain distribution chips, and tap to view summary.
class TripHistoryScreen extends StatefulWidget {
  final bool embedded;

  const TripHistoryScreen({super.key, this.embedded = false});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  List<TripSummary> _trips = [];
  bool _loading = true;
  final CsvExportService _csvExportService = CsvExportService();
  String? _exportingTripId;

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

  Future<void> _exportTripCsv(String tripId) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _exportingTripId = tripId);
    try {
      final path = await _csvExportService.exportBenchmarkTripCSV(tripId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.csvSaved}: $path'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l10n.shareCSV,
            onPressed: () => Share.shareXFiles([XFile(path)]),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(l10n.tripHistory),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _trips.isEmpty
                ? _buildEmptyState(isDark, l10n)
                : _buildTripList(isDark, l10n),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, AppLocalizations l10n) {
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
            l10n.noTripsYet,
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
            l10n.startFromHome,
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

  Widget _buildTripList(bool isDark, AppLocalizations l10n) {
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
            exporting: _exportingTripId == trip.tripId,
            onExportCsv: () => _exportTripCsv(trip.tripId),
            l10n: l10n,
          );
        },
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final TripSummary trip;
  final bool isDark;
  final VoidCallback onExportCsv;
  final bool exporting;
  final AppLocalizations l10n;

  const _TripCard({
    required this.trip,
    required this.isDark,
    required this.onExportCsv,
    required this.exporting,
    required this.l10n,
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
                  ],
                ),
                const SizedBox(height: 12),

                // ─── Stats row ───────────────────────────────────────
                Row(
                  children: [
                    _MiniStat(
                      l10n.deviation,
                      trip.overallAvgDeviation.toStringAsFixed(2),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 16),
                    _MiniStat(
                      l10n.segments,
                      '${trip.validSegments}',
                      isDark: isDark,
                    ),
                    const SizedBox(width: 16),
                    _MiniStat(
                      l10n.duration,
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
                      _TerrainChip(l10n.plain, trip.plainSegments),
                    if (trip.uphillSegments > 0) ...[
                      const SizedBox(width: 6),
                      _TerrainChip(l10n.uphill, trip.uphillSegments),
                    ],
                    if (trip.downhillSegments > 0) ...[
                      const SizedBox(width: 6),
                      _TerrainChip(l10n.downhill, trip.downhillSegments),
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
                    label: Text(l10n.exportCSV),
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
