import '../models/segment_model.dart';
import '../models/trip_model.dart';
import '../config/constants.dart';
import '../database/db_helper.dart';

/// Computes trip-level aggregated analytics from segment scores.
///
/// Outputs:
///   - % segments matching Cluster 0
///   - % segments matching Cluster 1
///   - Average deviation per terrain type
///   - Total trip average deviation
class TripAnalytics {
  final DbHelper _db = DbHelper();

  /// Generate and save a complete trip summary.
  Future<TripSummary> generateSummary(String tripId) async {
    final segments = await _db.getSegmentsForTrip(tripId);
    final scores = await _db.getScoresForTrip(tripId);

    final validSegments =
        segments.where((s) => s.isValid).toList();
    final int totalSegments = segments.length;
    final int validCount = validSegments.length;

    // ─── Cluster match counts ──────────────────────────────────────
    int cluster0Matches = 0;
    int cluster1Matches = 0;

    for (final score in scores) {
      if (score.matchedCluster == 0) {
        cluster0Matches++;
      } else {
        cluster1Matches++;
      }
    }

    final double cluster0Pct = validCount > 0
        ? (cluster0Matches / validCount) * 100.0
        : 0.0;
    final double cluster1Pct = validCount > 0
        ? (cluster1Matches / validCount) * 100.0
        : 0.0;

    // ─── Terrain segment counts ────────────────────────────────────
    final plainSegs = validSegments
        .where((s) => s.terrain == AppConstants.terrainPlain)
        .toList();
    final uphillSegs = validSegments
        .where((s) => s.terrain == AppConstants.terrainUphill)
        .toList();
    final downhillSegs = validSegments
        .where((s) => s.terrain == AppConstants.terrainDownhill)
        .toList();

    // ─── Average deviation per terrain ─────────────────────────────
    final double avgDevPlain =
        _avgDeviationForSegments(plainSegs, scores);
    final double avgDevUphill =
        _avgDeviationForSegments(uphillSegs, scores);
    final double avgDevDownhill =
        _avgDeviationForSegments(downhillSegs, scores);

    // ─── Overall average deviation ─────────────────────────────────
    double totalDev = 0.0;
    for (final score in scores) {
      // Use the deviation of the matched cluster
      totalDev += score.matchedCluster == 0
          ? score.cluster0Deviation
          : score.cluster1Deviation;
    }
    final double overallAvgDev =
        scores.isNotEmpty ? totalDev / scores.length : 0.0;

    // ─── Build summary ─────────────────────────────────────────────
    final DateTime startTime = segments.isNotEmpty
        ? DateTime.fromMillisecondsSinceEpoch(segments.first.startTime)
        : DateTime.now();
    final DateTime endTime = segments.isNotEmpty
        ? DateTime.fromMillisecondsSinceEpoch(segments.last.endTime)
        : DateTime.now();

    final summary = TripSummary(
      tripId: tripId,
      startTime: startTime,
      endTime: endTime,
      totalSegments: totalSegments,
      validSegments: validCount,
      cluster0Matches: cluster0Matches,
      cluster1Matches: cluster1Matches,
      cluster0Percentage: cluster0Pct,
      cluster1Percentage: cluster1Pct,
      avgDeviationPlain: avgDevPlain,
      avgDeviationUphill: avgDevUphill,
      avgDeviationDownhill: avgDevDownhill,
      overallAvgDeviation: overallAvgDev,
      plainSegments: plainSegs.length,
      uphillSegments: uphillSegs.length,
      downhillSegments: downhillSegs.length,
    );

    await _db.saveTripSummary(summary);

    return summary;
  }

  /// Average minimum deviation for a set of segments.
  double _avgDeviationForSegments(
    List<Segment> terrainSegments,
    List<SegmentScore> allScores,
  ) {
    if (terrainSegments.isEmpty) return 0.0;

    final segIds = terrainSegments
        .map((s) => s.id)
        .where((id) => id != null)
        .toSet();

    double totalDev = 0.0;
    int count = 0;

    for (final score in allScores) {
      if (segIds.contains(score.segmentId)) {
        // Use matched cluster's deviation
        totalDev += score.matchedCluster == 0
            ? score.cluster0Deviation
            : score.cluster1Deviation;
        count++;
      }
    }

    return count > 0 ? totalDev / count : 0.0;
  }
}
