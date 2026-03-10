import '../config/constants.dart';

/// Computes a trip-level score (0–100) from the overall average deviation.
///
/// Formula: score = max(0, (100 − (deviation / maxExpected) × 100)).round()
///   where maxExpected = AppConstants.maxExpectedDeviation (default 50.0).
///
/// Score colours:
///   - 80–100  Green  (#4CAF50)
///   - 50–79   Yellow (#FFC107)
///   - 0–49    Red    (#F44336)
class ScoreCalculator {
  /// Compute a 0–100 integer score from the overall average deviation.
  static int computeScore(double overallAvgDeviation) {
    final maxDev = AppConstants.maxExpectedDeviation;
    final raw = 100.0 - (overallAvgDeviation / maxDev) * 100.0;
    return raw.clamp(0, 100).round();
  }
}
