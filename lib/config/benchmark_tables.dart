import 'constants.dart';

/// Benchmark cluster ranges for terrain-specific feature comparison.
///
/// These tables define the 10 selected features per terrain type,
/// along with the [min, max] range for Cluster 0 and Cluster 1
/// from the master driver FCM clustering research.
///
/// SOURCE: Exact values from the Kozhikode–Sulthan Bathery route
/// research benchmark tables (FCM clustering results).
///
/// UNIT CONVENTION (must match feature extraction output):
///   Speed, VV  → km/h  (sensor m/s is converted before extraction)
///   ax, ay     → g     (sensor m/s² is divided by 9.81)
///   Jx, Jy     → g/s   (derivative of g-unit acceleration)
///   YR         → rad/s (raw gyroscope)
///   R          → m     (Speed_m/s / YR)

class BenchmarkRange {
  final double min;
  final double max;

  const BenchmarkRange(this.min, this.max);

  @override
  String toString() => 'BenchmarkRange($min, $max)';
}

class BenchmarkFeature {
  /// Full feature key: "Attribute_FeatureName" e.g. "Speed_Mean"
  final String featureKey;

  /// Cluster 0 acceptable range
  final BenchmarkRange cluster0;

  /// Cluster 1 acceptable range
  final BenchmarkRange cluster1;

  const BenchmarkFeature({
    required this.featureKey,
    required this.cluster0,
    required this.cluster1,
  });
}

class BenchmarkTables {
  BenchmarkTables._();

  /// Returns the 10 benchmark features for the given terrain type.
  static List<BenchmarkFeature> getFeaturesForTerrain(String terrain) {
    switch (terrain) {
      case AppConstants.terrainPlain:
        return plainFeatures;
      case AppConstants.terrainUphill:
        return uphillFeatures;
      case AppConstants.terrainDownhill:
        return downhillFeatures;
      default:
        return plainFeatures;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // PLAIN & ROLLING TERRAIN — 10 Selected Benchmark Features
  // Source: "Benchmark Table for Plain & Rolling Terrain"
  // ═══════════════════════════════════════════════════════════════════
  static const List<BenchmarkFeature> plainFeatures = [
    // 1. Jy_max (g/s)
    BenchmarkFeature(
      featureKey: 'Jy_Max',
      cluster0: BenchmarkRange(0.85, 3.17),
      cluster1: BenchmarkRange(1.13, 3.67),
    ),
    // 2. Jx_max (g/s)
    BenchmarkFeature(
      featureKey: 'Jx_Max',
      cluster0: BenchmarkRange(0.95, 2.66),
      cluster1: BenchmarkRange(1.40, 3.97),
    ),
    // 3. S_max (kmph)
    BenchmarkFeature(
      featureKey: 'Speed_Max',
      cluster0: BenchmarkRange(22.74, 64.48),
      cluster1: BenchmarkRange(29.94, 63.70),
    ),
    // 4. ay_fv (Hz²)
    BenchmarkFeature(
      featureKey: 'ay_FreqVariance',
      cluster0: BenchmarkRange(0.0004, 0.012),
      cluster1: BenchmarkRange(0.0012, 0.019),
    ),
    // 5. VV_min (kmph)
    BenchmarkFeature(
      featureKey: 'VV_Min',
      cluster0: BenchmarkRange(0.73, 1.70),
      cluster1: BenchmarkRange(0.68, 1.53),
    ),
    // 6. ax_max (g)
    BenchmarkFeature(
      featureKey: 'ax_Max',
      cluster0: BenchmarkRange(0.041, 0.34),
      cluster1: BenchmarkRange(0.061, 0.25),
    ),
    // 7. S_fc (Hz)
    BenchmarkFeature(
      featureKey: 'Speed_FreqCentroid',
      cluster0: BenchmarkRange(0.0007, 0.042),
      cluster1: BenchmarkRange(0.003, 0.0321),
    ),
    // 8. Jx_mf
    BenchmarkFeature(
      featureKey: 'Jx_MarginFactor',
      cluster0: BenchmarkRange(1.79, 3.60),
      cluster1: BenchmarkRange(1.87, 4.71),
    ),
    // 9. YR_se
    BenchmarkFeature(
      featureKey: 'YR_SpectralEntropy',
      cluster0: BenchmarkRange(2.46, 4.55),
      cluster1: BenchmarkRange(2.70, 4.71),
    ),
    // 10. R_se
    BenchmarkFeature(
      featureKey: 'R_SpectralEntropy',
      cluster0: BenchmarkRange(1.96, 4.16),
      cluster1: BenchmarkRange(1.44, 3.93),
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════
  // UPGRADE GHAT TERRAIN (Uphill) — 10 Selected Benchmark Features
  // Source: "Benchmark Table for Upgrade Ghat Terrain"
  // ═══════════════════════════════════════════════════════════════════
  static const List<BenchmarkFeature> uphillFeatures = [
    // 1. S_max (kmph)
    BenchmarkFeature(
      featureKey: 'Speed_Max',
      cluster0: BenchmarkRange(12.41, 37.10),
      cluster1: BenchmarkRange(15.66, 36.92),
    ),
    // 2. Jy_max (g/s)
    BenchmarkFeature(
      featureKey: 'Jy_Max',
      cluster0: BenchmarkRange(0.32, 4.11),
      cluster1: BenchmarkRange(0.88, 4.32),
    ),
    // 3. VV_max (kmph)
    BenchmarkFeature(
      featureKey: 'VV_Max',
      cluster0: BenchmarkRange(0.12, 3.64),
      cluster1: BenchmarkRange(0.32, 8.15),
    ),
    // 4. Jx_max (g/s)
    BenchmarkFeature(
      featureKey: 'Jx_Max',
      cluster0: BenchmarkRange(0.05, 3.02),
      cluster1: BenchmarkRange(0.32, 3.25),
    ),
    // 5. YR_mf
    BenchmarkFeature(
      featureKey: 'YR_MarginFactor',
      cluster0: BenchmarkRange(1.36, 4.31),
      cluster1: BenchmarkRange(1.66, 4.97),
    ),
    // 6. ax_max (g)
    BenchmarkFeature(
      featureKey: 'ax_Max',
      cluster0: BenchmarkRange(0.062, 0.25),
      cluster1: BenchmarkRange(0.098, 0.462),
    ),
    // 7. VV_pp (kmph)
    BenchmarkFeature(
      featureKey: 'VV_PeakToPeak',
      cluster0: BenchmarkRange(0.23, 2.27),
      cluster1: BenchmarkRange(0.027, 5.90),
    ),
    // 8. ax_se
    BenchmarkFeature(
      featureKey: 'ax_SpectralEntropy',
      cluster0: BenchmarkRange(3.12, 4.49),
      cluster1: BenchmarkRange(3.04, 4.33),
    ),
    // 9. Jy_se
    BenchmarkFeature(
      featureKey: 'Jy_SpectralEntropy',
      cluster0: BenchmarkRange(3.23, 4.31),
      cluster1: BenchmarkRange(3.32, 4.39),
    ),
    // 10. S_se
    BenchmarkFeature(
      featureKey: 'Speed_SpectralEntropy',
      cluster0: BenchmarkRange(0.46, 2.94),
      cluster1: BenchmarkRange(1.19, 3.21),
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════
  // DOWNGRADE GHAT TERRAIN (Downhill) — 10 Selected Benchmark Features
  // Source: "Benchmark Table for Downgrade Ghat Terrain"
  // ═══════════════════════════════════════════════════════════════════
  static const List<BenchmarkFeature> downhillFeatures = [
    // 1. S_max (kmph)
    BenchmarkFeature(
      featureKey: 'Speed_Max',
      cluster0: BenchmarkRange(18.52, 46.00),
      cluster1: BenchmarkRange(15.22, 47.61),
    ),
    // 2. S_se
    BenchmarkFeature(
      featureKey: 'Speed_SpectralEntropy',
      cluster0: BenchmarkRange(0.94, 2.94),
      cluster1: BenchmarkRange(0.36, 2.54),
    ),
    // 3. Jy_se
    BenchmarkFeature(
      featureKey: 'Jy_SpectralEntropy',
      cluster0: BenchmarkRange(3.42, 4.42),
      cluster1: BenchmarkRange(3.22, 4.24),
    ),
    // 4. ax_max (g)
    BenchmarkFeature(
      featureKey: 'ax_Max',
      cluster0: BenchmarkRange(0.12, 0.53),
      cluster1: BenchmarkRange(0.075, 0.30),
    ),
    // 5. ay_max (g)
    BenchmarkFeature(
      featureKey: 'ay_Max',
      cluster0: BenchmarkRange(0.15, 0.59),
      cluster1: BenchmarkRange(0.062, 0.486),
    ),
    // 6. Jy_max (g/s)
    BenchmarkFeature(
      featureKey: 'Jy_Max',
      cluster0: BenchmarkRange(0.75, 3.85),
      cluster1: BenchmarkRange(0.85, 4.30),
    ),
    // 7. ax_se
    BenchmarkFeature(
      featureKey: 'ax_SpectralEntropy',
      cluster0: BenchmarkRange(2.85, 4.17),
      cluster1: BenchmarkRange(3.21, 4.49),
    ),
    // 8. ax_min (g)
    BenchmarkFeature(
      featureKey: 'ax_Min',
      cluster0: BenchmarkRange(0.0018, 0.0345),
      cluster1: BenchmarkRange(0.0, 0.027),
    ),
    // 9. ax_fv (Hz²)
    BenchmarkFeature(
      featureKey: 'ax_FreqVariance',
      cluster0: BenchmarkRange(0.0011, 0.0088),
      cluster1: BenchmarkRange(0.002, 0.018),
    ),
    // 10. Jy_mf
    BenchmarkFeature(
      featureKey: 'Jy_MarginFactor',
      cluster0: BenchmarkRange(1.48, 4.10),
      cluster1: BenchmarkRange(1.65, 4.53),
    ),
  ];
}
