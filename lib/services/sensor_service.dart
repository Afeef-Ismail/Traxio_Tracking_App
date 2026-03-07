import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../models/raw_model.dart';
import '../config/constants.dart';
import '../utils/haversine.dart';

/// Manages real-time sensor data capture at 10 Hz.
///
/// Fuses accelerometer (ax, ay), gyroscope (yaw rate), and GPS
/// (lat, lon, speed, altitude) into a unified [RawSample] stream.
class SensorService {
  // ─── Stream controllers ────────────────────────────────────────────
  final StreamController<RawSample> _sampleController =
      StreamController<RawSample>.broadcast();

  /// Broadcast stream of fused sensor samples at ~10 Hz.
  Stream<RawSample> get sampleStream => _sampleController.stream;

  // ─── Subscriptions ─────────────────────────────────────────────────
  StreamSubscription? _accelSubscription;
  StreamSubscription? _gyroSubscription;
  StreamSubscription? _gpsSubscription;
  Timer? _fusionTimer;

  // ─── Latest sensor values ──────────────────────────────────────────
  double _ax = 0.0;
  double _ay = 0.0;
  double _yawRate = 0.0;
  double _lat = 0.0;
  double _lon = 0.0;
  double _speed = 0.0;
  double _altitude = 0.0;
  bool _gpsReady = false;

  // ─── Calibration offsets ───────────────────────────────────────────
  double _axOffset = 0.0;
  double _ayOffset = 0.0;
  double _yawOffset = 0.0;
  bool _isCalibrated = false;
  final List<double> _calAx = [];
  final List<double> _calAy = [];
  final List<double> _calYaw = [];

  // ─── Edge case tracking ────────────────────────────────────────────
  double _prevLat = 0.0;
  double _prevLon = 0.0;
  bool _hasPrevGps = false;

  // ─── State ─────────────────────────────────────────────────────────
  bool _isCapturing = false;
  String _tripId = '';

  bool get isCapturing => _isCapturing;
  bool get isCalibrated => _isCalibrated;

  /// Start sensor capture.
  ///
  /// 1. Requests permissions
  /// 2. Starts accelerometer, gyroscope, GPS streams
  /// 3. Runs a 10 Hz fusion timer that emits [RawSample]s
  Future<bool> startCapture(String tripId) async {
    if (_isCapturing) return true;

    // Check & request location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    // Check location service
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    _tripId = tripId;
    _isCapturing = true;
    _isCalibrated = false;
    _hasPrevGps = false;
    _calAx.clear();
    _calAy.clear();
    _calYaw.clear();

    // ─── Start accelerometer ─────────────────────────────────────
    _accelSubscription = accelerometerEventStream(
      samplingPeriod: Duration(
          milliseconds: AppConstants.sensorIntervalMs),
    ).listen((event) {
      _ax = event.x;
      _ay = event.y;
    });

    // ─── Start gyroscope ─────────────────────────────────────────
    _gyroSubscription = gyroscopeEventStream(
      samplingPeriod: Duration(
          milliseconds: AppConstants.sensorIntervalMs),
    ).listen((event) {
      _yawRate = event.z; // Z-axis = yaw rate
    });

    // ─── Start GPS ───────────────────────────────────────────────
    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: Duration(
            milliseconds: AppConstants.sensorIntervalMs),
        forceLocationManager: false,
      ),
    ).listen((Position pos) {
      _lat = pos.latitude;
      _lon = pos.longitude;
      _speed = pos.speed; // m/s
      _altitude = pos.altitude;
      _gpsReady = true;
    });

    // ─── 10 Hz fusion timer ──────────────────────────────────────
    _fusionTimer = Timer.periodic(
      Duration(milliseconds: AppConstants.sensorIntervalMs),
      (_) => _emitFusedSample(),
    );

    return true;
  }

  /// Stop all sensor capture.
  void stopCapture() {
    _isCapturing = false;
    _fusionTimer?.cancel();
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _gpsSubscription?.cancel();
    _fusionTimer = null;
    _accelSubscription = null;
    _gyroSubscription = null;
    _gpsSubscription = null;
  }

  /// Called every 100ms to emit a fused sample.
  void _emitFusedSample() {
    if (!_gpsReady) return;

    // ─── Calibration phase ───────────────────────────────────────
    if (!_isCalibrated) {
      _calAx.add(_ax);
      _calAy.add(_ay);
      _calYaw.add(_yawRate);

      if (_calAx.length >= AppConstants.calibrationSamples) {
        _axOffset = _calAx.reduce((a, b) => a + b) / _calAx.length;
        _ayOffset = _calAy.reduce((a, b) => a + b) / _calAy.length;
        _yawOffset = _calYaw.reduce((a, b) => a + b) / _calYaw.length;
        _isCalibrated = true;
      }
      return; // Don't emit during calibration
    }

    // ─── Edge case: GPS jump detection ───────────────────────────
    if (_hasPrevGps) {
      final double jump = haversineDistance(
          _prevLat, _prevLon, _lat, _lon);
      if (jump > AppConstants.maxGpsJumpMeters) {
        // Discard this sample — GPS jump too large
        return;
      }
    }
    _prevLat = _lat;
    _prevLon = _lon;
    _hasPrevGps = true;

    // ─── Build sample with calibration offset applied ────────────
    final sample = RawSample(
      tripId: _tripId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      lat: _lat,
      lon: _lon,
      speed: _speed.abs(), // speed should be non-negative
      ax: _ax - _axOffset,
      ay: _ay - _ayOffset,
      yawRate: _yawRate - _yawOffset,
      altitude: _altitude,
    );

    _sampleController.add(sample);
  }

  /// Dispose resources.
  void dispose() {
    stopCapture();
    _sampleController.close();
  }
}
