import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:traxio/analytics/feature_engine.dart';

void main() {
  group('FeatureEngine - Time Domain Features', () {
    test('empty signal returns zeros', () {
      final result = FeatureEngine.computeTimeDomain([]);
      expect(result['Max'], 0.0);
      expect(result['RMS'], 0.0);
    });

    test('single value signal', () {
      final result = FeatureEngine.computeTimeDomain([5.0]);
      expect(result['Max'], 5.0);
      expect(result['Min'], 5.0);
      expect(result['Mean'], 5.0);
      expect(result['Std'], 0.0); // n-1 = 0
      expect(result['PeakToPeak'], 0.0);
      expect(result['ARV'], 5.0);
      expect(result['RMS'], 5.0);
    });

    test('known signal [1, 2, 3, 4, 5]', () {
      final signal = [1.0, 2.0, 3.0, 4.0, 5.0];
      final result = FeatureEngine.computeTimeDomain(signal);

      expect(result['Max'], 5.0);
      expect(result['Min'], 1.0);
      expect(result['Mean'], 3.0);
      expect(result['PeakToPeak'], 4.0);

      // Std = sqrt(sum((x-3)^2) / 4) = sqrt(10/4) = sqrt(2.5) ≈ 1.5811
      expect(result['Std']!, closeTo(sqrt(2.5), 0.001));

      // ARV = (1+2+3+4+5)/5 = 3.0
      expect(result['ARV'], 3.0);

      // RMS = sqrt((1+4+9+16+25)/5) = sqrt(55/5) = sqrt(11) ≈ 3.3166
      expect(result['RMS']!, closeTo(sqrt(11.0), 0.001));

      // Shape Factor = RMS / ARV
      expect(result['ShapeFactor']!,
          closeTo(sqrt(11.0) / 3.0, 0.001));

      // Crest Factor = Max / RMS
      expect(result['CrestFactor']!,
          closeTo(5.0 / sqrt(11.0), 0.001));

      // Impulse Factor = Max / ARV
      expect(result['ImpulseFactor']!,
          closeTo(5.0 / 3.0, 0.001));
    });

    test('signal with negative values', () {
      final signal = [-2.0, -1.0, 0.0, 1.0, 2.0];
      final result = FeatureEngine.computeTimeDomain(signal);

      expect(result['Max'], 2.0);
      expect(result['Min'], -2.0);
      expect(result['Mean'], 0.0);
      expect(result['PeakToPeak'], 4.0);

      // ARV = (2+1+0+1+2)/5 = 1.2
      expect(result['ARV']!, closeTo(1.2, 0.001));
    });

    test('all zeros signal', () {
      final signal = [0.0, 0.0, 0.0, 0.0];
      final result = FeatureEngine.computeTimeDomain(signal);

      expect(result['Max'], 0.0);
      expect(result['Min'], 0.0);
      expect(result['Mean'], 0.0);
      expect(result['RMS'], 0.0);
      // Division by zero should be handled gracefully
      expect(result['ShapeFactor'], isNotNaN);
      expect(result['CrestFactor'], isNotNaN);
    });

    test('returns exactly 11 features', () {
      final result =
          FeatureEngine.computeTimeDomain([1.0, 2.0, 3.0]);
      expect(result.length, 11);
    });
  });
}
