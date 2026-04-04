import '../config/benchmark_tables.dart';
import '../models/trip_model.dart';
import '../models/cluster_model.dart';

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
  /// [benchmarkFeatures] - Optional custom benchmark features (from DB).
  ///   If null, falls back to hardcoded BenchmarkTables.
  ///
  /// Returns a [SegmentScore] with cluster0/cluster1 deviations and match.
  static DeviationResult computeSegmentDeviation({
    required String terrain,
    required Map<String, double> featureValues,
    List<BenchmarkFeature>? benchmarkFeatures,
  }) {
    final features = benchmarkFeatures ??
        BenchmarkTables.getFeaturesForTerrain(terrain);

    double cluster0Total = 0.0;
    double cluster1Total = 0.0;
    final List<FeatureDeviation> details = [];

    for (final bf in features) {
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

  /// Compute total deviation for a single cluster given its feature ranges.
  ///
  /// [featureValues] - Map of "Attribute_FeatureName" → computed value
  /// [clusterFeatures] - Feature ranges for this cluster and terrain
  ///
  /// Returns the sum of per-feature deviations.
  static double computeDeviationForCluster(
    Map<String, double> featureValues,
    List<ClusterFeatureRange> clusterFeatures,
  ) {
    double total = 0.0;
    for (final cf in clusterFeatures) {
      final value = featureValues[cf.featureName];
      if (value == null) continue;
      total += computeFeatureDeviation(
        value,
        BenchmarkRange(cf.minValue, cf.maxValue),
      );
    }
    return total;
  }

  /// Compute deviations against multiple dynamic clusters for a segment.
  ///
  /// Returns a [DynamicDeviationResult] containing per-cluster deviations
  /// and the name of the best-matching cluster.
  static DynamicDeviationResult computeSegmentDeviationDynamic({
    required Map<String, double> featureValues,
    required List<ClusterDefinition> clusters,
    required Map<String, List<ClusterFeatureRange>> featuresCache,
    required String terrain,
  }) {
    final Map<int, double> clusterDeviations = {};

    for (final cluster in clusters) {
      if (cluster.id == null) continue;
      final cacheKey = '${cluster.id}_$terrain';
      final features = featuresCache[cacheKey] ?? [];
      if (features.isEmpty) continue;
      clusterDeviations[cluster.id!] =
          computeDeviationForCluster(featureValues, features);
    }

    if (clusterDeviations.isEmpty) {
      return DynamicDeviationResult(
        clusterDeviations: {},
        bestClusterName: '',
        cluster0Deviation: 0.0,
        cluster1Deviation: 0.0,
        matchedClusterIndex: 0,
      );
    }

    // Sort clusters by ID (consistent ordering for cluster0/cluster1 labelling)
    final sortedClusters = List<ClusterDefinition>.from(clusters)
      ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));

    // Find best cluster (lowest deviation)
    int? bestId;
    double bestDev = double.infinity;
    for (final entry in clusterDeviations.entries) {
      if (entry.value < bestDev) {
        bestDev = entry.value;
        bestId = entry.key;
      }
    }

    final bestCluster = clusters.firstWhere(
      (c) => c.id == bestId,
      orElse: () => sortedClusters.first,
    );

    // cluster0 = first in sorted order, cluster1 = second
    final c0Id = sortedClusters.isNotEmpty ? sortedClusters[0].id : null;
    final c1Id = sortedClusters.length > 1 ? sortedClusters[1].id : null;
    final c0Dev = (c0Id != null ? clusterDeviations[c0Id] : null) ?? 0.0;
    final c1Dev = (c1Id != null ? clusterDeviations[c1Id] : null) ?? 999999.0;
    final matchedIndex = c0Dev <= c1Dev ? 0 : 1;

    return DynamicDeviationResult(
      clusterDeviations: clusterDeviations,
      bestClusterName: bestCluster.name,
      cluster0Deviation: c0Dev,
      cluster1Deviation: c1Dev,
      matchedClusterIndex: matchedIndex,
    );
  }
}

/// Result of dynamic multi-cluster deviation computation.
class DynamicDeviationResult {
  final Map<int, double> clusterDeviations;
  final String bestClusterName;
  final double cluster0Deviation;
  final double cluster1Deviation;
  final int matchedClusterIndex;

  DynamicDeviationResult({
    required this.clusterDeviations,
    required this.bestClusterName,
    required this.cluster0Deviation,
    required this.cluster1Deviation,
    required this.matchedClusterIndex,
  });
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
