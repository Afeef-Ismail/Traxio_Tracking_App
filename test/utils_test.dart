import 'package:flutter_test/flutter_test.dart';
import 'package:ksrtc_app/utils/haversine.dart';
import 'package:ksrtc_app/utils/math_utils.dart';

void main() {
  group('Haversine Distance', () {
    test('same point → 0 meters', () {
      final dist = haversineDistance(11.25, 75.77, 11.25, 75.77);
      expect(dist, closeTo(0.0, 0.01));
    });

    test('Kozhikode to Sulthan Bathery ≈ 90-100 km', () {
      // Kozhikode: 11.2588, 75.7804
      // Sulthan Bathery: 11.6551, 76.2671
      final dist = haversineDistance(
          11.2588, 75.7804, 11.6551, 76.2671);
      // Straight-line distance should be ~65-70 km
      expect(dist, greaterThan(50000));
      expect(dist, lessThan(100000));
    });

    test('short distance ≈ 100 meters', () {
      // ~100m apart at equator: 0.001° longitude ≈ 111m
      final dist = haversineDistance(0.0, 0.0, 0.0, 0.001);
      expect(dist, closeTo(111.0, 15.0));
    });
  });

  group('Math Utils', () {
    test('safeDivide normal case', () {
      expect(safeDivide(10.0, 2.0), 5.0);
    });

    test('safeDivide by zero returns fallback', () {
      expect(safeDivide(10.0, 0.0), 0.0);
      expect(safeDivide(10.0, 0.0, fallback: -1.0), -1.0);
    });

    test('nextPowerOf2', () {
      expect(nextPowerOf2(1), 1);
      expect(nextPowerOf2(2), 2);
      expect(nextPowerOf2(3), 4);
      expect(nextPowerOf2(5), 8);
      expect(nextPowerOf2(10), 16);
      expect(nextPowerOf2(16), 16);
      expect(nextPowerOf2(17), 32);
    });

    test('log2', () {
      expect(log2(1.0), closeTo(0.0, 0.001));
      expect(log2(2.0), closeTo(1.0, 0.001));
      expect(log2(8.0), closeTo(3.0, 0.001));
      expect(log2(0.0), 0.0); // edge case
    });

    test('allZeros', () {
      expect(allZeros([0.0, 0.0, 0.0]), true);
      expect(allZeros([0.0, 0.001, 0.0]), false);
      expect(allZeros([]), true);
    });

    test('computeDerivative', () {
      // Values: [0, 2, 6, 12]
      // Timestamps: [0, 1000, 2000, 3000] (1 second apart)
      // Derivatives: [2.0, 4.0, 6.0]
      final derivatives = computeDerivative(
        [0.0, 2.0, 6.0, 12.0],
        [0, 1000, 2000, 3000],
      );
      expect(derivatives.length, 3);
      expect(derivatives[0], closeTo(2.0, 0.001));
      expect(derivatives[1], closeTo(4.0, 0.001));
      expect(derivatives[2], closeTo(6.0, 0.001));
    });

    test('computeDerivative with 100ms intervals (10Hz)', () {
      // Values: [0, 0.1, 0.3]
      // Timestamps: [0, 100, 200] (100ms apart = 0.1s)
      // Derivatives: [0.1/0.1=1.0, 0.2/0.1=2.0]
      final derivatives = computeDerivative(
        [0.0, 0.1, 0.3],
        [0, 100, 200],
      );
      expect(derivatives[0], closeTo(1.0, 0.001));
      expect(derivatives[1], closeTo(2.0, 0.001));
    });
  });
}
