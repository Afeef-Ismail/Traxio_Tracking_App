import '../config/benchmark_tables.dart';
import '../models/trip_model.dart';

/// Computes deviation-based behavioral assessment against master driver
/// benchmark cluster ranges.
///
/// For each selected feature:
///   If value < min_range: deviation = min_range − value
///   If value > max_range: deviation = value − max_range
///   Else: deviation = 0
///
/// Cluster with lower total deviation = matched master behavior.
class DeviationEngine {
  DeviationEngine._();

  /// Compute deviation for a single feature against a benchmark range.
  static double computeFeatureDeviation(
    double value,
    BenchmarkRange range,
  ) {
    if (value < range.min) {
      return range.min - value;
    } else if (value > range.max) {
      return value - range.max;
    }
    return 0.0;
  }

  /// Score a segment against both clusters for a given terrain.
  ///
  /// [terrain] - "Plain", "Uphill", or "Downhill"
  /// [featureValues] - Map of "Attribute_FeatureName" → computed value
  ///
  /// Returns a [SegmentScore] with cluster0/cluster1 deviations and match.
  static DeviationResult computeSegmentDeviation({
    required String terrain,
    required Map<String, double> featureValues,
  }) {
    final benchmarkFeatures =
        BenchmarkTables.getFeaturesForTerrain(terrain);

    double cluster0Total = 0.0;
    double cluster1Total = 0.0;
    final List<FeatureDeviation> details = [];

    for (final bf in benchmarkFeatures) {
      final double? value = featureValues[bf.featureKey];
      if (value == null) continue;

      final double dev0 = computeFeatureDeviation(value, bf.cluster0);
      final double dev1 = computeFeatureDeviation(value, bf.cluster1);

      cluster0Total += dev0;
      cluster1Total += dev1;

      details.add(FeatureDeviation(
        featureKey: bf.featureKey,
        value: value,
        cluster0Deviation: dev0,
        cluster1Deviation: dev1,
      ));
    }

    final int matchedCluster =
        cluster0Total <= cluster1Total ? 0 : 1;

    return DeviationResult(
      cluster0Deviation: cluster0Total,
      cluster1Deviation: cluster1Total,
      matchedCluster: matchedCluster,
      featureDeviations: details,
    );
  }
}

/// Result of deviation computation for one segment.
class DeviationResult {
  final double cluster0Deviation;
  final double cluster1Deviation;
  final int matchedCluster;
  final List<FeatureDeviation> featureDeviations;

  DeviationResult({
    required this.cluster0Deviation,
    required this.cluster1Deviation,
    required this.matchedCluster,
    required this.featureDeviations,
  });
}

/// Per-feature deviation detail.
class FeatureDeviation {
  final String featureKey;
  final double value;
  final double cluster0Deviation;
  final double cluster1Deviation;

  FeatureDeviation({
    required this.featureKey,
    required this.value,
    required this.cluster0Deviation,
    required this.cluster1Deviation,
  });
}
