import '../models/segment_model.dart';
import '../models/feature_result.dart';
import '../models/trip_model.dart';
import '../models/cluster_model.dart';
import '../services/segmentation_service.dart';
import '../services/terrain_service.dart';
import '../analytics/smoothing.dart';
import '../analytics/feature_engine.dart';
import '../analytics/fft_engine.dart';
import '../analytics/deviation_engine.dart';
import '../config/constants.dart';
import '../config/benchmark_tables.dart';
import '../utils/math_utils.dart';
import '../utils/landmark_utils.dart';
import '../database/db_helper.dart';

/// Result returned after processing a segment, exposing data
/// needed by the UI layer.
class SegmentProcessResult {
  final int segmentId;
  final String terrain;
  final int matchedCluster;
  final double cluster0Deviation;
  final double cluster1Deviation;
  final bool isValid;

  SegmentProcessResult({
    required this.segmentId,
    required this.terrain,
    required this.matchedCluster,
    required this.cluster0Deviation,
    required this.cluster1Deviation,
    required this.isValid,
  });

  double get matchedDeviation =>
      matchedCluster == 0 ? cluster0Deviation : cluster1Deviation;
}

/// Orchestrates the full segment processing pipeline:
///   1. Extract 8 attribute arrays from raw samples
///   2. Derive Jx, Jy, VV, R
///   3. Apply 3-point smoothing
///   4. Classify terrain
///   5. Compute 120 features (15 × 8 attributes)
///   6. Score against benchmark clusters
///   7. Persist everything to database
class TripProcessor {
  final DbHelper _db = DbHelper();
  String _tripId = '';
  String _mode = 'benchmark';
  double _segmentDistanceM = AppConstants.segmentDistanceMeters;

  /// Slope threshold — can be updated from Settings.
  double slopeThreshold = AppConstants.uphillSlopeThreshold;

  void init(
    String tripId, {
    String mode = 'benchmark',
    double segmentDistanceM = 100.0,
  }) {
    _tripId = tripId;
    _mode = mode;
    _segmentDistanceM = segmentDistanceM;
  }

  String get mode => _mode;
  String get tripId => _tripId;
  double get segmentDistanceM => _segmentDistanceM;

  /// Cached benchmark features per terrain (fallback), loaded from DB once per trip.
  final Map<String, List<BenchmarkFeature>> _benchmarkCache = {};

  /// Active dynamic clusters loaded from DB.
  List<ClusterDefinition> _activeClusters = [];

  /// Cache of cluster features keyed by "clusterId_terrain".
  final Map<String, List<ClusterFeatureRange>> _clusterFeaturesCache = {};

  /// Load and cache benchmark features (fallback) and active clusters from DB.
  ///
  /// [vehicleType] optionally filters which clusters are loaded.
  Future<void> loadBenchmarks({String? vehicleType}) async {
    // Load fallback benchmark_config for each terrain
    for (final terrain in [
      AppConstants.terrainPlain,
      AppConstants.terrainUphill,
      AppConstants.terrainDownhill,
    ]) {
      _benchmarkCache[terrain] = await _db.getBenchmarkFeatures(terrain);
    }

    // Load active dynamic clusters (filtered by vehicle type if specified)
    final allActive = await _db.getActiveClusters();
    if (vehicleType != null && vehicleType.isNotEmpty) {
      _activeClusters = allActive
          .where((c) => c.vehicleType == vehicleType)
          .toList();
      // Fall back to all active if no clusters match the vehicle type
      if (_activeClusters.isEmpty) {
        _activeClusters = allActive;
      }
    } else {
      _activeClusters = allActive;
    }

    // Load features for each active cluster
    for (final cluster in _activeClusters) {
      if (cluster.id == null) continue;
      for (final terrain in [
        AppConstants.terrainPlain,
        AppConstants.terrainUphill,
        AppConstants.terrainDownhill,
      ]) {
        final cacheKey = '${cluster.id}_$terrain';
        _clusterFeaturesCache[cacheKey] =
            await _db.getClusterFeatures(cluster.id!, terrain);
      }
    }
  }

  /// Clear the benchmark cache (call when trip ends or benchmarks change).
  void clearBenchmarkCache() {
    _benchmarkCache.clear();
    _activeClusters = [];
    _clusterFeaturesCache.clear();
  }

  /// Process a completed 100m segment.
  /// Returns a [SegmentProcessResult] with terrain, cluster, and deviation.
  Future<SegmentProcessResult> processSegment(SegmentData segData) async {
    final samples = segData.samples;
    if (samples.isEmpty) {
      return SegmentProcessResult(
        segmentId: -1,
        terrain: 'N/A',
        matchedCluster: -1,
        cluster0Deviation: 0,
        cluster1Deviation: 0,
        isValid: false,
      );
    }

    // ─── 1. Extract base attribute arrays ──────────────────────────
    final List<double> speedArr = [];
    final List<double> ayArr = [];
    final List<double> axArr = [];
    final List<double> yrArr = [];
    final List<double> altArr = [];
    final List<int> tsArr = [];

    for (final s in samples) {
      speedArr.add(s.speed);
      ayArr.add(s.ay);
      axArr.add(s.ax);
      yrArr.add(s.yawRate);
      altArr.add(s.altitude);
      tsArr.add(s.timestamp);
    }

    // ─── 2. Derive attributes ──────────────────────────────────────
    // Jx = d(ax)/dt  — Lateral Jerk
    final List<double> jxArr = computeDerivative(axArr, tsArr);
    // Jy = d(ay)/dt  — Longitudinal Jerk
    final List<double> jyArr = computeDerivative(ayArr, tsArr);
    // VV = d(altitude)/dt — Vertical Velocity
    final List<double> vvArr = computeDerivative(altArr, tsArr);
    // R = V / YR — Radius of Turn (with capping)
    final List<double> rArr = _computeRadius(speedArr, yrArr);

    // Trim base arrays to match derived array length (n-1)
    final int derivedLen = jxArr.length;
    final List<double> speedTrimmed = speedArr.sublist(1);
    final List<double> ayTrimmed = ayArr.sublist(1);
    final List<double> axTrimmed = axArr.sublist(1);
    final List<double> yrTrimmed = yrArr.sublist(1);
    final List<double> rTrimmed =
        rArr.length > derivedLen ? rArr.sublist(1) : rArr;

    // ─── 2b. Convert to RESEARCH units ─────────────────────────────
    // Benchmark tables use these units:
    //   Speed, VV  → km/h   (sensor gives m/s)
    //   ax, ay     → g      (sensor gives m/s²)
    //   Jx, Jy     → g/s    (derivative of m/s² = m/s³ → ÷9.81)
    //   YR         → rad/s  (already correct)
    //   R          → m      (already correct: m/s ÷ rad/s)
    const double _g = 9.80665; // standard gravity
    final speedConverted = speedTrimmed.map((v) => v * 3.6).toList();
    final axConverted = axTrimmed.map((v) => v / _g).toList();
    final ayConverted = ayTrimmed.map((v) => v / _g).toList();
    final jxConverted = jxArr.map((v) => v / _g).toList();
    final jyConverted = jyArr.map((v) => v / _g).toList();
    final vvConverted = vvArr.map((v) => v * 3.6).toList();

    // ─── 3. Apply 3-point smoothing ────────────────────────────────
    final Map<String, List<double>> rawBuffers = {
      'Speed': speedConverted,
      'ay': ayConverted,
      'ax': axConverted,
      'YR': yrTrimmed,
      'Jx': jxConverted,
      'Jy': jyConverted,
      'VV': vvConverted,
      'R': rTrimmed,
    };

    final smoothed = Smoothing.smoothAll(rawBuffers);

    // ─── 4. Classify terrain (with configurable threshold) ────────
    final String terrain = TerrainService.classifyWithThreshold(
      startAltitude: segData.startAltitude,
      endAltitude: segData.endAltitude,
      distance: segData.distance,
      threshold: slopeThreshold,
    );

    // ─── 5. Check for all-zeros (invalid segment) ──────────────────
    bool isValid = true;
    for (final entry in smoothed.entries) {
      if (allZeros(entry.value)) {
        // If ALL attributes are zero, mark invalid
        if (smoothed.values.every((arr) => allZeros(arr))) {
          isValid = false;
          break;
        }
      }
    }

    // ─── 6. Save segment to database ───────────────────────────────
    final nearestLandmark = LandmarkUtils.getNearestLandmark(
      segData.endLat,
      segData.endLon,
    );

    final segment = Segment(
      tripId: segData.tripId,
      mode: _mode,
      segmentIndex: segData.segmentIndex,
      startTime: segData.startTime,
      endTime: segData.endTime,
      terrain: terrain,
      distance: segData.distance,
      startLat: segData.startLat,
      startLon: segData.startLon,
      endLat: segData.endLat,
      endLon: segData.endLon,
      startAltitude: segData.startAltitude,
      endAltitude: segData.endAltitude,
      isValid: isValid,
      nearestLandmark: nearestLandmark,
    );

    final int segmentId = await _db.insertSegment(segment);

    if (!isValid) {
      return SegmentProcessResult(
        segmentId: segmentId,
        terrain: terrain,
        matchedCluster: -1,
        cluster0Deviation: 0,
        cluster1Deviation: 0,
        isValid: false,
      );
    }

    // ─── 7. Compute 120 features ───────────────────────────────────
    final Map<String, double> allFeatures = {};

    for (final attrName in AppConstants.attributeNames) {
      final signal = smoothed[attrName] ?? [];

      // 11 time-domain features
      final timeDomain = FeatureEngine.computeTimeDomain(signal);
      for (final entry in timeDomain.entries) {
        allFeatures['${attrName}_${entry.key}'] = entry.value;
      }

      // 4 frequency-domain features
      final freqDomain = FftEngine.computeFrequencyDomain(signal);
      for (final entry in freqDomain.entries) {
        allFeatures['${attrName}_${entry.key}'] = entry.value;
      }
    }

    // ─── 8. Save features ──────────────────────────────────────────
    final featureResults = allFeatures.entries
        .map((e) => FeatureResult(
              segmentId: segmentId,
              featureName: e.key,
              value: e.value,
            ))
        .toList();

    await _db.insertFeatures(featureResults);

    if (_mode == 'collection') {
      return SegmentProcessResult(
        segmentId: segmentId,
        terrain: terrain,
        matchedCluster: -1,
        cluster0Deviation: 0,
        cluster1Deviation: 0,
        isValid: true,
      );
    }

    // ─── 9. Compute deviation scores ───────────────────────────────
    SegmentScore score;

    if (_activeClusters.isNotEmpty) {
      // Dynamic cluster scoring
      final dynResult = DeviationEngine.computeSegmentDeviationDynamic(
        featureValues: allFeatures,
        clusters: _activeClusters,
        featuresCache: _clusterFeaturesCache,
        terrain: terrain,
      );

      // bestClusterName can be '' if no cluster features are cached (empty
      // cluster_features table). Fall back to the first active cluster name so
      // matched_cluster_name is never stored as an empty string, which would
      // cause getClusterMatchCounts() to return an empty map.
      final clusterName = dynResult.bestClusterName.isNotEmpty
          ? dynResult.bestClusterName
          : _activeClusters.first.name;

      score = SegmentScore(
        segmentId: segmentId,
        cluster0Deviation: dynResult.cluster0Deviation,
        cluster1Deviation: dynResult.cluster1Deviation,
        matchedCluster: dynResult.matchedClusterIndex,
        matchedClusterName: clusterName,
      );
    } else {
      // Fallback: use hardcoded benchmark_config (no active clusters)
      final devResult = DeviationEngine.computeSegmentDeviation(
        terrain: terrain,
        featureValues: allFeatures,
        benchmarkFeatures: _benchmarkCache[terrain],
      );

      score = SegmentScore(
        segmentId: segmentId,
        cluster0Deviation: devResult.cluster0Deviation,
        cluster1Deviation: devResult.cluster1Deviation,
        matchedCluster: devResult.matchedCluster,
        matchedClusterName: devResult.matchedCluster == 0
            ? 'Master Driver A'
            : 'Master Driver B',
      );
    }

    await _db.insertSegmentScore(score);

    return SegmentProcessResult(
      segmentId: segmentId,
      terrain: terrain,
      matchedCluster: score.matchedCluster,
      cluster0Deviation: score.cluster0Deviation,
      cluster1Deviation: score.cluster1Deviation,
      isValid: true,
    );
  }

  /// Compute Radius of Turn: R = V / |YR|, capped.
  List<double> _computeRadius(List<double> speed, List<double> yawRate) {
    final List<double> result = [];
    for (int i = 0; i < speed.length; i++) {
      if (yawRate[i].abs() < AppConstants.minYawRateForRadius) {
        result.add(AppConstants.maxRadiusOfTurn);
      } else {
        final double r = speed[i] / yawRate[i].abs();
        result.add(r.clamp(-AppConstants.maxRadiusOfTurn,
            AppConstants.maxRadiusOfTurn));
      }
    }
    return result;
  }
}
