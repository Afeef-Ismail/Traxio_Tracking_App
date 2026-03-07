/// Raw sensor sample captured at 10 Hz.
/// Each instance represents one fused reading from GPS + IMU.
class RawSample {
  final int? id;
  final String tripId;
  final int timestamp; // milliseconds since epoch
  final double lat;
  final double lon;
  final double speed;   // m/s from GPS
  final double ax;      // lateral acceleration (accelerometer X)
  final double ay;      // longitudinal acceleration (accelerometer Y)
  final double yawRate; // gyroscope Z (rad/s)
  final double altitude;// meters from GPS

  RawSample({
    this.id,
    required this.tripId,
    required this.timestamp,
    required this.lat,
    required this.lon,
    required this.speed,
    required this.ax,
    required this.ay,
    required this.yawRate,
    required this.altitude,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'trip_id': tripId,
      'timestamp': timestamp,
      'lat': lat,
      'lon': lon,
      'speed': speed,
      'ax': ax,
      'ay': ay,
      'yaw_rate': yawRate,
      'altitude': altitude,
    };
  }

  factory RawSample.fromMap(Map<String, dynamic> map) {
    return RawSample(
      id: map['id'] as int?,
      tripId: map['trip_id'] as String,
      timestamp: map['timestamp'] as int,
      lat: (map['lat'] as num).toDouble(),
      lon: (map['lon'] as num).toDouble(),
      speed: (map['speed'] as num).toDouble(),
      ax: (map['ax'] as num).toDouble(),
      ay: (map['ay'] as num).toDouble(),
      yawRate: (map['yaw_rate'] as num).toDouble(),
      altitude: (map['altitude'] as num).toDouble(),
    );
  }

  @override
  String toString() =>
      'RawSample(t=$timestamp, lat=$lat, lon=$lon, v=$speed, ax=$ax, ay=$ay, yr=$yawRate, alt=$altitude)';
}
