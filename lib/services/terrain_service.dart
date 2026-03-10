import '../config/constants.dart';
import '../database/db_helper.dart';

/// Classifies terrain based on slope computed from altitude change
/// over segment distance.
///
/// slope = Δheight / Δdistance
///
/// Classification:
///   slope > +uphillThreshold  → Uphill
///   slope < downhillThreshold → Downhill
///   else                      → Plain
///
/// Thresholds are read from the config table at runtime.
/// Falls back to AppConstants if DB values are unavailable.
class TerrainService {
  TerrainService._();

  static final DbHelper _db = DbHelper();

  /// Cached thresholds (loaded once per app session).
  static double? _uphillThreshold;
  static double? _downhillThreshold;

  /// Load thresholds from the config table. Call once at startup or
  /// after threshold settings are changed.
  static Future<void> loadThresholds() async {
    final upStr = await _db.getConfig('terrain_slope_uphill_threshold');
    final downStr = await _db.getConfig('terrain_slope_downhill_threshold');
    _uphillThreshold = upStr != null ? double.tryParse(upStr) : null;
    _downhillThreshold = downStr != null ? double.tryParse(downStr) : null;
  }

  /// Get the effective uphill threshold.
  static double get _effectiveUphill =>
      _uphillThreshold ?? AppConstants.uphillSlopeThreshold;

  /// Get the effective downhill threshold.
  static double get _effectiveDownhill =>
      _downhillThreshold ?? AppConstants.downhillSlopeThreshold;

  /// Classify terrain for a segment given its altitude endpoints and distance.
  /// Uses thresholds from config table (loaded via loadThresholds()).
  static String classify({
    required double startAltitude,
    required double endAltitude,
    required double distance,
  }) {
    if (distance <= 0) return AppConstants.terrainPlain;

    final double slope = (endAltitude - startAltitude) / distance;

    if (slope > _effectiveUphill) {
      return AppConstants.terrainUphill;
    } else if (slope < _effectiveDownhill) {
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
