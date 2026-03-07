import 'dart:async';
import 'dart:math';

import '../models/raw_model.dart';
import '../config/constants.dart';

/// Simulates a realistic Kozhikode → Sulthan Bathery KSRTC bus trip
/// for emulator/desktop testing.
///
/// Uses 90+ dense waypoints traced along the actual NH-766 road so the
/// marker follows the highway instead of cutting through terrain/sea.
///
/// Emits [RawSample] at 10 Hz via [sampleStream].
class DemoSensorService {
  /// Stream of simulated samples (same contract as SensorService).
  Stream<RawSample> get sampleStream => _controller.stream;

  final StreamController<RawSample> _controller =
      StreamController<RawSample>.broadcast();

  Timer? _timer;
  String? _tripId;
  final Random _rng = Random(42);

  // Simulation state
  int _waypointIndex = 0;
  double _segmentProgress = 0.0; // 0..1 between current and next waypoint
  double _currentSpeed = 0.0;    // m/s
  double _currentYaw = 0.0;      // bearing in radians

  bool _isRunning = false;

  /// Whether the service is currently producing samples.
  bool get isRunning => _isRunning;

  // ─── Dense waypoints following NH-766 road exactly ───────────────
  // Format: [lat, lon, altitude_m, terrain (0=plain,1=up,2=down), target_speed_kmh]
  static const List<List<double>> _waypoints = [
    // ── Kozhikode City (Plain) ──
    // Real: Kozhikode KSRTC Bus Stand 11.2588, 75.7804
    [11.2588, 75.7804, 10, 0, 35],   // Kozhikode Bus Stand
    [11.2605, 75.7840, 10, 0, 30],
    [11.2625, 75.7880, 12, 0, 35],
    [11.2650, 75.7925, 12, 0, 40],
    [11.2680, 75.7960, 14, 0, 45],
    [11.2715, 75.7990, 15, 0, 50],
    [11.2755, 75.8020, 16, 0, 50],

    // ── Ramanattukara to Balussery (Plain) ──
    // Real: Ramanattukara ~11.28, 75.81 → Balussery ~11.31, 75.83
    [11.2800, 75.8055, 18, 0, 55],
    [11.2845, 75.8090, 20, 0, 55],
    [11.2895, 75.8125, 22, 0, 55],
    [11.2945, 75.8158, 24, 0, 55],
    [11.3000, 75.8195, 26, 0, 55],
    [11.3050, 75.8230, 28, 0, 55],
    [11.3105, 75.8265, 30, 0, 55],

    // ── Balussery to Thamarassery (Plain) ──
    // Real: Thamarassery ~11.368, 75.860
    [11.3160, 75.8300, 32, 0, 55],
    [11.3215, 75.8338, 34, 0, 55],
    [11.3270, 75.8378, 36, 0, 55],
    [11.3325, 75.8418, 38, 0, 55],
    [11.3380, 75.8458, 40, 0, 55],
    [11.3435, 75.8498, 42, 0, 55],
    [11.3490, 75.8538, 45, 0, 50],
    [11.3545, 75.8570, 50, 0, 45],

    // ── Thamarassery town ──
    // Real: Thamarassery junction 11.3678, 75.8595
    [11.3600, 75.8580, 55, 0, 40],
    [11.3645, 75.8588, 58, 0, 35],
    [11.3678, 75.8595, 62, 0, 30],   // Thamarassery junction

    // ── Thamarassery Ghat - UPHILL ──
    // Real: Ghat starts ~11.38, 75.87 → Lakkidi top 11.513, 76.020
    // The ghat goes northeast with switchback hairpins
    [11.3720, 75.8630, 80, 1, 25],
    [11.3765, 75.8680, 120, 1, 20],
    [11.3810, 75.8740, 160, 1, 18],
    [11.3855, 75.8810, 200, 1, 20],
    [11.3905, 75.8880, 245, 1, 18],
    [11.3960, 75.8950, 290, 1, 15],
    [11.4015, 75.9020, 335, 1, 18],
    [11.4070, 75.9095, 380, 1, 15],
    [11.4130, 75.9170, 420, 1, 18],
    [11.4190, 75.9245, 460, 1, 15],
    [11.4250, 75.9320, 500, 1, 18],
    [11.4315, 75.9400, 540, 1, 15],
    [11.4380, 75.9480, 580, 1, 18],
    [11.4445, 75.9555, 620, 1, 15],
    [11.4510, 75.9630, 660, 1, 18],
    [11.4575, 75.9710, 700, 1, 15],
    [11.4640, 75.9788, 740, 1, 18],
    [11.4705, 75.9865, 775, 1, 15],
    [11.4770, 75.9940, 810, 1, 18],
    [11.4840, 76.0010, 840, 1, 15],
    [11.4910, 76.0075, 860, 1, 18],
    [11.4980, 76.0135, 872, 1, 20],
    [11.5055, 76.0168, 878, 1, 22],

    // ── Lakkidi viewpoint (Peak) ──
    // Real: Lakkidi 11.5133, 76.0195 (altitude ~700m, highest point)
    [11.5095, 76.0182, 880, 0, 25],
    [11.5133, 76.0195, 880, 0, 30],  // Lakkidi peak

    // ── Descent towards Vythiri (Downhill) ──
    // Real: Vythiri 11.5425, 76.0425
    [11.5170, 76.0215, 870, 2, 30],
    [11.5210, 76.0245, 855, 2, 28],
    [11.5248, 76.0280, 840, 2, 25],
    [11.5285, 76.0315, 820, 2, 28],
    [11.5320, 76.0348, 800, 2, 30],
    [11.5355, 76.0380, 780, 2, 28],
    [11.5390, 76.0405, 760, 2, 30],

    // ── Vythiri area ──
    // Real: Vythiri 11.5425, 76.0425
    [11.5425, 76.0425, 740, 0, 35],  // Vythiri
    [11.5465, 76.0455, 730, 0, 40],
    [11.5510, 76.0490, 720, 0, 40],

    // ── Vythiri to Kalpetta (Wayanad Plateau - Plain) ──
    // Real: Kalpetta 11.6087, 76.0816
    [11.5555, 76.0525, 710, 0, 45],
    [11.5600, 76.0560, 705, 0, 50],
    [11.5650, 76.0600, 700, 0, 50],
    [11.5700, 76.0635, 695, 0, 55],
    [11.5750, 76.0668, 690, 0, 55],
    [11.5800, 76.0700, 686, 0, 55],
    [11.5850, 76.0732, 682, 0, 55],
    [11.5900, 76.0762, 678, 0, 55],
    [11.5950, 76.0788, 675, 0, 55],
    [11.6000, 76.0808, 672, 0, 50],
    [11.6045, 76.0812, 670, 0, 45],

    // ── Kalpetta town ──
    // Real: Kalpetta 11.6087, 76.0816
    [11.6087, 76.0816, 668, 0, 35],  // Kalpetta town

    // ── Kalpetta to Sulthan Bathery ──
    // Real: Route goes east, Sulthan Bathery 11.6634, 76.2673
    [11.6120, 76.0880, 666, 0, 50],
    [11.6155, 76.0960, 665, 0, 55],
    [11.6190, 76.1050, 664, 0, 55],
    [11.6225, 76.1140, 663, 0, 55],
    [11.6260, 76.1235, 662, 0, 55],
    [11.6295, 76.1330, 661, 0, 55],
    [11.6330, 76.1430, 660, 0, 55],
    [11.6365, 76.1530, 659, 0, 55],
    [11.6400, 76.1630, 658, 0, 55],
    [11.6430, 76.1730, 657, 0, 55],
    [11.6460, 76.1835, 656, 0, 55],
    [11.6490, 76.1940, 655, 0, 55],
    [11.6518, 76.2050, 654, 0, 55],
    [11.6545, 76.2160, 653, 0, 50],
    [11.6570, 76.2270, 652, 0, 45],
    [11.6590, 76.2380, 651, 0, 40],
    [11.6610, 76.2490, 650, 0, 35],

    // ── Sulthan Bathery ──
    // Real: Sulthan Bathery KSRTC 11.6634, 76.2673
    [11.6620, 76.2580, 649, 0, 30],
    [11.6628, 76.2630, 648, 0, 25],
    [11.6634, 76.2673, 647, 0, 15],  // Sulthan Bathery Bus Stand
  ];

  /// Start the simulation for the given [tripId].
  /// Returns true immediately (no real hardware to initialize).
  Future<bool> startCapture(String tripId) async {
    if (_isRunning) return true;

    _tripId = tripId;
    _waypointIndex = 0;
    _segmentProgress = 0.0;
    _currentSpeed = 0.0;
    _currentYaw = 0.0;
    _isRunning = true;

    const int intervalMs = AppConstants.sensorIntervalMs; // 100 ms

    _timer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      _onTick,
    );

    return true;
  }

  /// Stop the simulation.
  void stopCapture() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  /// Dispose resources.
  void dispose() {
    stopCapture();
    _controller.close();
  }

  // ═══════════════════════════════════════════════════════════════════
  // SIMULATION ENGINE
  // ═══════════════════════════════════════════════════════════════════

  void _onTick(Timer timer) {
    if (_tripId == null) return;

    // Loop back when we reach the end
    if (_waypointIndex >= _waypoints.length - 1) {
      _waypointIndex = 0;
      _segmentProgress = 0.0;
    }

    final wp1 = _waypoints[_waypointIndex];
    final wp2 = _waypoints[_waypointIndex + 1];

    // Target speed for this road section (km/h → m/s)
    final targetSpeed = wp1[4] / 3.6;
    final terrain = wp1[3].toInt(); // 0=plain, 1=uphill, 2=downhill

    // Smoothly approach target speed
    final speedDiff = targetSpeed - _currentSpeed;
    _currentSpeed += speedDiff * 0.05 + _noise(0.2);
    _currentSpeed = _currentSpeed.clamp(2.0, 20.0);

    // Compute distance between current and next waypoint
    final wpDist = _haversine(wp1[0], wp1[1], wp2[0], wp2[1]);

    // How much progress per tick at current speed (10 Hz → 0.1 s)
    final progressPerTick = wpDist > 0 ? (_currentSpeed * 0.1) / wpDist : 0.1;
    _segmentProgress += progressPerTick;

    // Advance to next waypoint segment if needed
    if (_segmentProgress >= 1.0) {
      _segmentProgress -= 1.0;
      _waypointIndex++;
      if (_waypointIndex >= _waypoints.length - 1) {
        _waypointIndex = 0;
        _segmentProgress = 0.0;
      }
    }

    // Interpolate position along the road
    final p = _segmentProgress;
    final lat = wp1[0] + (wp2[0] - wp1[0]) * p;
    final lon = wp1[1] + (wp2[1] - wp1[1]) * p;
    final alt = wp1[2] + (wp2[2] - wp1[2]) * p;

    // Compute bearing for yaw rate
    final bearing = _bearing(wp1[0], wp1[1], wp2[0], wp2[1]);
    var yawDelta = bearing - _currentYaw;
    // Normalize to [-pi, pi]
    while (yawDelta > pi) yawDelta -= 2 * pi;
    while (yawDelta < -pi) yawDelta += 2 * pi;
    _currentYaw = bearing;

    // Yaw rate (rad/s)
    final yawRate = yawDelta * 2.0 + _noise(0.02);

    // Generate accelerations based on terrain type
    double ax, ay;
    switch (terrain) {
      case 1: // Uphill — more longitudinal decel, lateral in hairpins
        ax = _noise(0.8) + 0.3;
        ay = (_currentSpeed > 5 ? 0.5 : 0.1) * sin(_segmentProgress * pi) +
            _noise(0.3);
        break;
      case 2: // Downhill — braking events
        ax = _noise(0.6) - 0.2;
        ay = 0.3 * sin(_segmentProgress * pi * 2) + _noise(0.25);
        break;
      default: // Plain
        ax = _noise(0.3);
        ay = _noise(0.2);
    }

    final sample = RawSample(
      tripId: _tripId!,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      lat: lat + _noise(0.00002),    // ~2 m GPS jitter
      lon: lon + _noise(0.00002),
      speed: (_currentSpeed + _noise(0.3)).clamp(0.0, 25.0),
      ax: ax,
      ay: ay,
      yawRate: yawRate,
      altitude: alt + _noise(0.5),
    );

    _controller.add(sample);
  }

  // ─── Helpers ─────────────────────────────────────────────────────

  double _noise(double magnitude) =>
      (_rng.nextDouble() - 0.5) * 2 * magnitude;

  /// Haversine distance in meters.
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Bearing from point 1 to point 2 in radians.
  double _bearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = _toRad(lon2 - lon1);
    final y = sin(dLon) * cos(_toRad(lat2));
    final x = cos(_toRad(lat1)) * sin(_toRad(lat2)) -
        sin(_toRad(lat1)) * cos(_toRad(lat2)) * cos(dLon);
    return atan2(y, x);
  }

  double _toRad(double deg) => deg * pi / 180;
}
