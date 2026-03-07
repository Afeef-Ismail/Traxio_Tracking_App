import 'package:flutter_test/flutter_test.dart';
import 'package:ksrtc_app/services/terrain_service.dart';
import 'package:ksrtc_app/config/constants.dart';

void main() {
  group('TerrainService', () {
    test('flat terrain (slope ≈ 0) → Plain', () {
      final result = TerrainService.classify(
        startAltitude: 100.0,
        endAltitude: 100.5,
        distance: 100.0,
      );
      // slope = 0.5/100 = 0.005 < 0.02
      expect(result, AppConstants.terrainPlain);
    });

    test('uphill (slope > 0.02) → Uphill', () {
      final result = TerrainService.classify(
        startAltitude: 100.0,
        endAltitude: 105.0,
        distance: 100.0,
      );
      // slope = 5/100 = 0.05 > 0.02
      expect(result, AppConstants.terrainUphill);
    });

    test('downhill (slope < -0.02) → Downhill', () {
      final result = TerrainService.classify(
        startAltitude: 105.0,
        endAltitude: 100.0,
        distance: 100.0,
      );
      // slope = -5/100 = -0.05 < -0.02
      expect(result, AppConstants.terrainDownhill);
    });

    test('borderline uphill (slope = exactly 0.02) → Plain', () {
      final result = TerrainService.classify(
        startAltitude: 100.0,
        endAltitude: 102.0,
        distance: 100.0,
      );
      // slope = 2/100 = 0.02, not > 0.02 so Plain
      expect(result, AppConstants.terrainPlain);
    });

    test('zero distance → Plain', () {
      final result = TerrainService.classify(
        startAltitude: 100.0,
        endAltitude: 200.0,
        distance: 0.0,
      );
      expect(result, AppConstants.terrainPlain);
    });

    test('computeSlope returns correct value', () {
      final slope = TerrainService.computeSlope(
        startAltitude: 100.0,
        endAltitude: 110.0,
        distance: 200.0,
      );
      expect(slope, 0.05);
    });

    test('steep ghat section classification', () {
      // Typical Kozhikode-Bathery ghat: 700m rise over 10km
      final result = TerrainService.classify(
        startAltitude: 100.0,
        endAltitude: 107.0,
        distance: 100.0,
      );
      // slope = 7/100 = 0.07 → Uphill
      expect(result, AppConstants.terrainUphill);
    });
  });
}
