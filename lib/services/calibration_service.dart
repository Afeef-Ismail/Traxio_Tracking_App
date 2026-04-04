import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores and applies sensor calibration offsets for mount-angle compensation.
///
/// Calibration captures the static gravity projection at the current phone
/// angle. Subtracting these offsets from raw sensor readings isolates only
/// the motion-induced forces, regardless of mounting angle.
class CalibrationService {
  static final CalibrationService _instance = CalibrationService._internal();
  factory CalibrationService() => _instance;
  CalibrationService._internal();

  static const _keyAxOffset = 'cal_ax_offset';
  static const _keyAyOffset = 'cal_ay_offset';
  static const _keyAzOffset = 'cal_az_offset';
  static const _keyYawOffset = 'cal_yaw_offset';
  static const _keyIsCalibrated = 'cal_is_calibrated';
  static const _keyCalDate = 'cal_date';

  double _axOffset = 0.0;
  double _ayOffset = 0.0;
  double _azOffset = 0.0;
  double _yawOffset = 0.0;
  bool _isCalibrated = false;
  String _calDate = '';

  bool get isCalibrated => _isCalibrated;
  double get axOffset => _axOffset;
  double get ayOffset => _ayOffset;
  double get azOffset => _azOffset;
  double get yawOffset => _yawOffset;
  String get calDate => _calDate;

  /// Load stored calibration from SharedPreferences.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isCalibrated = prefs.getBool(_keyIsCalibrated) ?? false;
    _axOffset = prefs.getDouble(_keyAxOffset) ?? 0.0;
    _ayOffset = prefs.getDouble(_keyAyOffset) ?? 0.0;
    _azOffset = prefs.getDouble(_keyAzOffset) ?? 0.0;
    _yawOffset = prefs.getDouble(_keyYawOffset) ?? 0.0;
    _calDate = prefs.getString(_keyCalDate) ?? '';
  }

  /// Save calibration offsets to SharedPreferences.
  Future<void> saveOffsets({
    required double axOffset,
    required double ayOffset,
    required double azOffset,
    required double yawOffset,
  }) async {
    _axOffset = axOffset;
    _ayOffset = ayOffset;
    _azOffset = azOffset;
    _yawOffset = yawOffset;
    _isCalibrated = true;
    _calDate = DateTime.now().toIso8601String();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyAxOffset, axOffset);
    await prefs.setDouble(_keyAyOffset, ayOffset);
    await prefs.setDouble(_keyAzOffset, azOffset);
    await prefs.setDouble(_keyYawOffset, yawOffset);
    await prefs.setBool(_keyIsCalibrated, true);
    await prefs.setString(_keyCalDate, _calDate);
  }

  /// Clear stored calibration.
  Future<void> clearCalibration() async {
    _axOffset = 0.0;
    _ayOffset = 0.0;
    _azOffset = 0.0;
    _yawOffset = 0.0;
    _isCalibrated = false;
    _calDate = '';

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAxOffset);
    await prefs.remove(_keyAyOffset);
    await prefs.remove(_keyAzOffset);
    await prefs.remove(_keyYawOffset);
    await prefs.remove(_keyIsCalibrated);
    await prefs.remove(_keyCalDate);
  }

  /// Returns true if the phone has tilted more than ~15° since last calibration.
  ///
  /// Uses current raw accelerometer readings compared to stored gravity offsets.
  bool hasTiltChanged(double currentAx, double currentAy) {
    if (!_isCalibrated) return false;
    // sin(15°) ≈ 0.259 g threshold
    const threshold = 0.259 * 9.80665;
    final deltaAx = (currentAx - _axOffset).abs();
    final deltaAy = (currentAy - _ayOffset).abs();
    return deltaAx > threshold || deltaAy > threshold;
  }

  /// Tilt angle from stored ax offset (roll/sideways tilt) in degrees.
  double get rollDegrees {
    const g = 9.80665;
    final ratio = (_axOffset / g).clamp(-1.0, 1.0);
    return asin(ratio) * (180 / pi);
  }

  /// Tilt angle from stored ay offset (pitch/forward tilt) in degrees.
  double get pitchDegrees {
    const g = 9.80665;
    final ratio = (_ayOffset / g).clamp(-1.0, 1.0);
    return asin(ratio) * (180 / pi);
  }

  // ─── Calibration process state ───────────────────────────────────

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;
  StreamController<CalibrationProgress>? _progressController;

  final List<double> _calAx = [];
  final List<double> _calAy = [];
  final List<double> _calAz = [];
  final List<double> _calYaw = [];

  // Sliding window for stability check (last 2 seconds at 10 Hz = 20 samples)
  final List<double> _stabilityAxWindow = [];
  final List<double> _stabilityAyWindow = [];
  static const int _stabilityWindowSize = 20;
  static const int _stabilityStableCount = 50; // 5 seconds at 10 Hz
  static const int _recordingSamples = 50; // 5 seconds at 10 Hz
  static const double _stabilityThreshold = 0.05 * 9.80665; // 0.05 g in m/s²

  int _stableCount = 0;
  bool _isRecording = false;
  bool _isDone = false;

  /// Start the guided calibration process. Returns a stream of [CalibrationProgress].
  Stream<CalibrationProgress> startCalibration() {
    _calAx.clear();
    _calAy.clear();
    _calAz.clear();
    _calYaw.clear();
    _stabilityAxWindow.clear();
    _stabilityAyWindow.clear();
    _stableCount = 0;
    _isRecording = false;
    _isDone = false;

    _progressController?.close();
    _progressController = StreamController<CalibrationProgress>.broadcast();

    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(_onAccelSample);

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((event) {
      if (_isRecording) {
        _calYaw.add(event.z);
      }
    });

    return _progressController!.stream;
  }

  void _onAccelSample(AccelerometerEvent event) {
    if (_isDone) return;

    if (_isRecording) {
      // Phase 2: Recording samples
      _calAx.add(event.x);
      _calAy.add(event.y);
      _calAz.add(event.z);

      final progress = _calAx.length / _recordingSamples;
      _progressController?.add(CalibrationProgress(
        phase: CalibrationPhase.recording,
        stabilityProgress: 1.0,
        recordingProgress: progress.clamp(0.0, 1.0),
        countdown: _recordingSamples - _calAx.length,
      ));

      if (_calAx.length >= _recordingSamples) {
        _finishCalibration();
      }
      return;
    }

    // Phase 1: Stability check
    _stabilityAxWindow.add(event.x);
    _stabilityAyWindow.add(event.y);

    if (_stabilityAxWindow.length > _stabilityWindowSize) {
      _stabilityAxWindow.removeAt(0);
      _stabilityAyWindow.removeAt(0);
    }

    final isStill = _computeStd(_stabilityAxWindow) < _stabilityThreshold &&
        _computeStd(_stabilityAyWindow) < _stabilityThreshold;

    if (isStill) {
      _stableCount++;
    } else {
      _stableCount = 0;
    }

    final stabilityProgress =
        (_stableCount / _stabilityStableCount).clamp(0.0, 1.0);

    _progressController?.add(CalibrationProgress(
      phase: CalibrationPhase.waitingForStillness,
      stabilityProgress: stabilityProgress,
      recordingProgress: 0.0,
      countdown: _recordingSamples,
    ));

    if (_stableCount >= _stabilityStableCount) {
      _isRecording = true;
      _stableCount = 0;
    }
  }

  double _computeStd(List<double> values) {
    if (values.length < 2) return double.infinity;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    return sqrt(variance);
  }

  Future<void> _finishCalibration() async {
    _isDone = true;
    _accelSub?.cancel();
    _gyroSub?.cancel();

    final axMean = _calAx.reduce((a, b) => a + b) / _calAx.length;
    final ayMean = _calAy.reduce((a, b) => a + b) / _calAy.length;
    final azMean = _calAz.reduce((a, b) => a + b) / _calAz.length;
    final yawMean = _calYaw.isNotEmpty
        ? _calYaw.reduce((a, b) => a + b) / _calYaw.length
        : 0.0;

    await saveOffsets(
      axOffset: axMean,
      ayOffset: ayMean,
      azOffset: azMean,
      yawOffset: yawMean,
    );

    _progressController?.add(CalibrationProgress(
      phase: CalibrationPhase.complete,
      stabilityProgress: 1.0,
      recordingProgress: 1.0,
      countdown: 0,
    ));

    _progressController?.close();
  }

  /// Stop calibration without saving.
  void stopCalibration() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _progressController?.close();
    _progressController = null;
  }
}

enum CalibrationPhase {
  waitingForStillness,
  recording,
  complete,
}

class CalibrationProgress {
  final CalibrationPhase phase;
  final double stabilityProgress; // 0.0 to 1.0
  final double recordingProgress; // 0.0 to 1.0
  final int countdown;

  CalibrationProgress({
    required this.phase,
    required this.stabilityProgress,
    required this.recordingProgress,
    required this.countdown,
  });
}
