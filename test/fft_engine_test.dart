import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:ksrtc_app/analytics/fft_engine.dart';

void main() {
  group('FftEngine - Frequency Domain Features', () {
    test('empty signal returns zeros', () {
      final result = FftEngine.computeFrequencyDomain([]);
      expect(result['AvgAmplitude'], 0.0);
      expect(result['FreqCentroid'], 0.0);
      expect(result['FreqVariance'], 0.0);
      expect(result['SpectralEntropy'], 0.0);
    });

    test('single sample returns zeros', () {
      final result = FftEngine.computeFrequencyDomain([1.0]);
      expect(result['AvgAmplitude'], 0.0);
    });

    test('DC signal produces non-zero avg amplitude', () {
      // Constant signal: all FFT energy at DC (bin 0)
      final signal = List.filled(16, 3.0);
      final result = FftEngine.computeFrequencyDomain(signal);

      expect(result['AvgAmplitude']! > 0, true);
    });

    test('pure sine wave produces energy at expected frequency', () {
      // 10 Hz sampling, 2.5 Hz sine → should have peak at bin 4
      // for n=16: freq resolution = 10/16 = 0.625 Hz
      // 2.5 Hz / 0.625 = bin 4
      const int n = 16;
      const double fs = 10.0;
      const double freq = 2.5;
      final signal = List.generate(
          n, (i) => sin(2 * pi * freq * i / fs));

      final result = FftEngine.computeFrequencyDomain(signal);

      // Frequency centroid should be near 2.5 Hz
      expect(result['FreqCentroid']!,
          closeTo(2.5, 0.5));

      // Should have non-zero spectral entropy
      expect(result['SpectralEntropy']! > 0, true);
    });

    test('white noise has high spectral entropy', () {
      // Pseudo-random signal should have higher entropy than sine
      final random = Random(42);
      final noise =
          List.generate(64, (_) => random.nextDouble() * 2 - 1);
      final sine = List.generate(
          64, (i) => sin(2 * pi * 2.0 * i / 10.0));

      final noiseResult = FftEngine.computeFrequencyDomain(noise);
      final sineResult = FftEngine.computeFrequencyDomain(sine);

      // Noise should have higher entropy than pure sine
      expect(noiseResult['SpectralEntropy']!,
          greaterThan(sineResult['SpectralEntropy']!));
    });

    test('returns exactly 4 features', () {
      final result = FftEngine.computeFrequencyDomain(
          [1.0, 2.0, 3.0, 4.0]);
      expect(result.length, 4);
      expect(result.containsKey('AvgAmplitude'), true);
      expect(result.containsKey('FreqCentroid'), true);
      expect(result.containsKey('FreqVariance'), true);
      expect(result.containsKey('SpectralEntropy'), true);
    });

    test('non-power-of-2 length is handled (zero-padded)', () {
      // 10 samples → zero-padded to 16
      final signal = List.generate(10, (i) => i.toDouble());
      final result = FftEngine.computeFrequencyDomain(signal);

      expect(result['AvgAmplitude']! >= 0, true);
      expect(result['SpectralEntropy']! >= 0, true);
    });
  });
}
