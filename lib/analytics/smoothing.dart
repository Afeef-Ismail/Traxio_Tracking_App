/// 3-point moving average smoothing.
///
/// Applies: Smoothed[i] = (x[i−1] + x[i] + x[i+1]) / 3
///
/// Boundary handling:
///   - First element: (x[0] + x[1]) / 2
///   - Last element:  (x[n-2] + x[n-1]) / 2
///
/// No Kalman, no Butterworth — research-exact implementation.
class Smoothing {
  Smoothing._();

  /// Apply 3-point moving average to a single signal.
  static List<double> smooth(List<double> data) {
    if (data.isEmpty) return [];
    if (data.length == 1) return [data[0]];
    if (data.length == 2) {
      final avg = (data[0] + data[1]) / 2.0;
      return [avg, avg];
    }

    final int n = data.length;
    final List<double> result = List<double>.filled(n, 0.0);

    // First element: 2-point average
    result[0] = (data[0] + data[1]) / 2.0;

    // Middle elements: 3-point moving average
    for (int i = 1; i < n - 1; i++) {
      result[i] = (data[i - 1] + data[i] + data[i + 1]) / 3.0;
    }

    // Last element: 2-point average
    result[n - 1] = (data[n - 2] + data[n - 1]) / 2.0;

    return result;
  }

  /// Apply 3-point smoothing to all 8 attribute arrays in a segment buffer.
  /// Returns a map of attribute name → smoothed values.
  static Map<String, List<double>> smoothAll(
      Map<String, List<double>> rawBuffers) {
    final Map<String, List<double>> smoothed = {};
    for (final entry in rawBuffers.entries) {
      smoothed[entry.key] = smooth(entry.value);
    }
    return smoothed;
  }
}
