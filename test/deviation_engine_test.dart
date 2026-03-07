import 'package:flutter_test/flutter_test.dart';
import 'package:ksrtc_app/analytics/deviation_engine.dart';
import 'package:ksrtc_app/config/benchmark_tables.dart';
import 'package:ksrtc_app/config/constants.dart';

void main() {
  group('DeviationEngine', () {
    test('value within range → deviation = 0', () {
      final dev = DeviationEngine.computeFeatureDeviation(
        5.0,
        const BenchmarkRange(3.0, 7.0),
      );
      expect(dev, 0.0);
    });

    test('value below min → deviation = min - value', () {
      final dev = DeviationEngine.computeFeatureDeviation(
        1.0,
        const BenchmarkRange(3.0, 7.0),
      );
      expect(dev, 2.0); // 3.0 - 1.0
    });

    test('value above max → deviation = value - max', () {
      final dev = DeviationEngine.computeFeatureDeviation(
        10.0,
        const BenchmarkRange(3.0, 7.0),
      );
      expect(dev, 3.0); // 10.0 - 7.0
    });

    test('value exactly at min → deviation = 0', () {
      final dev = DeviationEngine.computeFeatureDeviation(
        3.0,
        const BenchmarkRange(3.0, 7.0),
      );
      expect(dev, 0.0);
    });

    test('value exactly at max → deviation = 0', () {
      final dev = DeviationEngine.computeFeatureDeviation(
        7.0,
        const BenchmarkRange(3.0, 7.0),
      );
      expect(dev, 0.0);
    });

    test('segment deviation selects cluster with lower total', () {
      // Create feature values that are closer to cluster 0 ranges
      final features = <String, double>{};
      final benchmarks =
          BenchmarkTables.getFeaturesForTerrain(AppConstants.terrainPlain);

      // Set all features to cluster 0 midpoints
      for (final bf in benchmarks) {
        features[bf.featureKey] =
            (bf.cluster0.min + bf.cluster0.max) / 2.0;
      }

      final result = DeviationEngine.computeSegmentDeviation(
        terrain: AppConstants.terrainPlain,
        featureValues: features,
      );

      // All values within cluster 0 range → deviation 0
      expect(result.cluster0Deviation, 0.0);
      expect(result.matchedCluster, 0);
    });

    test('segment deviation sums all 10 feature deviations', () {
      final features = <String, double>{};
      final benchmarks =
          BenchmarkTables.getFeaturesForTerrain(AppConstants.terrainPlain);

      // Set all features to way outside both ranges
      for (final bf in benchmarks) {
        features[bf.featureKey] = 99999.0;
      }

      final result = DeviationEngine.computeSegmentDeviation(
        terrain: AppConstants.terrainPlain,
        featureValues: features,
      );

      // Both deviations should be large
      expect(result.cluster0Deviation > 0, true);
      expect(result.cluster1Deviation > 0, true);
      expect(result.featureDeviations.length, 10);
    });

    test('missing features are skipped gracefully', () {
      // No matching features → zero deviations
      final result = DeviationEngine.computeSegmentDeviation(
        terrain: AppConstants.terrainPlain,
        featureValues: {'nonexistent_feature': 5.0},
      );

      expect(result.cluster0Deviation, 0.0);
      expect(result.cluster1Deviation, 0.0);
    });

    test('uphill terrain uses uphill benchmark table', () {
      final features = <String, double>{};
      final benchmarks =
          BenchmarkTables.getFeaturesForTerrain(AppConstants.terrainUphill);

      for (final bf in benchmarks) {
        features[bf.featureKey] =
            (bf.cluster0.min + bf.cluster0.max) / 2.0;
      }

      final result = DeviationEngine.computeSegmentDeviation(
        terrain: AppConstants.terrainUphill,
        featureValues: features,
      );

      expect(result.cluster0Deviation, 0.0);
    });

    test('downhill terrain uses downhill benchmark table', () {
      final features = <String, double>{};
      final benchmarks =
          BenchmarkTables.getFeaturesForTerrain(AppConstants.terrainDownhill);

      for (final bf in benchmarks) {
        features[bf.featureKey] =
            (bf.cluster1.min + bf.cluster1.max) / 2.0;
      }

      final result = DeviationEngine.computeSegmentDeviation(
        terrain: AppConstants.terrainDownhill,
        featureValues: features,
      );

      expect(result.cluster1Deviation, 0.0);
      expect(result.matchedCluster, 1);
    });
  });
}
