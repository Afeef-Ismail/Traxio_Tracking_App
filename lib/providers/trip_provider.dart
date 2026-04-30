import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/constants.dart';
import '../services/sensor_service.dart';
import '../services/demo_sensor_service.dart';
import '../services/segmentation_service.dart';
import '../services/trip_processor.dart';
import '../analytics/trip_analytics.dart';
import '../models/raw_model.dart';
import '../models/trip_model.dart';
import '../database/db_helper.dart';
import '../ui/widgets/map_widget.dart';

/// Possible states of the trip recording lifecycle.
enum TripState {
  idle,
  calibrating,
  recording,
  processing,
  completed,
  error,
}

/// Per-segment detail data used by the SegmentDetailScreen.
class SegmentDetail {
  final int segmentIndex;
  final String terrain;
  final Map<String, double> features;
  final double cluster0Deviation;
  final double cluster1Deviation;
  final int matchedCluster;
  final String nearestLandmark;

  SegmentDetail({
    required this.segmentIndex,
    required this.terrain,
    required this.features,
    required this.cluster0Deviation,
    required this.cluster1Deviation,
    required this.matchedCluster,
    this.nearestLandmark = '',
  });
}

/// Central state manager for trip recording and processing.
/// Wires together sensor → segmentation → processing → analytics.
class TripProvider extends ChangeNotifier {
  // Real sensors (used when demoMode = false)
  SensorService? _sensorService;
  // Simulated sensors (used when demoMode = true)
  DemoSensorService? _demoSensorService;

  final SegmentationService _segmentationService = SegmentationService();
  final TripProcessor _tripProcessor = TripProcessor();
  final TripAnalytics _tripAnalytics = TripAnalytics();
  final DbHelper _db = DbHelper();

  TripProvider() {
    if (AppConstants.demoMode) {
      _demoSensorService = DemoSensorService();
    } else {
      _sensorService = SensorService();
    }
  }

  // ─── State ─────────────────────────────────────────────────────────
  TripState _state = TripState.idle;
  String _tripId = '';
  String _errorMessage = '';
  int _segmentsCompleted = 0;
  double _currentDistance = 0.0;
  double _currentSpeed = 0.0;
  String _currentTerrain = 'N/A';
  int _lastMatchedCluster = -1;
  double _lastDeviation = 0.0;
  TripSummary? _lastSummary;
  bool _isCollectionMode = false;
  double _collectionSegmentDistanceM = AppConstants.collectionSegmentDistanceM;

  // ─── Current driver ID for trip attribution ────────────────────────
  int _currentUserId = 0;

  // ─── Selected vehicle type for scoring ────────────────────────────
  String _selectedVehicleType = '';

  /// Set the current driver's user ID (call after login).
  void setCurrentUserId(int userId) {
    _currentUserId = userId;
  }

  // ─── Live GPS position ─────────────────────────────────────────────
  double? _currentLat;
  double? _currentLon;
  double _currentBearing = 0.0;
  bool _gpsSignalLost = false;
  DateTime? _lastSampleTimestamp;
  Timer? _gpsWatchdogTimer;
  double? _previousLat;
  double? _previousLon;

  // ─── GPS trail for map polyline ────────────────────────────────────
  final List<LatLng> _gpsTrail = [];

  // ─── Segment markers for map ───────────────────────────────────────
  final List<MapSegmentMarker> _segmentMarkers = [];

  // ─── Subscriptions ─────────────────────────────────────────────────
  StreamSubscription? _sampleSub;
  StreamSubscription? _segmentSub;

  // ─── Raw sample buffer for DB batch insert ─────────────────────────
  final List<RawSample> _rawBuffer = [];
  static const int _rawBatchSize = 50;

  // ─── UI throttle — only rebuild at ~2 Hz ───────────────────────────
  int _lastNotifyMs = 0;
  static const int _notifyIntervalMs = 500;

  // ─── Getters ───────────────────────────────────────────────────────
  TripState get state => _state;
  String get tripId => _tripId;
  String get errorMessage => _errorMessage;
  int get segmentsCompleted => _segmentsCompleted;
  double get currentDistance => _currentDistance;
  double get currentSpeed => _currentSpeed;
  String get currentTerrain => _currentTerrain;
  int get lastMatchedCluster => _lastMatchedCluster;
  double get lastDeviation => _lastDeviation;
  TripSummary? get lastSummary => _lastSummary;
  bool get isRecording => _state == TripState.recording;
  bool get isCollectionMode => _isCollectionMode;
  double get collectionSegmentDistanceM => _collectionSegmentDistanceM;
  String get selectedVehicleType => _selectedVehicleType;
  double? get currentLat => _currentLat;
  double? get currentLon => _currentLon;
  List<LatLng> get gpsTrail => List.unmodifiable(_gpsTrail);
  List<MapSegmentMarker> get segmentMarkers =>
      List.unmodifiable(_segmentMarkers);
  double get currentBearing => _currentBearing;
  bool get gpsSignalLost => _gpsSignalLost;

  /// Start a new trip recording.
  Future<void> startTrip({String vehicleType = ''}) async {
    try {
      _tripId = const Uuid().v4();
      _selectedVehicleType = vehicleType;
      _isCollectionMode = false;
      _collectionSegmentDistanceM = AppConstants.segmentDistanceMeters;
      _segmentsCompleted = 0;
      _currentDistance = 0.0;
      _currentSpeed = 0.0;
      _currentTerrain = 'N/A';
      _lastMatchedCluster = -1;
      _lastDeviation = 0.0;
      _lastSummary = null;
      _currentLat = null;
      _currentLon = null;
      _currentBearing = 0.0;
      _gpsSignalLost = false;
      _lastSampleTimestamp = null;
      _previousLat = null;
      _previousLon = null;
      _gpsTrail.clear();
      _segmentMarkers.clear();
      _rawBuffer.clear();

      _gpsWatchdogTimer?.cancel();

      // Seed with last known location so map has an immediate reference point.
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _currentLat = lastKnown.latitude;
          _currentLon = lastKnown.longitude;
          _previousLat = lastKnown.latitude;
          _previousLon = lastKnown.longitude;
        }
      } catch (_) {
        // Ignore location seed errors; live stream will provide updates.
      }

      // Load slope threshold from settings
      try {
        final prefs = await SharedPreferences.getInstance();
        _tripProcessor.slopeThreshold =
            prefs.getDouble('slope_threshold') ?? 0.02;
      } catch (_) {
        _tripProcessor.slopeThreshold = 0.02;
      }

      _state = TripState.calibrating;
      notifyListeners();

      bool success;
      if (AppConstants.demoMode) {
        // Demo mode — no real hardware, no permission checks
        success = await _demoSensorService!.startCapture(_tripId);
      } else {
        // Real mode — start hardware sensors (includes calibration)
        success = await _sensorService!.startCapture(_tripId);
      }

      if (!success) {
        await WakelockPlus.disable();
        _state = TripState.error;
        _errorMessage = 'Failed to start sensors. Check permissions.';
        notifyListeners();
        return;
      }

      await WakelockPlus.enable();

      // Initialize segmentation
      _tripProcessor.init(
        _tripId,
        mode: 'benchmark',
        segmentDistanceM: AppConstants.segmentDistanceMeters,
      );
      _segmentationService.startNewTrip(
        _tripId,
        segmentDistanceM: _tripProcessor.segmentDistanceM,
      );

      // Always load fresh cluster data — clear any stale cache from previous trip
      _tripProcessor.clearBenchmarkCache();
      await _tripProcessor.loadBenchmarks(vehicleType: vehicleType);

      // Listen to sensor samples (same stream interface for both)
      final sampleStream = AppConstants.demoMode
          ? _demoSensorService!.sampleStream
          : _sensorService!.sampleStream;
      _sampleSub = sampleStream.listen(_onSample);

      // Listen to completed segments
      _segmentSub =
          _segmentationService.segmentStream.listen(_onSegmentComplete);

      if (AppConstants.demoMode) {
        // Demo: skip calibration wait, go straight to recording
        _state = TripState.recording;
        _startGpsWatchdog();
        notifyListeners();
      } else {
        // Real: wait for calibration
        await Future.delayed(const Duration(seconds: 3));
        _state = TripState.recording;
        _startGpsWatchdog();
        notifyListeners();
      }
    } catch (e) {
      await WakelockPlus.disable();
      _state = TripState.error;
      _errorMessage = 'Error starting trip: $e';
      notifyListeners();
    }
  }

  /// Start a new data collection trip recording (no scoring/AI coaching).
  Future<void> startCollectionTrip(double segmentDistanceM, {String vehicleType = ''}) async {
    try {
      _tripId = const Uuid().v4();
      _isCollectionMode = true;
      _selectedVehicleType = vehicleType;
      _collectionSegmentDistanceM = segmentDistanceM;
      _segmentsCompleted = 0;
      _currentDistance = 0.0;
      _currentSpeed = 0.0;
      _currentTerrain = 'N/A';
      _lastMatchedCluster = -1;
      _lastDeviation = 0.0;
      _lastSummary = null;
      _currentLat = null;
      _currentLon = null;
      _currentBearing = 0.0;
      _gpsSignalLost = false;
      _lastSampleTimestamp = null;
      _previousLat = null;
      _previousLon = null;
      _gpsTrail.clear();
      _segmentMarkers.clear();
      _rawBuffer.clear();

      _gpsWatchdogTimer?.cancel();

      // Seed with last known location so map has an immediate reference point.
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _currentLat = lastKnown.latitude;
          _currentLon = lastKnown.longitude;
          _previousLat = lastKnown.latitude;
          _previousLon = lastKnown.longitude;
        }
      } catch (_) {
        // Ignore location seed errors; live stream will provide updates.
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        _tripProcessor.slopeThreshold =
            prefs.getDouble('slope_threshold') ?? 0.02;
      } catch (_) {
        _tripProcessor.slopeThreshold = 0.02;
      }

      await _db.insertDataCollectionTrip(
        _tripId,
        _currentUserId,
        segmentDistanceM,
        vehicleType: vehicleType,
      );

      _state = TripState.calibrating;
      notifyListeners();

      bool success;
      if (AppConstants.demoMode) {
        success = await _demoSensorService!.startCapture(_tripId);
      } else {
        success = await _sensorService!.startCapture(_tripId);
      }

      if (!success) {
        await WakelockPlus.disable();
        _state = TripState.error;
        _errorMessage = 'Failed to start sensors. Check permissions.';
        notifyListeners();
        return;
      }

      await WakelockPlus.enable();

      _tripProcessor.init(
        _tripId,
        mode: 'collection',
        segmentDistanceM: segmentDistanceM,
      );
      _segmentationService.startNewTrip(
        _tripId,
        segmentDistanceM: _tripProcessor.segmentDistanceM,
      );

      final sampleStream = AppConstants.demoMode
          ? _demoSensorService!.sampleStream
          : _sensorService!.sampleStream;
      _sampleSub = sampleStream.listen(_onSample);
      _segmentSub =
          _segmentationService.segmentStream.listen(_onSegmentComplete);

      if (AppConstants.demoMode) {
        _state = TripState.recording;
        _startGpsWatchdog();
        notifyListeners();
      } else {
        await Future.delayed(const Duration(seconds: 3));
        _state = TripState.recording;
        _startGpsWatchdog();
        notifyListeners();
      }
    } catch (e) {
      await WakelockPlus.disable();
      _state = TripState.error;
      _errorMessage = 'Error starting data collection: $e';
      notifyListeners();
    }
  }

  /// Stop the current trip and generate summary.
  Future<void> stopTrip() async {
    if (_state != TripState.recording) return;

    _state = TripState.processing;
    notifyListeners();

    try {
      // Stop sensor capture
      if (AppConstants.demoMode) {
        _demoSensorService!.stopCapture();
      } else {
        _sensorService!.stopCapture();
      }
      _sampleSub?.cancel();
      _segmentSub?.cancel();
      _gpsWatchdogTimer?.cancel();
      _gpsSignalLost = false;
      await WakelockPlus.disable();

      // Flush remaining raw samples
      if (_rawBuffer.isNotEmpty) {
        await _db.insertRawBatch(_rawBuffer);
        _rawBuffer.clear();
      }

      // End segmentation (discards partial segment < 100m)
      _segmentationService.endTrip();

      // Generate trip summary
      _lastSummary = await _tripAnalytics.generateSummary(
        _tripId,
        userId: _currentUserId,
        vehicleType: _selectedVehicleType,
      );

      // Clear benchmark cache
      _tripProcessor.clearBenchmarkCache();

      _state = TripState.completed;
      notifyListeners();
    } catch (e) {
      await WakelockPlus.disable();
      _state = TripState.error;
      _errorMessage = 'Error stopping trip: $e';
      notifyListeners();
    }
  }

  /// Stop the current data collection trip (no benchmark summary generation).
  Future<void> stopCollectionTrip() async {
    if (_state != TripState.recording || !_isCollectionMode) return;

    _state = TripState.processing;
    notifyListeners();

    try {
      if (AppConstants.demoMode) {
        _demoSensorService!.stopCapture();
      } else {
        _sensorService!.stopCapture();
      }
      _sampleSub?.cancel();
      _segmentSub?.cancel();
      _gpsWatchdogTimer?.cancel();
      _gpsSignalLost = false;
      await WakelockPlus.disable();

      if (_rawBuffer.isNotEmpty) {
        await _db.insertRawBatch(_rawBuffer);
        _rawBuffer.clear();
      }

      _segmentationService.endTrip();

      await _db.updateDataCollectionTripEnd(
        _tripId,
        DateTime.now().millisecondsSinceEpoch,
        _segmentsCompleted,
      );

      _tripProcessor.clearBenchmarkCache();
      _state = TripState.idle;
      _isCollectionMode = false;
      notifyListeners();
    } catch (e) {
      await WakelockPlus.disable();
      _state = TripState.error;
      _errorMessage = 'Error stopping data collection: $e';
      notifyListeners();
    }
  }

  /// Handle incoming raw sample.
  void _onSample(RawSample sample) {
    _lastSampleTimestamp = DateTime.now();
    if (_gpsSignalLost) {
      _gpsSignalLost = false;
      notifyListeners();
    }

    // Update live display values
    _currentSpeed = sample.speed;
    _currentDistance = _segmentationService.currentDistance;
    _currentLat = sample.lat;
    _currentLon = sample.lon;

    // Accumulate GPS trail (every sample for smooth polyline)
    if (sample.lat != 0.0 && sample.lon != 0.0) {
      if (_previousLat != null && _previousLon != null) {
        _currentBearing = _calculateBearing(
          _previousLat!,
          _previousLon!,
          sample.lat,
          sample.lon,
        );
      }
      _previousLat = sample.lat;
      _previousLon = sample.lon;
      _gpsTrail.add(LatLng(sample.lat, sample.lon));
    }

    // Buffer for batch DB insert
    _rawBuffer.add(sample);
    if (_rawBuffer.length >= _rawBatchSize) {
      _db.insertRawBatch(List.from(_rawBuffer));
      _rawBuffer.clear();
    }

    // Feed to segmentation
    _segmentationService.addSample(sample);

    // Throttle UI rebuilds to ~2 Hz
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastNotifyMs >= _notifyIntervalMs) {
      _lastNotifyMs = nowMs;
      notifyListeners();
    }
  }

  void _startGpsWatchdog() {
    _gpsWatchdogTimer?.cancel();
    _gpsWatchdogTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_state != TripState.recording) return;
      final last = _lastSampleTimestamp;
      if (last == null) return;
      final gap = DateTime.now().difference(last);
      final lost = gap > const Duration(seconds: 5);
      if (lost != _gpsSignalLost) {
        _gpsSignalLost = lost;
        notifyListeners();
      }
    });
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final lat1Rad = lat1 * (pi / 180.0);
    final lat2Rad = lat2 * (pi / 180.0);
    final lonDiffRad = (lon2 - lon1) * (pi / 180.0);

    final y = sin(lonDiffRad) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(lonDiffRad);

    final bearingDeg = atan2(y, x) * (180.0 / pi);
    return (bearingDeg + 360.0) % 360.0;
  }

  /// Handle completed segment.
  Future<void> _onSegmentComplete(SegmentData segData) async {
    try {
      final result = await _tripProcessor.processSegment(segData);
      _segmentsCompleted++;
      _currentTerrain = result.terrain;
      _lastMatchedCluster = result.matchedCluster;
      _lastDeviation = result.matchedDeviation;

      // Add a terrain-coded marker at the segment end point
      if (segData.endLat != 0.0 && segData.endLon != 0.0) {
        _segmentMarkers.add(MapSegmentMarker(
          position: LatLng(segData.endLat, segData.endLon),
          terrain: result.terrain,
        ));
      }

      notifyListeners();
    } catch (e) {
      print('Error processing segment: $e');
    }
  }

  /// Get vehicle types available across all active clusters.
  Future<List<String>> getActiveVehicleTypes() async {
    return await _db.getActiveVehicleTypes();
  }

  /// Reset to idle state.
  void reset() {
    _state = TripState.idle;
    _isCollectionMode = false;
    _selectedVehicleType = '';
    _tripId = '';
    _errorMessage = '';
    _segmentsCompleted = 0;
    _currentDistance = 0.0;
    _currentSpeed = 0.0;
    _currentLat = null;
    _currentLon = null;
    _currentBearing = 0.0;
    _gpsSignalLost = false;
    _gpsWatchdogTimer?.cancel();
    _lastSampleTimestamp = null;
    _previousLat = null;
    _previousLon = null;
    _gpsTrail.clear();
    _segmentMarkers.clear();
    _lastSummary = null;
    _lastMatchedCluster = -1;
    _lastDeviation = 0.0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  // TRIP HISTORY & SEGMENT DETAIL QUERIES
  // ═══════════════════════════════════════════════════════════════════

  /// Get all past trip summaries.
  Future<List<TripSummary>> getTripHistory() async {
    return await _db.getAllTripSummaries();
  }

  Future<List<DataCollectionTrip>> getDataCollectionTripsForUser(int userId) async {
    return await _db.getDataCollectionTripsForUser(userId);
  }

  Future<List<DataCollectionTrip>> getAllDataCollectionTrips() async {
    return await _db.getAllDataCollectionTrips();
  }

  /// Load a specific trip summary (for re-viewing from history).
  Future<TripSummary?> loadTripSummary(String tripId) async {
    return await _db.getTripSummary(tripId);
  }

  /// Get all segment details for a trip (for segment list / drill-down).
  /// Loads per-segment features from DB (120 per segment — use only when
  /// features are actually needed, e.g. SegmentDetailScreen).
  Future<List<SegmentDetail>> getSegmentDetailsForTrip(String tripId) async {
    final segments = await _db.getSegmentsForTrip(tripId);
    final scores = await _db.getScoresForTrip(tripId);

    // Build a map of segmentId → score
    final scoreMap = <int, SegmentScore>{};
    for (final s in scores) {
      scoreMap[s.segmentId] = s;
    }

    final List<SegmentDetail> details = [];
    for (final seg in segments) {
      if (!seg.isValid || seg.id == null) continue;

      final features = await _db.getFeaturesForSegment(seg.id!);
      final score = scoreMap[seg.id!];

      details.add(SegmentDetail(
        segmentIndex: seg.segmentIndex,
        terrain: seg.terrain,
        features: features,
        cluster0Deviation: score?.cluster0Deviation ?? 0.0,
        cluster1Deviation: score?.cluster1Deviation ?? 0.0,
        matchedCluster: score?.matchedCluster ?? -1,
        nearestLandmark: seg.nearestLandmark,
      ));
    }
    return details;
  }

  /// Lightweight version — loads segments + scores WITHOUT per-segment feature
  /// queries. Use this for coaching and analysis that only needs deviation data.
  /// Avoids the N×120 feature queries of [getSegmentDetailsForTrip].
  Future<List<SegmentDetail>> getSegmentDetailsLite(String tripId) async {
    final segments = await _db.getSegmentsForTrip(tripId);
    final scores = await _db.getScoresForTrip(tripId);

    final scoreMap = <int, SegmentScore>{};
    for (final s in scores) {
      scoreMap[s.segmentId] = s;
    }

    final List<SegmentDetail> details = [];
    for (final seg in segments) {
      if (!seg.isValid || seg.id == null) continue;
      final sc = scoreMap[seg.id!];
      details.add(SegmentDetail(
        segmentIndex: seg.segmentIndex,
        terrain: seg.terrain,
        features: const {},
        cluster0Deviation: sc?.cluster0Deviation ?? 0.0,
        cluster1Deviation: sc?.cluster1Deviation ?? 0.0,
        matchedCluster: sc?.matchedCluster ?? -1,
        nearestLandmark: seg.nearestLandmark,
      ));
    }
    return details;
  }

  /// Delete a trip and all its data.
  Future<void> deleteTrip(String tripId) async {
    await _db.deleteTrip(tripId);
    notifyListeners();
  }

  @override
  void dispose() {
    _gpsWatchdogTimer?.cancel();
    if (AppConstants.demoMode) {
      _demoSensorService?.dispose();
    } else {
      _sensorService?.dispose();
    }
    _segmentationService.dispose();
    _sampleSub?.cancel();
    _segmentSub?.cancel();
    super.dispose();
  }
}
