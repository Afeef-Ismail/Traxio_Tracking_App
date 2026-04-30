/// Segment-level deviation score against benchmark clusters.
class SegmentScore {
  final int? id;
  final int segmentId;
  final double cluster0Deviation;
  final double cluster1Deviation;
  final int matchedCluster;
  final String matchedClusterName;

  SegmentScore({
    this.id,
    required this.segmentId,
    required this.cluster0Deviation,
    required this.cluster1Deviation,
    required this.matchedCluster,
    this.matchedClusterName = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'segment_id': segmentId,
      'cluster0_deviation': cluster0Deviation,
      'cluster1_deviation': cluster1Deviation,
      'matched_cluster': matchedCluster,
      'matched_cluster_name': matchedClusterName,
    };
  }

  factory SegmentScore.fromMap(Map<String, dynamic> map) {
    return SegmentScore(
      id: map['id'] as int?,
      segmentId: map['segment_id'] as int,
      cluster0Deviation: (map['cluster0_deviation'] as num).toDouble(),
      cluster1Deviation: (map['cluster1_deviation'] as num).toDouble(),
      matchedCluster: map['matched_cluster'] as int,
      matchedClusterName: (map['matched_cluster_name'] as String?) ?? '',
    );
  }
}

/// Trip-level aggregated results.
class TripSummary {
  final String tripId;
  final DateTime startTime;
  final DateTime endTime;
  final int totalSegments;
  final int validSegments;
  final int cluster0Matches;
  final int cluster1Matches;
  final double cluster0Percentage;
  final double cluster1Percentage;
  final double avgDeviationPlain;
  final double avgDeviationUphill;
  final double avgDeviationDownhill;
  final double overallAvgDeviation;
  final int plainSegments;
  final int uphillSegments;
  final int downhillSegments;
  final int userId;
  final String coachingReport;
  final double score;
  final String vehicleType;

  /// Populated from JOIN when reading; not stored in trip_summaries table.
  final String driverName;
  final String busNumber;

  TripSummary({
    required this.tripId,
    required this.startTime,
    required this.endTime,
    required this.totalSegments,
    required this.validSegments,
    required this.cluster0Matches,
    required this.cluster1Matches,
    required this.cluster0Percentage,
    required this.cluster1Percentage,
    required this.avgDeviationPlain,
    required this.avgDeviationUphill,
    required this.avgDeviationDownhill,
    required this.overallAvgDeviation,
    required this.plainSegments,
    required this.uphillSegments,
    required this.downhillSegments,
    this.userId = 0,
    this.coachingReport = '',
    this.score = -1,
    this.vehicleType = '',
    this.driverName = '',
    this.busNumber = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'trip_id': tripId,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime.millisecondsSinceEpoch,
      'total_segments': totalSegments,
      'valid_segments': validSegments,
      'cluster0_matches': cluster0Matches,
      'cluster1_matches': cluster1Matches,
      'cluster0_percentage': cluster0Percentage,
      'cluster1_percentage': cluster1Percentage,
      'avg_deviation_plain': avgDeviationPlain,
      'avg_deviation_uphill': avgDeviationUphill,
      'avg_deviation_downhill': avgDeviationDownhill,
      'overall_avg_deviation': overallAvgDeviation,
      'plain_segments': plainSegments,
      'uphill_segments': uphillSegments,
      'downhill_segments': downhillSegments,
      'user_id': userId,
      'coaching_report': coachingReport,
      'score': score,
      'vehicle_type': vehicleType,
    };
  }

  factory TripSummary.fromMap(Map<String, dynamic> map) {
    return TripSummary(
      tripId: map['trip_id'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int),
      totalSegments: map['total_segments'] as int,
      validSegments: map['valid_segments'] as int,
      cluster0Matches: map['cluster0_matches'] as int,
      cluster1Matches: map['cluster1_matches'] as int,
      cluster0Percentage: (map['cluster0_percentage'] as num).toDouble(),
      cluster1Percentage: (map['cluster1_percentage'] as num).toDouble(),
      avgDeviationPlain: (map['avg_deviation_plain'] as num).toDouble(),
      avgDeviationUphill: (map['avg_deviation_uphill'] as num).toDouble(),
      avgDeviationDownhill: (map['avg_deviation_downhill'] as num).toDouble(),
      overallAvgDeviation: (map['overall_avg_deviation'] as num).toDouble(),
      plainSegments: map['plain_segments'] as int,
      uphillSegments: map['uphill_segments'] as int,
      downhillSegments: map['downhill_segments'] as int,
      userId: (map['user_id'] as int?) ?? 0,
      coachingReport: (map['coaching_report'] as String?) ?? '',
      score: (map['score'] as num?)?.toDouble() ?? -1,
      vehicleType: (map['vehicle_type'] as String?) ?? '',
      driverName: (map['driver_name'] as String?) ?? '',
      busNumber: (map['bus_number'] as String?) ?? '',
    );
  }
}

/// Data-collection trip metadata (non-benchmark mode, no scoring).
class DataCollectionTrip {
  final int? id;
  final String tripId;
  final int driverId;
  final String mode;
  final double segmentDistanceM;
  final DateTime startTime;
  final DateTime? endTime;
  final int totalSegments;
  final String notes;
  final String createdAt;
  final String driverUsername;
  final String busNumber;
  final String routeDescription;
  final String vehicleType;

  DataCollectionTrip({
    this.id,
    required this.tripId,
    required this.driverId,
    this.mode = 'collection',
    required this.segmentDistanceM,
    required this.startTime,
    this.endTime,
    this.totalSegments = 0,
    this.notes = '',
    this.createdAt = '',
    this.driverUsername = '',
    this.busNumber = '',
    this.routeDescription = '',
    this.vehicleType = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'trip_id': tripId,
      'driver_id': driverId,
      'mode': mode,
      'vehicle_type': vehicleType,
      'segment_distance_m': segmentDistanceM,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime?.millisecondsSinceEpoch,
      'total_segments': totalSegments,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory DataCollectionTrip.fromMap(Map<String, dynamic> map) {
    final startMs = map['start_time'] as int? ?? 0;
    final endMs = map['end_time'] as int?;
    final startLandmark = (map['start_landmark'] as String?) ?? '';
    final endLandmark = (map['end_landmark'] as String?) ?? '';
    final routeDescription = startLandmark.isNotEmpty || endLandmark.isNotEmpty
        ? '${startLandmark.isEmpty ? 'Unknown' : startLandmark} → ${endLandmark.isEmpty ? 'Unknown' : endLandmark}'
        : '';

    return DataCollectionTrip(
      id: map['id'] as int?,
      tripId: map['trip_id'] as String,
      driverId: map['driver_id'] as int? ?? 0,
      mode: (map['mode'] as String?) ?? 'collection',
      vehicleType: (map['vehicle_type'] as String?) ?? '',
      segmentDistanceM: (map['segment_distance_m'] as num?)?.toDouble() ?? 100.0,
      startTime: DateTime.fromMillisecondsSinceEpoch(startMs),
      endTime: endMs != null
          ? DateTime.fromMillisecondsSinceEpoch(endMs)
          : null,
      totalSegments: map['total_segments'] as int? ?? 0,
      notes: (map['notes'] as String?) ?? '',
      createdAt: (map['created_at'] as String?) ?? '',
      driverUsername: (map['username'] as String?) ?? '',
      busNumber: (map['bus_number'] as String?) ?? '',
      routeDescription: routeDescription,
    );
  }
}
