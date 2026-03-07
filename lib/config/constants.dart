/// Application-wide constants for the KSRTC Driver Benchmarking System.
/// All values are research-aligned and must not be changed without validation.
class AppConstants {
  AppConstants._();

  // ─── Demo Mode ─────────────────────────────────────────────────────
  /// Set to true to use simulated sensor data (for emulator/desktop testing).
  /// Set to false for real device with hardware sensors.
  static const bool demoMode = false;

  // ─── Sensor Configuration ───────────────────────────────────────────
  /// Target sampling rate in Hz
  static const int sensorSamplingRateHz = 10;

  /// Sampling interval in milliseconds (1000 / 10 Hz = 100ms)
  static const int sensorIntervalMs = 100;

  /// Duration of calibration phase in seconds
  static const int calibrationDurationSec = 2;

  /// Number of calibration samples (2s × 10Hz)
  static const int calibrationSamples = calibrationDurationSec * sensorSamplingRateHz;

  // ─── Segmentation ──────────────────────────────────────────────────
  /// Segment distance in meters
  static const double segmentDistanceMeters = 100.0;

  /// Minimum samples required for a valid segment
  static const int minSegmentSamples = 5;

  // ─── Terrain Classification ────────────────────────────────────────
  /// Slope threshold for uphill classification
  static const double uphillSlopeThreshold = 0.02;

  /// Slope threshold for downhill classification
  static const double downhillSlopeThreshold = -0.02;

  // ─── Edge Case Guards ──────────────────────────────────────────────
  /// Maximum GPS jump in meters per sample (30m at 10Hz = 300m/s)
  static const double maxGpsJumpMeters = 30.0;

  /// Maximum radius of turn value (cap for yaw_rate ≈ 0)
  static const double maxRadiusOfTurn = 10000.0;

  /// Minimum yaw rate to compute radius (avoid division by zero)
  static const double minYawRateForRadius = 0.001;

  // ─── Feature Extraction ────────────────────────────────────────────
  /// Number of attributes (Speed, ay, ax, YR, Jx, Jy, VV, R)
  static const int numAttributes = 8;

  /// Number of features per attribute (11 time + 4 frequency)
  static const int featuresPerAttribute = 15;

  /// Total features per segment
  static const int totalFeaturesPerSegment = numAttributes * featuresPerAttribute;

  /// Number of benchmark features selected per terrain
  static const int benchmarkFeaturesPerTerrain = 10;

  // ─── Attribute Names ───────────────────────────────────────────────
  static const List<String> attributeNames = [
    'Speed',
    'ay',    // Longitudinal Acceleration
    'ax',    // Lateral Acceleration
    'YR',    // Yaw Rate
    'Jx',    // Lateral Jerk
    'Jy',    // Longitudinal Jerk
    'VV',    // Vertical Velocity
    'R',     // Radius of Turn
  ];

  // ─── Feature Names (per attribute) ─────────────────────────────────
  static const List<String> featureNames = [
    // Time Domain (11)
    'Max',
    'Min',
    'Mean',
    'Std',
    'PeakToPeak',
    'ARV',
    'RMS',
    'ShapeFactor',
    'CrestFactor',
    'ImpulseFactor',
    'MarginFactor',
    // Frequency Domain (4)
    'AvgAmplitude',
    'FreqCentroid',
    'FreqVariance',
    'SpectralEntropy',
  ];

  // ─── Database ──────────────────────────────────────────────────────
  static const String dbName = 'ksrtc_benchmarking.db';
  static const int dbVersion = 1;

  // ─── Terrain Labels ────────────────────────────────────────────────
  static const String terrainPlain = 'Plain';
  static const String terrainUphill = 'Uphill';
  static const String terrainDownhill = 'Downhill';
}
