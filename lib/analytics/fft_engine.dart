import 'dart:math';
import '../utils/math_utils.dart';

/// Computes the 4 frequency-domain features using DFT.
///
/// Features:
///   12. Average Amplitude  = (1/m) Σ |X(k)|
///   13. Frequency Centroid = (Σ fk·|X(k)|) / (Σ |X(k)|)
///   14. Frequency Variance = (Σ (fk − fc)²·|X(k)|) / (Σ |X(k)|)
///   15. Spectral Entropy   = −Σ P(k)·log₂(P(k))
///
/// Uses a hand-rolled Cooley-Tukey FFT for performance.
/// Zero-pads input to next power of 2.
class FftEngine {
  FftEngine._();

  /// Sampling rate in Hz.
  static const double _fs = 10.0;

  /// Compute all 4 frequency-domain features for a signal.
  static Map<String, double> computeFrequencyDomain(List<double> signal) {
    if (signal.isEmpty || signal.length < 2) {
      return _emptyFreqDomain();
    }

    // ─── Zero-pad to next power of 2 ───────────────────────────────
    final int n = nextPowerOf2(signal.length);
    final List<double> real = List<double>.filled(n, 0.0);
    final List<double> imag = List<double>.filled(n, 0.0);

    for (int i = 0; i < signal.length; i++) {
      real[i] = signal[i];
    }

    // ─── In-place FFT ──────────────────────────────────────────────
    _fft(real, imag, false);

    // ─── Compute magnitude spectrum (one-sided: 0..n/2) ────────────
    final int halfN = n ~/ 2;
    final List<double> magnitudes = List<double>.filled(halfN, 0.0);
    final List<double> frequencies = List<double>.filled(halfN, 0.0);

    final double freqResolution = _fs / n;

    for (int k = 0; k < halfN; k++) {
      magnitudes[k] = sqrt(real[k] * real[k] + imag[k] * imag[k]);
      frequencies[k] = k * freqResolution;
    }

    // ─── Feature 12: Average Amplitude ─────────────────────────────
    double sumMag = 0.0;
    for (int k = 0; k < halfN; k++) {
      sumMag += magnitudes[k];
    }
    final double avgAmplitude = safeDivide(sumMag, halfN.toDouble());

    // ─── Feature 13: Frequency Centroid ────────────────────────────
    double sumFkMag = 0.0;
    for (int k = 0; k < halfN; k++) {
      sumFkMag += frequencies[k] * magnitudes[k];
    }
    final double freqCentroid = safeDivide(sumFkMag, sumMag);

    // ─── Feature 14: Frequency Variance ────────────────────────────
    double sumVarMag = 0.0;
    for (int k = 0; k < halfN; k++) {
      final double diff = frequencies[k] - freqCentroid;
      sumVarMag += diff * diff * magnitudes[k];
    }
    final double freqVariance = safeDivide(sumVarMag, sumMag);

    // ─── Feature 15: Spectral Entropy ──────────────────────────────
    // Normalize magnitudes to probability distribution
    double spectralEntropy = 0.0;
    if (sumMag > 0) {
      for (int k = 0; k < halfN; k++) {
        final double pk = magnitudes[k] / sumMag;
        if (pk > 1e-12) {
          spectralEntropy -= pk * log2(pk);
        }
      }
    }

    return {
      'AvgAmplitude': avgAmplitude,
      'FreqCentroid': freqCentroid,
      'FreqVariance': freqVariance,
      'SpectralEntropy': spectralEntropy,
    };
  }

  /// Empty frequency domain features.
  static Map<String, double> _emptyFreqDomain() {
    return {
      'AvgAmplitude': 0.0,
      'FreqCentroid': 0.0,
      'FreqVariance': 0.0,
      'SpectralEntropy': 0.0,
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Cooley-Tukey FFT (iterative, in-place, radix-2)
  // ═══════════════════════════════════════════════════════════════════

  /// In-place FFT. [inverse] = true for IFFT.
  /// [real] and [imag] must have length that is a power of 2.
  static void _fft(List<double> real, List<double> imag, bool inverse) {
    final int n = real.length;
    if (n <= 1) return;

    // Bit-reversal permutation
    int j = 0;
    for (int i = 0; i < n; i++) {
      if (i < j) {
        // Swap real
        double temp = real[i];
        real[i] = real[j];
        real[j] = temp;
        // Swap imag
        temp = imag[i];
        imag[i] = imag[j];
        imag[j] = temp;
      }
      int m = n >> 1;
      while (m >= 1 && j >= m) {
        j -= m;
        m >>= 1;
      }
      j += m;
    }

    // Cooley-Tukey butterfly
    for (int size = 2; size <= n; size <<= 1) {
      final int halfSize = size >> 1;
      final double angle =
          (inverse ? 2.0 : -2.0) * pi / size;

      final double wReal = cos(angle);
      final double wImag = sin(angle);

      for (int i = 0; i < n; i += size) {
        double curReal = 1.0;
        double curImag = 0.0;

        for (int k = 0; k < halfSize; k++) {
          final int evenIdx = i + k;
          final int oddIdx = i + k + halfSize;

          final double tReal =
              curReal * real[oddIdx] - curImag * imag[oddIdx];
          final double tImag =
              curReal * imag[oddIdx] + curImag * real[oddIdx];

          real[oddIdx] = real[evenIdx] - tReal;
          imag[oddIdx] = imag[evenIdx] - tImag;
          real[evenIdx] += tReal;
          imag[evenIdx] += tImag;

          // Advance twiddle factor
          final double newCurReal =
              curReal * wReal - curImag * wImag;
          curImag = curReal * wImag + curImag * wReal;
          curReal = newCurReal;
        }
      }
    }

    // Normalize for inverse FFT
    if (inverse) {
      for (int i = 0; i < n; i++) {
        real[i] /= n;
        imag[i] /= n;
      }
    }
  }
}
