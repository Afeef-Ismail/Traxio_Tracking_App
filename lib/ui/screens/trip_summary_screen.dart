import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../providers/trip_provider.dart';
import '../../models/trip_model.dart';
import '../../analytics/coaching_engine.dart';
import '../../analytics/score_calculator.dart';
import '../../database/db_helper.dart';
import '../../models/cluster_model.dart';
import '../widgets/summary_card.dart';
import '../widgets/buttons.dart';
import '../widgets/map_widget.dart';
import '../theme/app_colors.dart';
import 'segment_list_screen.dart';
import 'cluster_management_screen.dart' show vehicleTypeIcon;

/// Trip Summary Screen — shown after trip completion.
///
/// Displays:
///   - Route map overview
///   - Cluster match percentages
///   - Average deviation per terrain
///   - Terrain distribution summary cards
///   - AI coaching report
class TripSummaryScreen extends StatefulWidget {
  final int initialTabIndex;

  const TripSummaryScreen({super.key, this.initialTabIndex = 2});

  @override
  State<TripSummaryScreen> createState() => _TripSummaryScreenState();
}

class _TripSummaryScreenState extends State<TripSummaryScreen> {
  List<CoachingInsight> _insights = [];
  bool _coachingLoaded = false;
  int _tripScore = -1;
  // Clusters that were actually scored in this trip (by matched_cluster_name).
  // May include clusters now deactivated; _inactiveClusterNames tracks those.
  List<ClusterDefinition> _scoredClusters = [];
  Set<String> _inactiveClusterNames = {};
  Map<String, int> _clusterMatchCounts = {};
  int _totalMatchedSegments = 0;

  bool _clusterMatchesVehicle(ClusterDefinition cluster, String vehicleType) {
    if (vehicleType.isEmpty) return true;
    return cluster.vehicleType.isEmpty || cluster.vehicleType == vehicleType;
  }

  @override
  void initState() {
    super.initState();
    _loadCoaching();
  }

  Future<void> _loadCoaching() async {
    final provider = context.read<TripProvider>();
    // Capture l10n synchronously before any await.
    final l10n = AppLocalizations.of(context);
    final summary = provider.lastSummary;

    if (summary == null) {
      if (mounted) setState(() => _coachingLoaded = true);
      return;
    }

    // Step 1: Load cluster display data
    try {
      final allClusters = await DbHelper().getAllClusters();
      final matchCounts = await DbHelper().getClusterMatchCounts(summary.tripId);
      final totalMatched = matchCounts.values.fold(0, (a, b) => a + b);
      final matchedNames = matchCounts.keys.toSet();

      // Show all active clusters relevant to this trip's vehicle type,
      // then append any matched clusters that are now inactive.
      final relevantActive = allClusters
          .where((c) => c.isActive && _clusterMatchesVehicle(c, summary.vehicleType))
          .toList();

      final missingMatched = allClusters
          .where((c) => !c.isActive && matchedNames.contains(c.name))
          .toList();

      final scored = <ClusterDefinition>[
        ...relevantActive,
        ...missingMatched.where(
          (c) => !relevantActive.any((a) => a.name == c.name),
        ),
      ]
        ..sort((a, b) {
          final ai = a.id ?? 1 << 30;
          final bi = b.id ?? 1 << 30;
          return ai.compareTo(bi);
        });

      final inactiveNames = scored
          .where((c) => !c.isActive)
          .map((c) => c.name)
          .toSet();

      if (mounted) {
        setState(() {
          _scoredClusters = scored;
          _inactiveClusterNames = inactiveNames;
          _clusterMatchCounts = matchCounts;
          _totalMatchedSegments = summary.validSegments > 0
              ? summary.validSegments
              : totalMatched;
        });
      }
    } catch (_) {
      // cluster data unavailable — show empty cluster section
    }

    if (!mounted) {
      return;
    }

    // Step 2: Compute score and coaching insights
    final tripScore = ScoreCalculator.computeScore(summary.overallAvgDeviation);

    List<SegmentDetail> segments = [];
    try {
      segments = await provider.getSegmentDetailsLite(summary.tripId);
    } catch (_) {
      // segment data unavailable — coaching will use summary data only
    }

    final insights = CoachingEngine.analyze(summary, segments, l10n: l10n);

    if (mounted) {
      setState(() {
        _tripScore = tripScore;
        _insights = insights;
        _coachingLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<TripProvider>();
    final summary = provider.lastSummary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (summary == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.tripSummary)),
        body: Center(child: Text(l10n.tripNotFound)),
      );
    }

    final totalTerrainSegments =
        summary.plainSegments + summary.uphillSegments + summary.downhillSegments;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        _goHome(provider);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
            // ─── Top Bar ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.tripComplete,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textOnDark
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // ─── Scrollable Content ──────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── Score Badge ─────────────────────────────────
                    if (_tripScore >= 0) ...[
                      Center(
                        child: _ScoreBadge(score: _tripScore, isDark: isDark),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ─── Map Overview ────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 200,
                        child: MapWidget(zoom: 13.0),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ─── Vehicle type badge ───────────────────────────
                    if (summary.vehicleType.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            vehicleTypeIcon(summary.vehicleType),
                            size: 16,
                            color: isDark
                                ? AppColors.textOnDarkSecondary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            summary.vehicleType,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? AppColors.textOnDarkSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ─── Cluster Match Section ───────────────────────
                    _SectionTitle(l10n.clusterMatching, isDark: isDark),
                    const SizedBox(height: 10),
                    _buildClusterCards(summary, isDark),
                    const SizedBox(height: 20),

                    // ─── Overall Deviation ───────────────────────────
                    SummaryCard(
                      title: l10n.averageDeviation,
                      value: summary.overallAvgDeviation.toStringAsFixed(2),
                      subtitle:
                          '${summary.validSegments} of ${summary.totalSegments} segments valid',
                      icon: Icons.analytics_outlined,
                      accentColor: summary.overallAvgDeviation < 5.0
                          ? AppColors.success
                          : (summary.overallAvgDeviation < 15.0
                              ? AppColors.warning
                              : AppColors.alert),
                    ),
                    const SizedBox(height: 20),

                    // ─── Per-Terrain Deviation ───────────────────────
                    _SectionTitle(l10n.deviationByTerrain, isDark: isDark),
                    const SizedBox(height: 10),

                    if (summary.plainSegments > 0) ...[
                      _TerrainDeviationRow(
                        terrain: l10n.plain,
                        deviation: summary.avgDeviationPlain,
                        segmentCount: summary.plainSegments,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (summary.uphillSegments > 0) ...[
                      _TerrainDeviationRow(
                        terrain: l10n.uphill,
                        deviation: summary.avgDeviationUphill,
                        segmentCount: summary.uphillSegments,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (summary.downhillSegments > 0) ...[
                      _TerrainDeviationRow(
                        terrain: l10n.downhill,
                        deviation: summary.avgDeviationDownhill,
                        segmentCount: summary.downhillSegments,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 20),

                    // ─── Terrain Distribution ────────────────────────
                    _SectionTitle(l10n.terrainDistribution, isDark: isDark),
                    const SizedBox(height: 10),
                    _TerrainDistributionBar(
                      plain: summary.plainSegments,
                      uphill: summary.uphillSegments,
                      downhill: summary.downhillSegments,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _TerrainLegend(
                          terrain: l10n.plain,
                          count: summary.plainSegments,
                          total: totalTerrainSegments,
                        ),
                        _TerrainLegend(
                          terrain: l10n.uphill,
                          count: summary.uphillSegments,
                          total: totalTerrainSegments,
                        ),
                        _TerrainLegend(
                          terrain: l10n.downhill,
                          count: summary.downhillSegments,
                          total: totalTerrainSegments,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ─── Trip Info ────────────────────────────────────
                    _SectionTitle(l10n.tripInformation, isDark: isDark),
                    const SizedBox(height: 10),
                    _InfoRow(
                      l10n.startTime,
                      _formatTime(summary.startTime),
                      isDark: isDark,
                    ),
                    _InfoRow(
                      l10n.endTime,
                      _formatTime(summary.endTime),
                      isDark: isDark,
                    ),
                    _InfoRow(
                      l10n.duration,
                      _formatDuration(
                          summary.endTime.difference(summary.startTime)),
                      isDark: isDark,
                    ),
                    _InfoRow(
                      l10n.totalSegments,
                      '${summary.totalSegments}',
                      isDark: isDark,
                    ),
                    _InfoRow(
                      l10n.validSegments,
                      '${summary.validSegments}',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 24),

                    // ─── Coaching Cards ──────────────────────────────
                    _SectionTitle(l10n.coachingReport, isDark: isDark),
                    const SizedBox(height: 10),
                    if (!_coachingLoaded)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2)),
                      )
                    else
                      ..._insights.map((insight) =>
                          _CoachingCard(insight: insight, isDark: isDark)),
                    const SizedBox(height: 24),

                    // ─── Action Buttons ──────────────────────────────
                    PrimaryButton(
                      label: l10n.viewSegments,
                      icon: Icons.grid_view_rounded,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SegmentListScreen(
                              tripId: summary.tripId,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: l10n.done,
                      icon: Icons.check_rounded,
                      onPressed: () => _goHome(provider),
                    ),
                  ],
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  void _goHome(TripProvider provider) {
    provider.reset();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/home',
      (route) => false,
      arguments: {'initialTab': widget.initialTabIndex},
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildClusterCards(TripSummary summary, bool isDark) {
    if (_scoredClusters.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          ),
        ),
        child: Text(
          'No cluster data available for this trip.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.textOnDarkSecondary : AppColors.textMuted,
          ),
        ),
      );
    }

    final cards = _scoredClusters.map((c) {
      final count = _clusterMatchCounts[c.name] ?? 0;
      final pct = _totalMatchedSegments > 0
          ? count * 100.0 / _totalMatchedSegments
          : 0.0;
      final inactive = _inactiveClusterNames.contains(c.name);
      return _ClusterCard(
        clusterName: c.name,
        percentage: pct,
        count: count,
        isDark: isDark,
        inactive: inactive,
      );
    }).toList();

    if (cards.length == 1) return cards.first;

    return LayoutBuilder(builder: (context, constraints) {
      final cardWidth = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards
            .map((c) => SizedBox(width: cardWidth, child: c))
            .toList(),
      );
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }
}

// ─── Helper Widgets ────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionTitle(this.title, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
      ),
    );
  }
}

class _ClusterCard extends StatelessWidget {
  final String clusterName;
  final double percentage;
  final int count;
  final bool isDark;
  final bool inactive;

  const _ClusterCard({
    required this.clusterName,
    required this.percentage,
    required this.count,
    required this.isDark,
    this.inactive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: inactive
              ? (isDark ? AppColors.dividerDark : AppColors.dividerLight)
              : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
        ),
      ),
      child: Column(
        children: [
          Text(
            clusterName,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: inactive
                  ? AppColors.textMuted
                  : (isDark
                      ? AppColors.textOnDarkSecondary
                      : AppColors.textMuted),
            ),
          ),
          if (inactive) ...[
            const SizedBox(height: 2),
            Text(
              '(inactive)',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: inactive
                  ? AppColors.textMuted
                  : (isDark ? AppColors.textOnDark : AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$count segments',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TerrainDeviationRow extends StatelessWidget {
  final String terrain;
  final double deviation;
  final int segmentCount;
  final bool isDark;

  const _TerrainDeviationRow({
    required this.terrain,
    required this.deviation,
    required this.segmentCount,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.terrainColor(terrain);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  terrain,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  '$segmentCount segments',
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
            deviation.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TerrainDistributionBar extends StatelessWidget {
  final int plain;
  final int uphill;
  final int downhill;
  final bool isDark;

  const _TerrainDistributionBar({
    required this.plain,
    required this.uphill,
    required this.downhill,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final total = plain + uphill + downhill;
    if (total == 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            if (plain > 0)
              Flexible(
                flex: plain,
                child: Container(color: AppColors.terrainPlain),
              ),
            if (uphill > 0)
              Flexible(
                flex: uphill,
                child: Container(color: AppColors.terrainUphill),
              ),
            if (downhill > 0)
              Flexible(
                flex: downhill,
                child: Container(color: AppColors.terrainDownhill),
              ),
          ],
        ),
      ),
    );
  }
}

class _TerrainLegend extends StatelessWidget {
  final String terrain;
  final int count;
  final int total;

  const _TerrainLegend({
    required this.terrain,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (count / total * 100) : 0.0;
    final color = AppColors.terrainColor(terrain);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$terrain ${pct.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _InfoRow(this.label, this.value, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachingCard extends StatelessWidget {
  final CoachingInsight insight;
  final bool isDark;

  const _CoachingCard({required this.insight, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final accentColor = _severityColor(insight.severity);
    final icon = _insightIcon(insight.icon);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withOpacity(0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textOnDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(Severity severity) {
    switch (severity) {
      case Severity.positive:
        return AppColors.success;
      case Severity.neutral:
        return AppColors.primary;
      case Severity.warning:
        return AppColors.warning;
      case Severity.critical:
        return AppColors.alert;
    }
  }

  IconData _insightIcon(InsightIcon icon) {
    switch (icon) {
      case InsightIcon.trophy:
        return Icons.emoji_events_rounded;
      case InsightIcon.thumbsUp:
        return Icons.thumb_up_alt_rounded;
      case InsightIcon.warning:
        return Icons.warning_rounded;
      case InsightIcon.alert:
        return Icons.error_rounded;
      case InsightIcon.terrain:
        return Icons.terrain_rounded;
      case InsightIcon.focus:
        return Icons.center_focus_strong_rounded;
      case InsightIcon.info:
        return Icons.info_rounded;
    }
  }
}

// ─── Score Badge ──────────────────────────────────────────────────────

class _ScoreBadge extends StatelessWidget {
  final int score;
  final bool isDark;

  const _ScoreBadge({required this.score, required this.isDark});

  Color get _color {
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 50) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color.withOpacity(0.12),
        border: Border.all(color: _color, width: 4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$score',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: _color,
              height: 1,
            ),
          ),
          Text(
            'SCORE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

