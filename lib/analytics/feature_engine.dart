import 'dart:math';
import '../utils/math_utils.dart';

/// Computes the 11 time-domain features for a single attribute signal.
///
/// Features (per spec):
///   1.  Max             = max(T)
///   2.  Min             = min(T)
///   3.  Mean            = (1/n) Σ Ti
///   4.  Std             = sqrt( (1/(n−1)) Σ (Ti − Mean)² )
///   5.  Peak-to-Peak    = Max − Min
///   6.  ARV             = (1/n) Σ |Ti|
///   7.  RMS             = sqrt( (1/n) Σ Ti² )
///   8.  Shape Factor    = RMS / ARV
///   9.  Crest Factor    = Max / RMS
///  10.  Impulse Factor  = Max / ARV
///  11.  Margin Factor   = Max / ( (1/n Σ √|Ti|)² )
class FeatureEngine {
  FeatureEngine._();

  /// Compute all 11 time-domain features for a signal.
  /// Returns a Map with feature name → value.
  static Map<String, double> computeTimeDomain(List<double> signal) {
    final int n = signal.length;

    if (n == 0) {
      return _emptyTimeDomain();
    }

    // ─── Basic statistics ──────────────────────────────────────────
    double maxVal = signal[0];
    double minVal = signal[0];
    double sum = 0.0;
    double sumAbs = 0.0;
    double sumSq = 0.0;
    double sumSqrtAbs = 0.0;

    for (int i = 0; i < n; i++) {
      final double v = signal[i];
      if (v > maxVal) maxVal = v;
      if (v < minVal) minVal = v;
      sum += v;
      sumAbs += v.abs();
      sumSq += v * v;
      sumSqrtAbs += sqrt(v.abs());
    }

    final double mean = sum / n;

    // ─── Standard deviation (sample, n-1) ──────────────────────────
    double sumDevSq = 0.0;
    for (int i = 0; i < n; i++) {
      final double dev = signal[i] - mean;
      sumDevSq += dev * dev;
    }
    final double std = n > 1 ? sqrt(sumDevSq / (n - 1)) : 0.0;

    // ─── Derived features ──────────────────────────────────────────
    final double peakToPeak = maxVal - minVal;
    final double arv = sumAbs / n;
    final double rms = sqrt(sumSq / n);

    // Shape Factor = RMS / ARV
    final double shapeFactor = safeDivide(rms, arv);

    // Crest Factor = Max / RMS
    final double crestFactor = safeDivide(maxVal, rms);

    // Impulse Factor = Max / ARV
    final double impulseFactor = safeDivide(maxVal, arv);

    // Margin Factor = Max / ((1/n Σ √|Ti|)²)
    final double meanSqrtAbs = sumSqrtAbs / n;
    final double marginDenom = meanSqrtAbs * meanSqrtAbs;
    final double marginFactor = safeDivide(maxVal, marginDenom);

    return {
      'Max': maxVal,
      'Min': minVal,
      'Mean': mean,
      'Std': std,
      'PeakToPeak': peakToPeak,
      'ARV': arv,
      'RMS': rms,
      'ShapeFactor': shapeFactor,
      'CrestFactor': crestFactor,
      'ImpulseFactor': impulseFactor,
      'MarginFactor': marginFactor,
    };
  }

  /// Returns zero-value map when signal is empty.
  static Map<String, double> _emptyTimeDomain() {
    return {
      'Max': 0.0,
      'Min': 0.0,
      'Mean': 0.0,
      'Std': 0.0,
      'PeakToPeak': 0.0,
      'ARV': 0.0,
      'RMS': 0.0,
      'ShapeFactor': 0.0,
      'CrestFactor': 0.0,
      'ImpulseFactor': 0.0,
      'MarginFactor': 0.0,
    };
  }
}
