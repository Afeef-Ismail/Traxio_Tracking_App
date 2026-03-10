import '../models/trip_model.dart';
import '../providers/trip_provider.dart';

/// Rule-based coaching engine that generates actionable driving feedback
/// from trip and segment data.
class CoachingEngine {
  /// Generate a list of coaching insights from a trip summary
  /// and its segment details.
  static List<CoachingInsight> analyze(
    TripSummary summary,
    List<SegmentDetail> segments,
  ) {
    final insights = <CoachingInsight>[];

    // ─── 1. Overall deviation rating ─────────────────────────────
    final dev = summary.overallAvgDeviation;
    if (dev < 5.0) {
      insights.add(CoachingInsight(
        icon: InsightIcon.trophy,
        title: 'Excellent Driving',
        message:
            'Your overall deviation of ${dev.toStringAsFixed(2)} is well within '
            'the benchmark range. Keep up the great driving!',
        severity: Severity.positive,
      ));
    } else if (dev < 10.0) {
      insights.add(CoachingInsight(
        icon: InsightIcon.thumbsUp,
        title: 'Good Performance',
        message:
            'Your deviation of ${dev.toStringAsFixed(2)} shows generally safe '
            'driving with minor areas for improvement.',
        severity: Severity.neutral,
      ));
    } else if (dev < 20.0) {
      insights.add(CoachingInsight(
        icon: InsightIcon.warning,
        title: 'Needs Improvement',
        message:
            'Your deviation of ${dev.toStringAsFixed(2)} indicates noticeable '
            'departures from benchmark driving patterns. Review the tips below.',
        severity: Severity.warning,
      ));
    } else {
      insights.add(CoachingInsight(
        icon: InsightIcon.alert,
        title: 'High Deviation Alert',
        message:
            'Your deviation of ${dev.toStringAsFixed(2)} is significantly above '
            'benchmarks. Please review your driving technique carefully.',
        severity: Severity.critical,
      ));
    }

    // ─── 2. Terrain-specific feedback ────────────────────────────
    if (summary.uphillSegments > 0 && summary.avgDeviationUphill > 12.0) {
      insights.add(CoachingInsight(
        icon: InsightIcon.terrain,
        title: 'Uphill Driving',
        message:
            'Your uphill deviation (${summary.avgDeviationUphill.toStringAsFixed(2)}) '
            'is elevated. On inclines, maintain steady throttle input and '
            'avoid sudden acceleration. Use lower gears for consistent speed.',
        severity: Severity.warning,
      ));
    }
    if (summary.downhillSegments > 0 &&
        summary.avgDeviationDownhill > 12.0) {
      insights.add(CoachingInsight(
        icon: InsightIcon.terrain,
        title: 'Downhill Driving',
        message:
            'Your downhill deviation (${summary.avgDeviationDownhill.toStringAsFixed(2)}) '
            'suggests aggressive braking or speed surges. Use engine braking '
            'and maintain controlled speed on descents.',
        severity: Severity.warning,
      ));
    }
    if (summary.plainSegments > 0 && summary.avgDeviationPlain > 12.0) {
      insights.add(CoachingInsight(
        icon: InsightIcon.terrain,
        title: 'Plain Road Driving',
        message:
            'Your plain road deviation (${summary.avgDeviationPlain.toStringAsFixed(2)}) '
            'is above benchmark. On flat roads, maintain even speed and '
            'smooth steering to reduce lateral forces.',
        severity: Severity.warning,
      ));
    }

    // ─── 3. Worst segment analysis ───────────────────────────────
    if (segments.length > 1) {
      SegmentDetail? worst;
      double worstDev = -1;
      for (final seg in segments) {
        final d = seg.matchedCluster == 0
            ? seg.cluster0Deviation
            : seg.cluster1Deviation;
        if (d > worstDev) {
          worstDev = d;
          worst = seg;
        }
      }
      if (worst != null && worstDev > 10.0) {
        insights.add(CoachingInsight(
          icon: InsightIcon.focus,
          title: 'Worst Segment: #${worst.segmentIndex + 1}',
          message:
              'Segment ${worst.segmentIndex + 1} (${worst.terrain}) had the '
              'highest deviation of ${worstDev.toStringAsFixed(2)}. Review your '
              'driving behaviour in that section — check for sudden braking, '
              'sharp turns, or speed variations.',
          severity: Severity.warning,
        ));
      }
    }

    // ─── 4. Cluster distribution insight ─────────────────────────
    if (summary.cluster0Percentage > 70) {
      insights.add(CoachingInsight(
        icon: InsightIcon.info,
        title: 'Driving Pattern: Cluster 0 Dominant',
        message:
            '${summary.cluster0Percentage.toStringAsFixed(0)}% of your segments '
            'matched Cluster 0, indicating a consistent driving style. '
            'This is typical of steady, predictable driving.',
        severity: Severity.positive,
      ));
    } else if (summary.cluster1Percentage > 70) {
      insights.add(CoachingInsight(
        icon: InsightIcon.info,
        title: 'Driving Pattern: Cluster 1 Dominant',
        message:
            '${summary.cluster1Percentage.toStringAsFixed(0)}% of your segments '
            'matched Cluster 1. This pattern may indicate more dynamic driving. '
            'Monitor your deviation scores closely.',
        severity: Severity.neutral,
      ));
    } else {
      insights.add(CoachingInsight(
        icon: InsightIcon.info,
        title: 'Mixed Driving Pattern',
        message:
            'Your driving showed a mix of patterns — '
            '${summary.cluster0Percentage.toStringAsFixed(0)}% Cluster 0 and '
            '${summary.cluster1Percentage.toStringAsFixed(0)}% Cluster 1. '
            'This suggests varied road and traffic conditions.',
        severity: Severity.neutral,
      ));
    }

    // ─── 5. High-deviation segments count ────────────────────────
    int highDevCount = 0;
    for (final seg in segments) {
      final d = seg.matchedCluster == 0
          ? seg.cluster0Deviation
          : seg.cluster1Deviation;
      if (d > 15.0) highDevCount++;
    }
    if (highDevCount > 0) {
      final pct = (highDevCount / segments.length * 100).toStringAsFixed(0);
      insights.add(CoachingInsight(
        icon: InsightIcon.alert,
        title: '$highDevCount High-Deviation Segments',
        message:
            '$pct% of your segments exceeded a deviation of 15. '
            'Focus on smoother transitions between acceleration, braking, '
            'and steering to bring these within benchmark range.',
        severity: highDevCount > segments.length / 2
            ? Severity.critical
            : Severity.warning,
      ));
    }

    // ─── 6. Short trip warning ───────────────────────────────────
    if (summary.validSegments < 5) {
      insights.add(CoachingInsight(
        icon: InsightIcon.info,
        title: 'Short Trip',
        message:
            'Only ${summary.validSegments} segments were recorded. '
            'Longer trips provide more accurate benchmarking data. '
            'Try recording trips of at least 10 km.',
        severity: Severity.neutral,
      ));
    }

    return insights;
  }
}

/// Severity levels for coaching insights.
enum Severity { positive, neutral, warning, critical }

/// Icon types for coaching insights.
enum InsightIcon { trophy, thumbsUp, warning, alert, terrain, focus, info }

/// A single coaching insight/feedback item.
class CoachingInsight {
  final InsightIcon icon;
  final String title;
  final String message;
  final Severity severity;

  const CoachingInsight({
    required this.icon,
    required this.title,
    required this.message,
    required this.severity,
  });
}
