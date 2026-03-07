import 'package:flutter/material.dart';
import '../widgets/segment_feature_table.dart';
import '../widgets/terrain_badge.dart';
import '../widgets/summary_card.dart';
import '../theme/app_colors.dart';
import '../../config/benchmark_tables.dart';

/// Segment Detail Screen — triggered after trip to inspect individual segments.
///
/// Displays:
///   - Segment terrain
///   - 10 benchmark feature values with ranges
///   - Cluster matched
///   - Deviation score
///   - Optional simple bar chart
class SegmentDetailScreen extends StatelessWidget {
  /// The terrain type for this segment.
  final String terrain;

  /// The 10 benchmark feature values for this segment.
  final Map<String, double> features;

  /// Deviation from cluster 0.
  final double cluster0Deviation;

  /// Deviation from cluster 1.
  final double cluster1Deviation;

  /// Which cluster matched (lower deviation).
  final int matchedCluster;

  /// Segment index for display.
  final int segmentIndex;

  const SegmentDetailScreen({
    super.key,
    required this.terrain,
    required this.features,
    required this.cluster0Deviation,
    required this.cluster1Deviation,
    required this.matchedCluster,
    required this.segmentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final matchedDev =
        matchedCluster == 0 ? cluster0Deviation : cluster1Deviation;

    // Build benchmark ranges for matched cluster
    final benchmarkFeatures =
        BenchmarkTables.getFeaturesForTerrain(terrain);
    final Map<String, (double, double)> ranges = {};
    for (final bf in benchmarkFeatures) {
      final range = matchedCluster == 0 ? bf.cluster0 : bf.cluster1;
      ranges[bf.featureKey] = (range.min, range.max);
    }

    // Filter features to only show the 10 benchmark features
    final displayFeatures = <String, double>{};
    for (final bf in benchmarkFeatures) {
      if (features.containsKey(bf.featureKey)) {
        displayFeatures[bf.featureKey] = features[bf.featureKey]!;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Segment $segmentIndex'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Terrain + Cluster row ─────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TerrainBadge(terrain: terrain, large: true),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Cluster $matchedCluster',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ─── Deviation Scores ──────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: SummaryCard(
                      title: 'Matched Deviation',
                      value: matchedDev.toStringAsFixed(2),
                      subtitle: 'Cluster $matchedCluster',
                      accentColor: matchedDev < 5.0
                          ? AppColors.success
                          : (matchedDev < 15.0
                              ? AppColors.warning
                              : AppColors.alert),
                      icon: Icons.analytics_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DeviationCompareCard(
                      label: 'Cluster 0',
                      value: cluster0Deviation,
                      isMatched: matchedCluster == 0,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DeviationCompareCard(
                      label: 'Cluster 1',
                      value: cluster1Deviation,
                      isMatched: matchedCluster == 1,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ─── Feature Table ─────────────────────────────────────
              Text(
                'Benchmark Features',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              SegmentFeatureTable(
                features: displayFeatures,
                benchmarkRanges: ranges,
                matchedCluster: matchedCluster,
              ),
              const SizedBox(height: 24),

              // ─── Simple Deviation Bar ──────────────────────────────
              Text(
                'Deviation Comparison',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _DeviationBar(
                label: 'Cluster 0',
                value: cluster0Deviation,
                maxValue: (cluster0Deviation > cluster1Deviation
                        ? cluster0Deviation
                        : cluster1Deviation) *
                    1.2,
                color: matchedCluster == 0
                    ? AppColors.success
                    : AppColors.textMuted,
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _DeviationBar(
                label: 'Cluster 1',
                value: cluster1Deviation,
                maxValue: (cluster0Deviation > cluster1Deviation
                        ? cluster0Deviation
                        : cluster1Deviation) *
                    1.2,
                color: matchedCluster == 1
                    ? AppColors.success
                    : AppColors.textMuted,
                isDark: isDark,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Helper Widgets ────────────────────────────────────────────────────

class _DeviationCompareCard extends StatelessWidget {
  final String label;
  final double value;
  final bool isMatched;
  final bool isDark;

  const _DeviationCompareCard({
    required this.label,
    required this.value,
    required this.isMatched,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMatched
            ? AppColors.success.withOpacity(0.08)
            : (isDark ? AppColors.darkCard : AppColors.lightCard),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMatched
              ? AppColors.success.withOpacity(0.3)
              : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
          width: isMatched ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.textOnDarkSecondary
                      : AppColors.textMuted,
                ),
              ),
              if (isMatched) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check_circle, size: 14, color: AppColors.success),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviationBar extends StatelessWidget {
  final String label;
  final double value;
  final double maxValue;
  final Color color;
  final bool isDark;

  const _DeviationBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue > 0 ? (value / maxValue).clamp(0.0, 1.0) : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkBackground
                  : AppColors.lightBackground,
              borderRadius: BorderRadius.circular(6),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 56,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
