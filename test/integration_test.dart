import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:traxio/analytics/smoothing.dart';
import 'package:traxio/analytics/feature_engine.dart';
import 'package:traxio/analytics/fft_engine.dart';
import 'package:traxio/analytics/deviation_engine.dart';
import 'package:traxio/services/terrain_service.dart';
import 'package:traxio/config/constants.dart';
import 'package:traxio/config/benchmark_tables.dart';
import 'package:traxio/utils/math_utils.dart';

/// Integration test simulating the full processing pipeline
/// for a synthetic segment of data.
void main() {
  group('Full Pipeline Integration Test', () {
    test('complete pipeline: raw → smooth → features → deviation', () {
      // ─── 1. Generate synthetic 100m segment data (10Hz, ~10s) ────
      const int numSamples = 100; // 10 seconds at 10Hz
      final random = Random(42);

      // Simulate a vehicle at ~10 m/s (36 km/h) on plain terrain
      final List<double> speed = List.generate(
          numSamples, (i) => 10.0 + random.nextDouble() * 2 - 1);
      final List<double> ay = List.generate(
          numSamples, (i) => random.nextDouble() * 0.4 - 0.2);
      final List<double> ax = List.generate(
          numSamples, (i) => random.nextDouble() * 0.3 - 0.15);
      final List<double> yr = List.generate(
          numSamples, (i) => random.nextDouble() * 0.06 - 0.03);
      final List<int> timestamps = List.generate(
          numSamples, (i) => i * 100); // 100ms intervals

      // Derive attributes
      final List<double> jx = computeDerivative(ax, timestamps);
      final List<double> jy = computeDerivative(ay, timestamps);

      // Altitude nearly flat → Plain terrain
      final List<double> altitude = List.generate(
          numSamples, (i) => 100.0 + i * 0.001);
      final List<double> vv = computeDerivative(altitude, timestamps);

      // Radius of turn
      final List<double> r = List.generate(numSamples, (i) {
        if (yr[i].abs() < AppConstants.minYawRateForRadius) {
          return AppConstants.maxRadiusOfTurn;
        }
        return (speed[i] / yr[i].abs()).clamp(
            -AppConstants.maxRadiusOfTurn, AppConstants.maxRadiusOfTurn);
      });

      // Trim to derived length
      final int n = jx.length;
      final speedT = speed.sublist(1);
      final ayT = ay.sublist(1);
      final axT = ax.sublist(1);
      final yrT = yr.sublist(1);
      final rT = r.sublist(1);

      // ─── 2. Apply 3-point smoothing ──────────────────────────────
      final smoothed = Smoothing.smoothAll({
        'Speed': speedT,
        'ay': ayT,
        'ax': axT,
        'YR': yrT,
        'Jx': jx,
        'Jy': jy,
        'VV': vv,
        'R': rT,
      });

      expect(smoothed.length, 8);
      for (final arr in smoothed.values) {
        expect(arr.length, n);
      }

      // ─── 3. Classify terrain ─────────────────────────────────────
      final terrain = TerrainService.classify(
        startAltitude: altitude.first,
        endAltitude: altitude.last,
        distance: 100.0,
      );
      // Slope = (100.099 - 100.0) / 100 = 0.00099 → Plain
      expect(terrain, AppConstants.terrainPlain);

      // ─── 4. Compute 120 features ─────────────────────────────────
      final Map<String, double> allFeatures = {};

      for (final attrName in AppConstants.attributeNames) {
        final signal = smoothed[attrName]!;

        // 11 time-domain features
        final td = FeatureEngine.computeTimeDomain(signal);
        expect(td.length, 11);
        for (final e in td.entries) {
          allFeatures['${attrName}_${e.key}'] = e.value;
        }

        // 4 frequency-domain features
        final fd = FftEngine.computeFrequencyDomain(signal);
        expect(fd.length, 4);
        for (final e in fd.entries) {
          allFeatures['${attrName}_${e.key}'] = e.value;
        }
      }

      // Verify total feature count: 8 attributes × 15 features = 120
      expect(allFeatures.length, AppConstants.totalFeaturesPerSegment);

      // ─── 5. Verify no NaN or Infinity ────────────────────────────
      for (final entry in allFeatures.entries) {
        expect(entry.value.isNaN, false,
            reason: '${entry.key} is NaN');
        expect(entry.value.isInfinite, false,
            reason: '${entry.key} is Infinite');
      }

      // ─── 6. Compute deviation against benchmarks ─────────────────
      final devResult = DeviationEngine.computeSegmentDeviation(
        terrain: terrain,
        featureValues: allFeatures,
      );

      expect(devResult.cluster0Deviation >= 0, true);
      expect(devResult.cluster1Deviation >= 0, true);
      expect(devResult.matchedCluster, anyOf(0, 1));
      expect(devResult.featureDeviations.length, 10);

      // ─── 7. Verify deterministic results ─────────────────────────
      // Run again with same input — should get identical results
      final devResult2 = DeviationEngine.computeSegmentDeviation(
        terrain: terrain,
        featureValues: allFeatures,
      );

      expect(devResult2.cluster0Deviation, devResult.cluster0Deviation);
      expect(devResult2.cluster1Deviation, devResult.cluster1Deviation);
      expect(devResult2.matchedCluster, devResult.matchedCluster);
    });

    test('all terrain types produce valid results', () {
      final random = Random(123);
      const int n = 50;

      for (final terrainType in [
        AppConstants.terrainPlain,
        AppConstants.terrainUphill,
        AppConstants.terrainDownhill,
      ]) {
        final Map<String, double> features = {};

        for (final attr in AppConstants.attributeNames) {
          final signal =
              List.generate(n, (_) => random.nextDouble() * 10 - 5);
          final td = FeatureEngine.computeTimeDomain(signal);
          final fd = FftEngine.computeFrequencyDomain(signal);

          for (final e in td.entries) {
            features['${attr}_${e.key}'] = e.value;
          }
          for (final e in fd.entries) {
            features['${attr}_${e.key}'] = e.value;
          }
        }

        final result = DeviationEngine.computeSegmentDeviation(
          terrain: terrainType,
          featureValues: features,
        );

        expect(result.featureDeviations.length, 10,
            reason: '$terrainType should use 10 features');
        expect(result.matchedCluster, anyOf(0, 1));
      }
    });

    test('benchmark tables have correct structure', () {
      for (final terrain in [
        AppConstants.terrainPlain,
        AppConstants.terrainUphill,
        AppConstants.terrainDownhill,
      ]) {
        final features = BenchmarkTables.getFeaturesForTerrain(terrain);
        expect(features.length, 10,
            reason: '$terrain should have 10 benchmark features');

        for (final f in features) {
          // Each range should have min < max
          expect(f.cluster0.min <= f.cluster0.max, true,
              reason:
                  '$terrain ${f.featureKey} cluster0 min > max');
          expect(f.cluster1.min <= f.cluster1.max, true,
              reason:
                  '$terrain ${f.featureKey} cluster1 min > max');

          // Feature key should be in format "Attr_Feature"
          expect(f.featureKey.contains('_'), true);
        }
      }
    });
  });
}
