import 'dart:async';
import '../models/raw_model.dart';
import '../config/constants.dart';
import '../utils/haversine.dart';

/// Buffer holding raw samples accumulating toward a 100m segment.
class SegmentBuffer {
  final String tripId;
  final int segmentIndex;
  final List<RawSample> samples = [];
  double cumulativeDistance = 0.0;

  SegmentBuffer({required this.tripId, required this.segmentIndex});

  bool get isEmpty => samples.isEmpty;

  RawSample get first => samples.first;
  RawSample get last => samples.last;

  void addSample(RawSample sample) {
    samples.add(sample);
  }
}

/// Service that segments the incoming raw sample stream into
/// 100-meter GPS-distance-based segments.
///
/// Tracks cumulative Haversine distance. When distance ≥ 100m:
///   1. Closes the current segment
///   2. Emits a completed [SegmentData]
///   3. Resets the buffer
///
/// Final segments < 100m are discarded per spec.
class SegmentationService {
  final StreamController<SegmentData> _segmentController =
      StreamController<SegmentData>.broadcast();

  /// Stream of completed 100m segments ready for processing.
  Stream<SegmentData> get segmentStream => _segmentController.stream;

  SegmentBuffer? _currentBuffer;
  int _segmentIndex = 0;
  double _cumulativeDistance = 0.0;
  double _segmentDistanceMeters = AppConstants.segmentDistanceMeters;
  RawSample? _prevSample;

  /// Reset for a new trip.
  void startNewTrip(String tripId, {double? segmentDistanceM}) {
    _segmentIndex = 0;
    _cumulativeDistance = 0.0;
    _segmentDistanceMeters = segmentDistanceM ?? AppConstants.segmentDistanceMeters;
    _prevSample = null;
    _currentBuffer = SegmentBuffer(
      tripId: tripId,
      segmentIndex: _segmentIndex,
    );
  }

  /// Feed a new raw sample into the segmentation engine.
  void addSample(RawSample sample) {
    if (_currentBuffer == null) return;

    // Calculate distance from previous sample
    if (_prevSample != null) {
      final double dist = haversineDistance(
        _prevSample!.lat,
        _prevSample!.lon,
        sample.lat,
        sample.lon,
      );
      _cumulativeDistance += dist;
    }

    _currentBuffer!.addSample(sample);
    _prevSample = sample;

    if (_cumulativeDistance >= _segmentDistanceMeters) {
      _closeCurrentSegment();
    }
  }

  /// Close current segment and start a new one.
  void _closeCurrentSegment() {
    final buffer = _currentBuffer!;

    if (buffer.samples.length < AppConstants.minSegmentSamples) {
      // Too few samples — skip this segment
      _resetBuffer(buffer.tripId);
      return;
    }

    // Emit the completed segment data
    final segData = SegmentData(
      tripId: buffer.tripId,
      segmentIndex: buffer.segmentIndex,
      samples: List.unmodifiable(buffer.samples),
      distance: _cumulativeDistance,
    );

    _segmentController.add(segData);

    // Reset for next segment
    _resetBuffer(buffer.tripId);
  }

  void _resetBuffer(String tripId) {
    _segmentIndex++;
    _cumulativeDistance = 0.0;
    _currentBuffer = SegmentBuffer(
      tripId: tripId,
      segmentIndex: _segmentIndex,
    );
  }

  /// Call when trip ends. Discards any partial segment < 100m.
  void endTrip() {
    // Per spec: final segment < 100m is discarded
    _currentBuffer = null;
    _prevSample = null;
  }

  int get currentSegmentIndex => _segmentIndex;
  double get currentDistance => _cumulativeDistance;

  void dispose() {
    _segmentController.close();
  }
}

/// Data container for a completed segment, passed to the processing pipeline.
class SegmentData {
  final String tripId;
  final int segmentIndex;
  final List<RawSample> samples;
  final double distance;

  SegmentData({
    required this.tripId,
    required this.segmentIndex,
    required this.samples,
    required this.distance,
  });

  int get startTime => samples.first.timestamp;
  int get endTime => samples.last.timestamp;
  double get startLat => samples.first.lat;
  double get startLon => samples.first.lon;
  double get endLat => samples.last.lat;
  double get endLon => samples.last.lon;
  double get startAltitude => samples.first.altitude;
  double get endAltitude => samples.last.altitude;
}
