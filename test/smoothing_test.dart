import 'package:flutter_test/flutter_test.dart';
import 'package:traxio/analytics/smoothing.dart';

void main() {
  group('Smoothing - 3-Point Moving Average', () {
    test('empty list returns empty', () {
      expect(Smoothing.smooth([]), []);
    });

    test('single element returns same', () {
      expect(Smoothing.smooth([5.0]), [5.0]);
    });

    test('two elements returns average of both', () {
      final result = Smoothing.smooth([4.0, 6.0]);
      expect(result[0], 5.0);
      expect(result[1], 5.0);
    });

    test('three elements applies correct formula', () {
      // [2, 4, 6]
      // result[0] = (2+4)/2 = 3.0
      // result[1] = (2+4+6)/3 = 4.0
      // result[2] = (4+6)/2 = 5.0
      final result = Smoothing.smooth([2.0, 4.0, 6.0]);
      expect(result[0], 3.0);
      expect(result[1], 4.0);
      expect(result[2], 5.0);
    });

    test('five elements', () {
      // [1, 3, 5, 7, 9]
      // result[0] = (1+3)/2 = 2.0
      // result[1] = (1+3+5)/3 = 3.0
      // result[2] = (3+5+7)/3 = 5.0
      // result[3] = (5+7+9)/3 = 7.0
      // result[4] = (7+9)/2 = 8.0
      final result = Smoothing.smooth([1.0, 3.0, 5.0, 7.0, 9.0]);
      expect(result[0], 2.0);
      expect(result[1], 3.0);
      expect(result[2], 5.0);
      expect(result[3], 7.0);
      expect(result[4], 8.0);
    });

    test('all same values returns same values', () {
      final result = Smoothing.smooth([3.0, 3.0, 3.0, 3.0]);
      for (final v in result) {
        expect(v, 3.0);
      }
    });

    test('smoothAll processes multiple attributes', () {
      final raw = {
        'Speed': [1.0, 2.0, 3.0],
        'ax': [0.5, 1.0, 1.5],
      };
      final smoothed = Smoothing.smoothAll(raw);
      expect(smoothed.containsKey('Speed'), true);
      expect(smoothed.containsKey('ax'), true);
      expect(smoothed['Speed']!.length, 3);
    });
  });
}
