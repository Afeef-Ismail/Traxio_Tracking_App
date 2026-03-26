import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../database/db_helper.dart';
import '../../models/trip_model.dart';
import '../theme/app_colors.dart';
import '../widgets/trip_score_chart.dart';

/// Driver Profile — shows logged-in driver's stats and history summary.
class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final DbHelper _db = DbHelper();
  bool _loading = true;
  List<TripSummary> _trips = [];
  String _driverName = '';
  String _busNumber = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final userId = user['id'] as int;
    _driverName = user['username'] as String? ?? 'Driver';
    _busNumber = user['bus_number'] as String? ?? '';

    final trips = await _db.getTripSummariesForUser(userId);
    if (mounted) {
      setState(() {
        _trips = trips;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.driverProfile),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildProfileHeader(isDark),
                    const SizedBox(height: 20),
                    _buildStatsGrid(isDark, l10n),
                    const SizedBox(height: 20),
                    _buildScoreHistory(isDark),
                    const SizedBox(height: 20),
                    _buildLatestAiCoaching(isDark, l10n),
                    const SizedBox(height: 20),
                    _buildTerrainBreakdown(isDark, l10n),
                    const SizedBox(height: 20),
                    _buildRecentTrips(isDark, l10n),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProfileHeader(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: const Icon(Icons.person_rounded,
                size: 40, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            _driverName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (_busNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.directions_bus_rounded,
                    size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Text(
                  _busNumber,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsGrid(bool isDark, AppLocalizations l10n) {
    final totalTrips = _trips.length;
    final totalSegments =
        _trips.fold<int>(0, (s, t) => s + t.validSegments);

    double avgDev = 0;
    double bestDev = double.infinity;
    double worstDev = 0;

    if (_trips.isNotEmpty) {
      double sum = 0;
      for (final t in _trips) {
        sum += t.overallAvgDeviation;
        if (t.overallAvgDeviation < bestDev) bestDev = t.overallAvgDeviation;
        if (t.overallAvgDeviation > worstDev) {
          worstDev = t.overallAvgDeviation;
        }
      }
      avgDev = sum / _trips.length;
    } else {
      bestDev = 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.overall, isDark),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _statCard(
                l10n.totalTrips,
                '$totalTrips',
                Icons.route_rounded,
                AppColors.primary,
                isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                l10n.segments,
                '$totalSegments',
                Icons.grid_view_rounded,
                AppColors.terrainDownhill,
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statCard(
                l10n.averageDeviation,
                avgDev.toStringAsFixed(2),
                Icons.analytics_rounded,
                _deviationColor(avgDev),
                isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                l10n.bestTerrain,
                bestDev.toStringAsFixed(2),
                Icons.emoji_events_rounded,
                AppColors.success,
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _statCard(
          l10n.worstTerrain,
          worstDev.toStringAsFixed(2),
          Icons.warning_rounded,
          AppColors.alert,
          isDark,
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _buildScoreHistory(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Deviation Trend', isDark),
        const SizedBox(height: 10),
        TripScoreHistoryChart(trips: _trips),
      ],
    );
  }

  Widget _buildLatestAiCoaching(bool isDark, AppLocalizations l10n) {
    // Find the most recent trip with a cached coaching report
    String? cachedReport;
    for (final trip in _trips) {
      if (trip.coachingReport.isNotEmpty) {
        cachedReport = trip.coachingReport;
        break;
      }
    }

    if (cachedReport == null || cachedReport.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.aiCoach, isDark),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'AI Coach',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                cachedReport,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark
                      ? AppColors.textOnDarkSecondary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTerrainBreakdown(bool isDark, AppLocalizations l10n) {
    int totalPlain = 0, totalUphill = 0, totalDownhill = 0;
    double sumDevPlain = 0, sumDevUphill = 0, sumDevDownhill = 0;
    int countPlain = 0, countUphill = 0, countDownhill = 0;

    for (final t in _trips) {
      totalPlain += t.plainSegments;
      totalUphill += t.uphillSegments;
      totalDownhill += t.downhillSegments;
      if (t.plainSegments > 0) {
        sumDevPlain += t.avgDeviationPlain * t.plainSegments;
        countPlain += t.plainSegments;
      }
      if (t.uphillSegments > 0) {
        sumDevUphill += t.avgDeviationUphill * t.uphillSegments;
        countUphill += t.uphillSegments;
      }
      if (t.downhillSegments > 0) {
        sumDevDownhill += t.avgDeviationDownhill * t.downhillSegments;
        countDownhill += t.downhillSegments;
      }
    }

    final avgPlain = countPlain > 0 ? sumDevPlain / countPlain : 0.0;
    final avgUphill = countUphill > 0 ? sumDevUphill / countUphill : 0.0;
    final avgDownhill =
        countDownhill > 0 ? sumDevDownhill / countDownhill : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.terrain, isDark),
        const SizedBox(height: 10),
        _terrainRow(l10n.plain, totalPlain, avgPlain,
            AppColors.terrainPlain, isDark),
        const SizedBox(height: 8),
        _terrainRow(l10n.uphill, totalUphill, avgUphill,
            AppColors.terrainUphill, isDark),
        const SizedBox(height: 8),
        _terrainRow(l10n.downhill, totalDownhill, avgDownhill,
            AppColors.terrainDownhill, isDark),
      ],
    );
  }

  Widget _buildRecentTrips(bool isDark, AppLocalizations l10n) {
    if (_trips.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.route_rounded,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 8),
            Text(
              l10n.noTripsYet,
              style: TextStyle(
                color: isDark
                    ? AppColors.textOnDarkSecondary
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    final recent = _trips.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.tripHistory, isDark),
        const SizedBox(height: 10),
        ...recent.map((trip) => _recentTripTile(trip, isDark)),
      ],
    );
  }

  Widget _recentTripTile(TripSummary trip, bool isDark) {
    final date =
        '${trip.startTime.day}/${trip.startTime.month}/${trip.startTime.year}';
    final dur = trip.endTime.difference(trip.startTime);
    final mins = dur.inMinutes;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _deviationColor(trip.overallAvgDeviation)
                  .withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                trip.overallAvgDeviation.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _deviationColor(trip.overallAvgDeviation),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textOnDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${trip.validSegments} segments · ${mins}m',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Terrain chips
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trip.plainSegments > 0)
                _terrainChip('P', trip.plainSegments,
                    AppColors.terrainPlain),
              if (trip.uphillSegments > 0)
                _terrainChip('U', trip.uphillSegments,
                    AppColors.terrainUphill),
              if (trip.downhillSegments > 0)
                _terrainChip('D', trip.downhillSegments,
                    AppColors.terrainDownhill),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Helper widgets ────────────────────────────────────────────────

  Widget _sectionTitle(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
      ),
    );
  }

  Widget _statCard(
    String label,
    String value,
    IconData icon,
    Color accent,
    bool isDark, {
    bool fullWidth = false,
  }) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textOnDark
                        : AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _terrainRow(
      String name, int segments, double avgDev, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textOnDark
                        : AppColors.textPrimary,
                  ),
                ),
                Text(
                  '$segments segments',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            segments > 0 ? avgDev.toStringAsFixed(2) : '—',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: segments > 0
                  ? _deviationColor(avgDev)
                  : (isDark
                      ? AppColors.textOnDarkSecondary
                      : AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _terrainChip(String letter, int count, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$letter$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Color _deviationColor(double dev) {
    if (dev < 5.0) return AppColors.success;
    if (dev < 15.0) return AppColors.warning;
    return AppColors.alert;
  }
}
