/// Application-wide constants for the KSRTC Driver Benchmarking System.
/// All values are research-aligned and must not be changed without validation.
class AppConstants {
  AppConstants._();

  // ─── Demo Mode ─────────────────────────────────────────────────────
  /// Set to true to use simulated sensor data (for emulator/desktop testing).
  /// Set to false for real device with hardware sensors.
  static const bool demoMode = true;

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

  /// Default segment distance for Data Collection mode (admin configurable).
  static double collectionSegmentDistanceM = 100.0;

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

  // ─── Database ──────────────────────────────────────────────────────
  static const String dbName = 'ksrtc_benchmarking.db';
  static const int dbVersion = 9;

  // ─── AI Coaching ───────────────────────────────────────────────────
  static const double maxExpectedDeviation = 50.0;

  // ─── Terrain Labels ────────────────────────────────────────────────
  static const String terrainPlain = 'Plain';
  static const String terrainUphill = 'Uphill';
  static const String terrainDownhill = 'Downhill';

  // ─── Feature Units ─────────────────────────────────────────────────
  /// Maps every feature key (Attribute_FeatureName) to its display unit.
  /// Time-domain features inherit the attribute unit;
  /// frequency-domain / shape features are dimensionless ('').
  static const Map<String, String> featureUnits = {
    // ── Speed (km/h) ──────────────────────────────────────────────
    'Speed_Max': 'km/h',
    'Speed_Min': 'km/h',
    'Speed_Mean': 'km/h',
    'Speed_Std': 'km/h',
    'Speed_PeakToPeak': 'km/h',
    'Speed_ARV': 'km/h',
    'Speed_RMS': 'km/h',
    'Speed_ShapeFactor': '',
    'Speed_CrestFactor': '',
    'Speed_ImpulseFactor': '',
    'Speed_MarginFactor': '',
    'Speed_AvgAmplitude': '',
    'Speed_FreqCentroid': '',
    'Speed_FreqVariance': '',
    'Speed_SpectralEntropy': '',
    // ── ay — Longitudinal Acceleration (g) ────────────────────────
    'ay_Max': 'g',
    'ay_Min': 'g',
    'ay_Mean': 'g',
    'ay_Std': 'g',
    'ay_PeakToPeak': 'g',
    'ay_ARV': 'g',
    'ay_RMS': 'g',
    'ay_ShapeFactor': '',
    'ay_CrestFactor': '',
    'ay_ImpulseFactor': '',
    'ay_MarginFactor': '',
    'ay_AvgAmplitude': '',
    'ay_FreqCentroid': '',
    'ay_FreqVariance': '',
    'ay_SpectralEntropy': '',
    // ── ax — Lateral Acceleration (g) ─────────────────────────────
    'ax_Max': 'g',
    'ax_Min': 'g',
    'ax_Mean': 'g',
    'ax_Std': 'g',
    'ax_PeakToPeak': 'g',
    'ax_ARV': 'g',
    'ax_RMS': 'g',
    'ax_ShapeFactor': '',
    'ax_CrestFactor': '',
    'ax_ImpulseFactor': '',
    'ax_MarginFactor': '',
    'ax_AvgAmplitude': '',
    'ax_FreqCentroid': '',
    'ax_FreqVariance': '',
    'ax_SpectralEntropy': '',
    // ── YR — Yaw Rate (deg/s) ─────────────────────────────────────
    'YR_Max': 'deg/s',
    'YR_Min': 'deg/s',
    'YR_Mean': 'deg/s',
    'YR_Std': 'deg/s',
    'YR_PeakToPeak': 'deg/s',
    'YR_ARV': 'deg/s',
    'YR_RMS': 'deg/s',
    'YR_ShapeFactor': '',
    'YR_CrestFactor': '',
    'YR_ImpulseFactor': '',
    'YR_MarginFactor': '',
    'YR_AvgAmplitude': '',
    'YR_FreqCentroid': '',
    'YR_FreqVariance': '',
    'YR_SpectralEntropy': '',
    // ── Jx — Lateral Jerk (g/s) ──────────────────────────────────
    'Jx_Max': 'g/s',
    'Jx_Min': 'g/s',
    'Jx_Mean': 'g/s',
    'Jx_Std': 'g/s',
    'Jx_PeakToPeak': 'g/s',
    'Jx_ARV': 'g/s',
    'Jx_RMS': 'g/s',
    'Jx_ShapeFactor': '',
    'Jx_CrestFactor': '',
    'Jx_ImpulseFactor': '',
    'Jx_MarginFactor': '',
    'Jx_AvgAmplitude': '',
    'Jx_FreqCentroid': '',
    'Jx_FreqVariance': '',
    'Jx_SpectralEntropy': '',
    // ── Jy — Longitudinal Jerk (g/s) ─────────────────────────────
    'Jy_Max': 'g/s',
    'Jy_Min': 'g/s',
    'Jy_Mean': 'g/s',
    'Jy_Std': 'g/s',
    'Jy_PeakToPeak': 'g/s',
    'Jy_ARV': 'g/s',
    'Jy_RMS': 'g/s',
    'Jy_ShapeFactor': '',
    'Jy_CrestFactor': '',
    'Jy_ImpulseFactor': '',
    'Jy_MarginFactor': '',
    'Jy_AvgAmplitude': '',
    'Jy_FreqCentroid': '',
    'Jy_FreqVariance': '',
    'Jy_SpectralEntropy': '',
    // ── VV — Vertical Velocity (km/h) ─────────────────────────────
    'VV_Max': 'km/h',
    'VV_Min': 'km/h',
    'VV_Mean': 'km/h',
    'VV_Std': 'km/h',
    'VV_PeakToPeak': 'km/h',
    'VV_ARV': 'km/h',
    'VV_RMS': 'km/h',
    'VV_ShapeFactor': '',
    'VV_CrestFactor': '',
    'VV_ImpulseFactor': '',
    'VV_MarginFactor': '',
    'VV_AvgAmplitude': '',
    'VV_FreqCentroid': '',
    'VV_FreqVariance': '',
    'VV_SpectralEntropy': '',
    // ── R — Radius of Turn (m) ────────────────────────────────────
    'R_Max': 'm',
    'R_Min': 'm',
    'R_Mean': 'm',
    'R_Std': 'm',
    'R_PeakToPeak': 'm',
    'R_ARV': 'm',
    'R_RMS': 'm',
    'R_ShapeFactor': '',
    'R_CrestFactor': '',
    'R_ImpulseFactor': '',
    'R_MarginFactor': '',
    'R_AvgAmplitude': '',
    'R_FreqCentroid': '',
    'R_FreqVariance': '',
    'R_SpectralEntropy': '',
  };

  /// Look up the display unit for a feature key. Returns '' if unknown.
  static String getFeatureUnit(String featureKey) =>
      featureUnits[featureKey] ?? '';
}
