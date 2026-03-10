import 'dart:math';

/// Static NH-766 route landmarks and GPS-based nearest-landmark lookup.
class LandmarkUtils {
  LandmarkUtils._();

  /// NH-766 route landmarks with GPS coordinates.
  static const List<_Landmark> _landmarks = [
    _Landmark('Kozhikode Bus Stand', 11.2588, 75.7804),
    _Landmark('Kallayi Bridge', 11.2750, 75.7900),
    _Landmark('Feroke', 11.3050, 75.8200),
    _Landmark('Ramanattukara', 11.3200, 75.8350),
    _Landmark('Thamarassery', 11.3678, 75.8595),
    _Landmark('Thamarassery Churam Start', 11.4200, 75.9100),
    _Landmark('Hairpin Bend 1', 11.4500, 75.9400),
    _Landmark('Hairpin Bend 2', 11.4700, 75.9600),
    _Landmark('Hairpin Bend 3', 11.4900, 75.9800),
    _Landmark('Hairpin Bend 4', 11.5000, 75.9950),
    _Landmark('Hairpin Bend 5', 11.5050, 76.0050),
    _Landmark('Lakkidi Viewpoint', 11.5133, 76.0195),
    _Landmark('Vythiri', 11.5425, 76.0425),
    _Landmark('Meppadi', 11.5600, 76.0600),
    _Landmark('Kalpetta', 11.6087, 76.0816),
    _Landmark('Ambalavayal', 11.6300, 76.1500),
    _Landmark('Sulthan Bathery', 11.6634, 76.2673),
  ];

  /// Returns the nearest landmark name if within 2 km, otherwise 'NH-766'.
  static String getNearestLandmark(double lat, double lon) {
    String nearest = 'NH-766';
    double minDist = double.infinity;

    for (final lm in _landmarks) {
      final dist = _haversine(lat, lon, lm.lat, lm.lon);
      if (dist < minDist) {
        minDist = dist;
        nearest = lm.name;
      }
    }

    return minDist <= 2.0 ? nearest : 'NH-766';
  }

  /// Haversine distance in kilometres.
  static double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0; // Earth radius in km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _deg2rad(double deg) => deg * (pi / 180);
}

class _Landmark {
  final String name;
  final double lat;
  final double lon;

  const _Landmark(this.name, this.lat, this.lon);
}
