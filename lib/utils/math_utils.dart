import 'dart:math';

/// Safe division: returns [fallback] if denominator is 0 or near-zero.
double safeDivide(double numerator, double denominator,
    {double fallback = 0.0, double epsilon = 1e-12}) {
  if (denominator.abs() < epsilon) return fallback;
  return numerator / denominator;
}

/// Clamp a value to [minVal, maxVal].
double clampValue(double value, double minVal, double maxVal) {
  if (value < minVal) return minVal;
  if (value > maxVal) return maxVal;
  return value;
}

/// Next power of 2 >= n.
int nextPowerOf2(int n) {
  if (n <= 1) return 1;
  int power = 1;
  while (power < n) {
    power <<= 1;
  }
  return power;
}

/// Log base 2.
double log2(double x) {
  if (x <= 0) return 0.0;
  return log(x) / ln2;
}

/// Check if all values in a list are zero.
bool allZeros(List<double> values) {
  return values.every((v) => v.abs() < 1e-12);
}

/// Compute derivative: d(values)/d(time).
/// Returns a list of length values.length - 1.
List<double> computeDerivative(List<double> values, List<int> timestamps) {
  if (values.length < 2) return [];

  final List<double> derivatives = [];
  for (int i = 1; i < values.length; i++) {
    final double dt = (timestamps[i] - timestamps[i - 1]) / 1000.0; // ms → s
    if (dt.abs() < 1e-6) {
      derivatives.add(0.0);
    } else {
      derivatives.add((values[i] - values[i - 1]) / dt);
    }
  }
  return derivatives;
}
