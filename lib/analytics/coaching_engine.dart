import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models/trip_model.dart';
import '../providers/trip_provider.dart';

/// Rule-based coaching engine that generates actionable driving feedback
/// from trip and segment data.
class CoachingEngine {
  /// Generate a list of coaching insights from a trip summary
  /// and its segment details. Pass [l10n] to get localized strings.
  static List<CoachingInsight> analyze(
    TripSummary summary,
    List<SegmentDetail> segments, {
    AppLocalizations? l10n,
  }) {
    final insights = <CoachingInsight>[];
    final dev = summary.overallAvgDeviation;
    final devStr = dev.toStringAsFixed(2);

    // ─── 1. Overall deviation rating ─────────────────────────────
    if (dev < 5.0) {
      insights.add(CoachingInsight(
        icon: InsightIcon.trophy,
        title: l10n?.coachExcellentTitle ?? 'Excellent Driving',
        message: l10n?.coachExcellentMsg(devStr) ??
            'Your overall deviation of $devStr is well within the benchmark range. Keep up the great driving!',
        severity: Severity.positive,
      ));
    } else if (dev < 10.0) {
      insights.add(CoachingInsight(
        icon: InsightIcon.thumbsUp,
        title: l10n?.coachGoodTitle ?? 'Good Performance',
        message: l10n?.coachGoodMsg(devStr) ??
            'Your deviation of $devStr shows generally safe driving with minor areas for improvement.',
        severity: Severity.neutral,
      ));
    } else if (dev < 20.0) {
      insights.add(CoachingInsight(
        icon: InsightIcon.warning,
        title: l10n?.coachNeedsImpTitle ?? 'Needs Improvement',
        message: l10n?.coachNeedsImpMsg(devStr) ??
            'Your deviation of $devStr indicates noticeable departures from benchmark driving patterns. Review the tips below.',
        severity: Severity.warning,
      ));
    } else {
      insights.add(CoachingInsight(
        icon: InsightIcon.alert,
        title: l10n?.coachHighDevTitle ?? 'High Deviation Alert',
        message: l10n?.coachHighDevMsg(devStr) ??
            'Your deviation of $devStr is significantly above benchmarks. Please review your driving technique carefully.',
        severity: Severity.critical,
      ));
    }

    // ─── 2. Terrain-specific feedback ────────────────────────────
    if (summary.uphillSegments > 0 && summary.avgDeviationUphill > 12.0) {
      final d = summary.avgDeviationUphill.toStringAsFixed(2);
      insights.add(CoachingInsight(
        icon: InsightIcon.terrain,
        title: l10n?.coachUphillTitle ?? 'Uphill Driving',
        message: l10n?.coachUphillMsg(d) ??
            'Your uphill deviation ($d) is elevated. On inclines, maintain steady throttle input and avoid sudden acceleration. Use lower gears for consistent speed.',
        severity: Severity.warning,
      ));
    }
    if (summary.downhillSegments > 0 && summary.avgDeviationDownhill > 12.0) {
      final d = summary.avgDeviationDownhill.toStringAsFixed(2);
      insights.add(CoachingInsight(
        icon: InsightIcon.terrain,
        title: l10n?.coachDownhillTitle ?? 'Downhill Driving',
        message: l10n?.coachDownhillMsg(d) ??
            'Your downhill deviation ($d) suggests aggressive braking or speed surges. Use engine braking and maintain controlled speed on descents.',
        severity: Severity.warning,
      ));
    }
    if (summary.plainSegments > 0 && summary.avgDeviationPlain > 12.0) {
      final d = summary.avgDeviationPlain.toStringAsFixed(2);
      insights.add(CoachingInsight(
        icon: InsightIcon.terrain,
        title: l10n?.coachPlainTitle ?? 'Plain Road Driving',
        message: l10n?.coachPlainMsg(d) ??
            'Your plain road deviation ($d) is above benchmark. On flat roads, maintain even speed and smooth steering to reduce lateral forces.',
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
        final num = worst.segmentIndex + 1;
        final dStr = worstDev.toStringAsFixed(2);
        insights.add(CoachingInsight(
          icon: InsightIcon.focus,
          title: l10n?.coachWorstSegTitle(num) ?? 'Worst Segment: #$num',
          message: l10n?.coachWorstSegMsg(num, worst.terrain, dStr) ??
              'Segment $num (${worst.terrain}) had the highest deviation of $dStr. Review your driving behaviour in that section — check for sudden braking, sharp turns, or speed variations.',
          severity: Severity.warning,
        ));
      }
    }

    // ─── 4. High-deviation segments count ────────────────────────
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
        title: l10n?.coachHighDevSegsTitle(highDevCount) ?? '$highDevCount High-Deviation Segments',
        message: l10n?.coachHighDevSegsMsg(pct) ??
            '$pct% of your segments exceeded a deviation of 15. Focus on smoother transitions between acceleration, braking, and steering to bring these within benchmark range.',
        severity: highDevCount > segments.length / 2
            ? Severity.critical
            : Severity.warning,
      ));
    }

    // ─── 5. Short trip warning ───────────────────────────────────
    if (summary.validSegments < 5) {
      insights.add(CoachingInsight(
        icon: InsightIcon.info,
        title: l10n?.coachShortTripTitle ?? 'Short Trip',
        message: l10n?.coachShortTripMsg(summary.validSegments) ??
            'Only ${summary.validSegments} segments were recorded. Longer trips provide more accurate benchmarking data. Try recording trips of at least 10 km.',
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
