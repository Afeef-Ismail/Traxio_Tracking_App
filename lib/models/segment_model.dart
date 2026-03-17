/// Represents a 100-meter terrain-based segment with its computed scores.
class Segment {
  final int? id;
  final String tripId;
  final String mode;
  final int segmentIndex;
  final int startTime;  // ms since epoch
  final int endTime;    // ms since epoch
  final String terrain; // 'Plain', 'Uphill', 'Downhill'
  final double distance;// actual GPS distance (≈100m)
  final double startLat;
  final double startLon;
  final double endLat;
  final double endLon;
  final double startAltitude;
  final double endAltitude;
  final bool isValid;
  final String nearestLandmark;

  Segment({
    this.id,
    required this.tripId,
    this.mode = 'benchmark',
    required this.segmentIndex,
    required this.startTime,
    required this.endTime,
    required this.terrain,
    required this.distance,
    required this.startLat,
    required this.startLon,
    required this.endLat,
    required this.endLon,
    required this.startAltitude,
    required this.endAltitude,
    this.isValid = true,
    this.nearestLandmark = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'trip_id': tripId,
      'mode': mode,
      'segment_index': segmentIndex,
      'start_time': startTime,
      'end_time': endTime,
      'terrain': terrain,
      'distance': distance,
      'start_lat': startLat,
      'start_lon': startLon,
      'end_lat': endLat,
      'end_lon': endLon,
      'start_altitude': startAltitude,
      'end_altitude': endAltitude,
      'is_valid': isValid ? 1 : 0,
      'nearest_landmark': nearestLandmark,
    };
  }

  factory Segment.fromMap(Map<String, dynamic> map) {
    return Segment(
      id: map['id'] as int?,
      tripId: map['trip_id'] as String,
      mode: (map['mode'] as String?) ?? 'benchmark',
      segmentIndex: map['segment_index'] as int,
      startTime: map['start_time'] as int,
      endTime: map['end_time'] as int,
      terrain: map['terrain'] as String,
      distance: (map['distance'] as num).toDouble(),
      startLat: (map['start_lat'] as num).toDouble(),
      startLon: (map['start_lon'] as num).toDouble(),
      endLat: (map['end_lat'] as num).toDouble(),
      endLon: (map['end_lon'] as num).toDouble(),
      startAltitude: (map['start_altitude'] as num).toDouble(),
      endAltitude: (map['end_altitude'] as num).toDouble(),
      isValid: (map['is_valid'] as int) == 1,
      nearestLandmark: (map['nearest_landmark'] as String?) ?? '',
    );
  }
}
