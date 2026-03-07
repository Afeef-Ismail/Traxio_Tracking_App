import '../config/constants.dart';

/// Classifies terrain based on slope computed from altitude change
/// over segment distance.
///
/// slope = Δheight / Δdistance
///
/// Classification:
///   slope > +0.02  → Uphill
///   slope < −0.02  → Downhill
///   else           → Plain
class TerrainService {
  TerrainService._();

  /// Classify terrain for a segment given its altitude endpoints and distance.
  static String classify({
    required double startAltitude,
    required double endAltitude,
    required double distance,
  }) {
    if (distance <= 0) return AppConstants.terrainPlain;

    final double slope = (endAltitude - startAltitude) / distance;

    if (slope > AppConstants.uphillSlopeThreshold) {
      return AppConstants.terrainUphill;
    } else if (slope < AppConstants.downhillSlopeThreshold) {
      return AppConstants.terrainDownhill;
    } else {
      return AppConstants.terrainPlain;
    }
  }

  /// Classify terrain using a custom slope threshold (from Settings).
  static String classifyWithThreshold({
    required double startAltitude,
    required double endAltitude,
    required double distance,
    required double threshold,
  }) {
    if (distance <= 0) return AppConstants.terrainPlain;

    final double slope = (endAltitude - startAltitude) / distance;

    if (slope > threshold) {
      return AppConstants.terrainUphill;
    } else if (slope < -threshold) {
      return AppConstants.terrainDownhill;
    } else {
      return AppConstants.terrainPlain;
    }
  }

  /// Compute the raw slope value.
  static double computeSlope({
    required double startAltitude,
    required double endAltitude,
    required double distance,
  }) {
    if (distance <= 0) return 0.0;
    return (endAltitude - startAltitude) / distance;
  }
}
