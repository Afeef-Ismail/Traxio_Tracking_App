# KSRTC Master Driver Benchmarking System — Complete Codebase Guide

**Version:** 2.0 | **Date:** March 2026 | **Platform:** Flutter Android  
**Project:** NIT Calicut Internship — KSRTC Kerala Bus Driver Benchmarking

---

## 1. Project Overview

This Android app benchmarks KSRTC (Kerala State Road Transport Corporation) bus drivers against master-driver behaviour profiles established through research. The phone is mounted inside the bus and captures accelerometer, gyroscope, and GPS data at 10 Hz. As the bus travels, the app splits the journey into 100-metre segments, classifies each segment's terrain (Plain, Uphill Ghat, or Downhill Ghat), extracts 120 statistical features from the sensor data (8 physical attributes × 15 features each, covering both time-domain and frequency-domain analysis), and scores each segment against two benchmark clusters derived from expert driver data. After the trip ends, the app computes a 0–100 driving score, generates rule-based coaching insights, and calls the Google Gemini AI API to produce a personalised 3-part coaching report that references specific landmarks on the NH-766 Kozhikode–Sulthan Bathery route. The app supports role-based access (admin and driver), encrypted SQLite storage, editable benchmark thresholds, driver management, trip history with cached coaching reports, and a demo mode that simulates the entire sensor pipeline for testing without a real bus.

---

## 2. Directory Structure

```
lib/
├── main.dart                          # App entry point, MultiProvider setup, route definitions
├── config/
│   ├── constants.dart                 # All app-wide constants: sensor rates, thresholds, feature units, Gemini API key
│   └── benchmark_tables.dart          # Hardcoded master-driver benchmark ranges (fallback for DB)
├── models/
│   ├── raw_model.dart                 # RawSample data class: one sensor reading (lat, lon, speed, ax, ay, yaw, alt)
│   ├── segment_model.dart             # SegmentData class: one 100m segment with metadata and landmark
│   └── trip_model.dart                # TripSummary class: aggregated trip statistics, score, coaching report
├── database/
│   └── db_helper.dart                 # SQLite database: 7 tables, all CRUD operations, migrations, seed data
├── providers/
│   ├── auth_provider.dart             # Authentication state: login, logout, session timeout, role checks
│   └── trip_provider.dart             # Trip recording state: coordinates sensors, processor, and UI updates
├── services/
│   ├── sensor_service.dart            # Real device sensor capture: accelerometer + gyroscope + GPS at 10 Hz
│   ├── demo_sensor_service.dart       # Simulated sensor capture: 93 NH-766 waypoints with altitude and IMU
│   ├── segmentation_service.dart      # Accumulates GPS distance, closes segments every 100m
│   ├── terrain_service.dart           # Classifies terrain from altitude slope, reads thresholds from DB
│   └── gemini_coaching_service.dart   # Google Gemini API client: builds prompt, sends request, parses response
├── analytics/
│   ├── trip_processor.dart            # Central pipeline: receives samples, drives segmentation, triggers features
│   ├── feature_engine.dart            # Extracts 120 features (11 time-domain + 4 frequency-domain × 8 attributes)
│   ├── fft_engine.dart                # Radix-2 FFT implementation for frequency-domain feature extraction
│   ├── deviation_engine.dart          # Scores segments against benchmark clusters, loads ranges from DB
│   ├── trip_analytics.dart            # Computes trip summary: cluster percentages, terrain averages, saves to DB
│   ├── coaching_engine.dart           # Rule-based coaching insights: analyses trip data, generates text cards
│   └── score_calculator.dart          # Computes 0-100 score from overall average deviation
├── utils/
│   └── landmark_utils.dart            # 17 NH-766 landmarks with GPS coordinates, nearest-landmark lookup
├── ui/
│   ├── theme/
│   │   ├── app_theme.dart             # Light and dark ThemeData definitions
│   │   └── app_colors.dart            # Colour constants: primary blue, backgrounds, terrain badge colours
│   ├── widgets/
│   │   └── admin_guard.dart           # Route guard widget: blocks non-admin users from admin screens
│   └── screens/
│       ├── splash_screen.dart         # 2-second animated splash, then navigates to /login
│       ├── login_screen.dart          # Username/password form, SHA-256 auth, role-based routing, demo buttons
│       ├── home_screen.dart           # Driver dashboard: map, Start Trip button, session timeout timer
│       ├── trip_in_progress_screen.dart # Live trip: speed display, terrain badge, segment counter, Stop button
│       ├── trip_summary_screen.dart   # Post-trip: score badge, Gemini coaching, rule cards, worst segment
│       ├── trip_history_screen.dart   # List of past trips with score badges, tap to view coaching report
│       ├── segment_list_screen.dart   # List of segments in a trip with terrain badges and deviation scores
│       ├── segment_detail_screen.dart # 120 features for one segment, benchmark comparison, landmark label
│       ├── segment_feature_table.dart # Reusable widget: renders feature name, value, unit, and range bar
│       ├── settings_screen.dart       # Driver settings: theme toggle, demo mode info, logout button
│       ├── admin_home_screen.dart     # Admin dashboard: All Trips, Threshold Settings, Driver Mgmt, Benchmarks
│       ├── threshold_editor_screen.dart # Edit terrain thresholds and benchmark ranges (tabbed interface)
│       ├── driver_management_screen.dart # Add/delete drivers, edit bus numbers, view driver list
│       ├── driver_profile_screen.dart # Driver stats: total trips, avg deviation, score history chart
│       └── coaching_report_screen.dart # Full coaching report for a trip: score, AI coach, rule cards, worst seg
test/
├── demo_flow_test.dart                # 7 widget tests: login routing, dev buttons, role-based navigation
└── auth_provider_test.dart            # 7 unit tests: session timeout, login/logout, role properties
```

---

## 3. App Startup Flow

### Step-by-step sequence from APK launch to login screen:

1. **Android launches `main()`** in `lib/main.dart`.

2. **`main()` calls `WidgetsFlutterBinding.ensureInitialized()`** — this initialises Flutter's binding to the native platform before any async work.

3. **`main()` calls `runApp(const KsrtcBenchmarkingApp())`** — this mounts the root widget.

4. **`KsrtcBenchmarkingApp.build()` creates a `MultiProvider`** that wraps the entire widget tree with two providers:
   ```dart
   MultiProvider(
     providers: [
       ChangeNotifierProvider(create: (_) => AuthProvider()),
       ChangeNotifierProvider(create: (_) => TripProvider()),
     ],
     child: ... MaterialApp ...
   )
   ```
   - `AuthProvider()` constructor: initialises `_currentUser = null`, `_lastActivityTime = null`. No async work here.
   - `TripProvider()` constructor: creates either `DemoSensorService()` or `SensorService()` based on `AppConstants.demoMode`. Creates `SegmentationService()`, `TripProcessor()`. No sensor capture starts yet.

5. **`MaterialApp` is configured** with:
   - `initialRoute: '/'` which points to `SplashScreen`
   - Named routes: `'/login'`, `'/home'`, `'/admin'`, `'/settings'`, `'/trip-history'`, `'/coaching-report'`
   - Theme: `AppTheme.lightTheme` and `AppTheme.darkTheme` with system-mode switching

6. **`SplashScreen` loads** (`splash_screen.dart`):
   - `initState()` starts a `Future.delayed(Duration(seconds: 2))` timer
   - During the 2 seconds, an animated KSRTC logo and app name are displayed with a fade-in
   - After 2 seconds, `Navigator.pushReplacementNamed(context, '/login')` replaces the splash with the login screen

7. **`LoginScreen` loads** (`login_screen.dart`):
   - Two `TextEditingController`s are created for username and password fields
   - If `AppConstants.demoMode == true`, three quick-login buttons are rendered below the form
   - The app is now waiting for user interaction

### What happens in the background during startup:

Nothing database-related happens until the first DB operation is triggered. `DbHelper` uses a lazy singleton pattern:
```dart
static Database? _database;
Future<Database> get database async {
  if (_database != null) return _database!;
  _database = await _initDatabase();
  return _database!;
}
```
The database is only opened when the first query runs (typically during `login()`). At that point, `_initDatabase()` calls `openDatabase()` with `onCreate` which creates all 7 tables and seeds default data (admin/driver users + config values + benchmark ranges).

---

## 4. Authentication Flow

### End-to-end login sequence:

1. **User types credentials** into the `_usernameController` and `_passwordController` text fields on `LoginScreen`.

2. **User taps "Sign In" button** (or one of the demo quick-login buttons which pre-fill credentials and call the same function).

3. **`_handleLogin()` is called** in `login_screen.dart`:
   ```dart
   void _handleLogin() async {
     if (!_formKey.currentState!.validate()) return;
     setState(() { _isLoading = true; _errorMessage = ''; });
     final authProvider = context.read<AuthProvider>();
     final success = await authProvider.login(
       _usernameController.text.trim(),
       _passwordController.text,
     );
     ...
   }
   ```

4. **`AuthProvider.login(username, password)`** is called in `auth_provider.dart`:
   ```dart
   Future<bool> login(String username, String password) async {
     final db = DbHelper.instance;
     final passwordHash = DbHelper.hashPassword(password);
     final user = await db.getUserByUsername(username);
     if (user == null) return false;
     if (user['password_hash'] != passwordHash) return false;
     _currentUser = user;
     _lastActivityTime = DateTime.now();
     notifyListeners();
     return true;
   }
   ```

5. **SHA-256 hash is computed** in `DbHelper.hashPassword()`:
   ```dart
   static String hashPassword(String password) {
     final bytes = utf8.encode(password);
     final digest = sha256.convert(bytes);
     return digest.toString();
   }
   ```
   This produces a 64-character hex string. For example, `'admin123'` becomes `'240be518fabd2724ddb6f04eeb9d56b5...`'.

6. **DB lookup** in `DbHelper.getUserByUsername()`:
   ```dart
   Future<Map<String, dynamic>?> getUserByUsername(String username) async {
     final db = await database;
     final results = await db.query('users',
       where: 'username = ?', whereArgs: [username], limit: 1);
     return results.isEmpty ? null : results.first;
   }
   ```

7. **Hash comparison**: The stored `password_hash` column value is compared with the freshly computed hash. If they match, the login succeeds.

8. **State update**: `_currentUser` is set to the user map (containing `id`, `username`, `role`, `bus_number`, `created_at`). `_lastActivityTime` is set to `DateTime.now()`. `notifyListeners()` fires, which causes any widget watching `AuthProvider` to rebuild.

9. **Back in `_handleLogin()`**, if `success == true`:
   ```dart
   if (authProvider.isAdmin) {
     Navigator.pushNamedAndRemoveUntil(context, '/admin', (route) => false);
   } else {
     Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
   }
   ```
   `pushNamedAndRemoveUntil` with `(route) => false` clears the entire navigation stack, so pressing the back button after login does not return to the login screen.

10. **If `success == false`**: `_errorMessage` is set to `'Invalid username or password'` and `setState()` triggers a rebuild showing the error message in red.

### Session timeout:

- `HomeScreen` starts a `Timer.periodic(Duration(minutes: 5))` that calls `authProvider.checkSessionTimeout()`.
- `TripInProgressScreen` starts a `Timer.periodic(Duration(minutes: 1))` that calls `authProvider.updateActivity()` to keep the session alive during recording.
- `checkSessionTimeout()` compares `DateTime.now()` with `_lastActivityTime`. If the difference exceeds 30 minutes, it calls `logout()` and returns `true`.
- When the timer detects a timeout, the screen navigates to `'/login'` and clears the stack.

---

## 5. Trip Recording Flow

This is the core workflow of the app. Here is every step in numbered order:

### Step 1: User taps "Start Trip"

In `home_screen.dart`, the Start Trip button's `onPressed` calls:
```dart
final tripProvider = context.read<TripProvider>();
await tripProvider.startTrip();
Navigator.pushNamed(context, '/trip-in-progress');
```

### Step 2: TripProvider.startTrip() initialises the pipeline

In `trip_provider.dart`, `startTrip()`:
```dart
Future<void> startTrip() async {
  _tripId = DateTime.now().millisecondsSinceEpoch.toString();
  _isRecording = true;
  _segmentCount = 0;
  _currentTerrain = 'Plain';
  _currentSpeed = 0.0;
  _segments.clear();
  notifyListeners();

  // Reset the segmentation service
  _segmentationService.reset();

  // Initialise the trip processor
  await _tripProcessor.init(_tripId!);

  if (AppConstants.demoMode) {
    // Demo: start simulated sensor stream
    final demoService = _sensorService as DemoSensorService;
    _sensorSubscription = demoService.start().listen(_onSensorData);
  } else {
    // Real: request permissions, calibrate, start real sensors
    final realService = _sensorService as SensorService;
    await realService.requestPermissions();
    _sensorSubscription = realService.startCapture(_tripId!).listen(_onSensorData);
  }
}
```

### Step 3: Sensor capture begins emitting data

**Demo mode** (`demo_sensor_service.dart`):
- A `Timer.periodic(Duration(milliseconds: 100))` fires `_tick()` 10 times per second.
- Each tick interpolates position between two consecutive waypoints from the 93-waypoint list.
- It computes: latitude, longitude (interpolated + 2m GPS jitter), speed (smooth approach to terrain target speed), altitude (interpolated between anchor points), lateral acceleration `ax`, longitudinal acceleration `ay` (terrain-dependent with noise), yaw rate (computed from bearing change between waypoints).
- Each tick emits one `RawSample` object to the stream.

**Real mode** (`sensor_service.dart`):
- `geolocator` provides GPS updates (lat, lon, speed, altitude).
- `sensors_plus` provides accelerometer (ax, ay) and gyroscope (yaw rate) at the device's native rate.
- A fusion timer at 10 Hz combines the latest GPS and IMU readings into one `RawSample` per tick.

**RawSample structure** (`raw_model.dart`):
```dart
class RawSample {
  final int timestamp;    // milliseconds since epoch
  final double lat;       // degrees
  final double lon;       // degrees
  final double speed;     // m/s
  final double ax;        // m/s² (lateral)
  final double ay;        // m/s² (longitudinal)
  final double yawRate;   // rad/s
  final double altitude;  // metres
}
```

### Step 4: Raw samples flow into the trip processor

Every `RawSample` emitted by the sensor service is received by `_onSensorData()` in `trip_provider.dart`:
```dart
void _onSensorData(RawSample sample) {
  _currentSpeed = sample.speed * 3.6; // m/s → km/h
  _currentPosition = LatLng(sample.lat, sample.lon);
  _gpsTrail.add(_currentPosition!);

  // Feed to trip processor
  _tripProcessor.addSample(sample);
  notifyListeners();
}
```

### Step 5: Trip processor accumulates samples and checks for segment closure

In `trip_processor.dart`, `addSample()`:
```dart
void addSample(RawSample sample) {
  _currentSamples.add(sample);

  // Write raw data to DB
  _dbHelper.insertRawData(_tripId, sample);

  // Check if we've covered 100m since last segment start
  _segmentationService.addPoint(sample.lat, sample.lon);
  if (_segmentationService.currentDistance >= AppConstants.segmentDistanceMeters) {
    _closeSegment();
  }
}
```

### Step 6: Segment closes at exactly 100 metres

**How distance is accumulated** (`segmentation_service.dart`):
```dart
void addPoint(double lat, double lon) {
  if (_lastLat != null && _lastLon != null) {
    final d = _haversine(_lastLat!, _lastLon!, lat, lon);
    if (d < AppConstants.maxGpsJumpMeters) {
      _currentDistance += d;
    }
  }
  _lastLat = lat;
  _lastLon = lon;
}
```

**Haversine formula** (computes great-circle distance between two GPS points):
```dart
double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371000.0; // Earth radius in metres
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = sin(dLat/2) * sin(dLat/2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) *
      sin(dLon/2) * sin(dLon/2);
  return R * 2 * atan2(sqrt(a), sqrt(1 - a));
}
```

When `_currentDistance >= 100.0`, the segment is closed. The distance counter resets to `0.0` and a new segment begins accumulating.

**Edge case**: GPS jumps greater than `maxGpsJumpMeters` (30m) per sample are discarded to prevent teleportation spikes from corrupting the distance calculation.

### Step 7: Terrain is classified for the segment

In `_closeSegment()` within `trip_processor.dart`:
```dart
final altitude1 = _currentSamples.first.altitude;
final altitude2 = _currentSamples.last.altitude;
final terrain = await _terrainService.classify(altitude1, altitude2, segmentDistance);
```

**Terrain classification** (`terrain_service.dart`):
```dart
Future<String> classify(double startAlt, double endAlt, double distance) async {
  await _loadThresholds(); // Load from DB config table (cached after first call)
  final slope = (endAlt - startAlt) / distance;
  if (slope > _uphillThreshold) return 'Uphill';    // default: 0.02
  if (slope < _downhillThreshold) return 'Downhill'; // default: -0.02
  return 'Plain';
}
```

The slope formula: `slope = (end_altitude - start_altitude) / horizontal_distance`. A slope of 0.02 means 2 metres of elevation gain per 100 metres of travel — a 2% grade. The Thamarassery Ghat section has slopes of 3-7%, which exceeds the 0.02 threshold and is classified as Uphill.

**Runtime threshold loading**: On first call, `_loadThresholds()` queries the `config` table for keys `terrain_slope_uphill_threshold` and `terrain_slope_downhill_threshold`. The values are cached in `_uphillThreshold` and `_downhillThreshold` instance variables. If the DB read fails, it falls back to `AppConstants.uphillSlopeThreshold` (0.02) and `AppConstants.downhillSlopeThreshold` (-0.02).

### Step 8: Nearest NH-766 landmark is assigned

In `_closeSegment()`:
```dart
final landmark = LandmarkUtils.getNearestLandmark(
  _currentSamples.last.lat,
  _currentSamples.last.lon,
);
```

**Landmark lookup** (`landmark_utils.dart`):
- Contains 17 landmarks along NH-766 with their GPS coordinates (e.g., `'Thamarassery': (11.3678, 75.8595)`).
- `getNearestLandmark()` iterates all landmarks, computes Haversine distance from the segment's end point to each landmark, and returns the name of the closest one if it is within 2 km.
- If no landmark is within 2 km, it returns `'NH-766'`.

### Step 9: 120 features are extracted

In `_closeSegment()`:
```dart
final features = _featureEngine.extract(_currentSamples);
```

**Feature extraction** (`feature_engine.dart`):

First, the raw samples are converted into 8 attribute arrays:

| Attribute | Source | Unit Conversion |
|-----------|--------|-----------------|
| Speed | `sample.speed` | × 3.6 (m/s → km/h) |
| ay | `sample.ay` | ÷ 9.80665 (m/s² → g) |
| ax | `sample.ax` | ÷ 9.80665 (m/s² → g) |
| YR | `sample.yawRate` | × (180/π) (rad/s → deg/s) |
| Jx | `d(ax)/dt` | finite difference ÷ 9.80665 (→ g/s) |
| Jy | `d(ay)/dt` | finite difference ÷ 9.80665 (→ g/s) |
| VV | `d(altitude)/dt` | × 3.6 (m/s → km/h) |
| R | `speed / yawRate` | capped at 10,000m |

Then, a 3-point moving average smooths each array: `smoothed[i] = (x[i-1] + x[i] + x[i+1]) / 3`.

Then, for each of the 8 attributes, 15 features are computed:

**Time-domain features (11):**

| # | Feature | Formula |
|---|---------|---------|
| 1 | **Max** | `max(T)` — largest value in the array |
| 2 | **Min** | `min(T)` — smallest value |
| 3 | **Mean** | `(1/n) × Σ Ti` — arithmetic average |
| 4 | **Std** | `sqrt((1/(n-1)) × Σ(Ti - Mean)²)` — sample standard deviation |
| 5 | **PeakToPeak** | `Max - Min` — total range of values |
| 6 | **ARV** | `(1/n) × Σ|Ti|` — average rectified value (mean of absolute values) |
| 7 | **RMS** | `sqrt((1/n) × Σ Ti²)` — root mean square |
| 8 | **ShapeFactor** | `RMS / ARV` — ratio indicating signal shape (1.0 for constant, higher for peaky) |
| 9 | **CrestFactor** | `Max / RMS` — ratio of peak to RMS (high = sharp spikes) |
| 10 | **ImpulseFactor** | `Max / ARV` — ratio of peak to average absolute (high = sudden impulses) |
| 11 | **MarginFactor** | `Max / ((1/n × Σ √|Ti|)²)` — peak relative to the square of mean root amplitude |

**Frequency-domain features (4):**

| # | Feature | Formula |
|---|---------|---------|
| 12 | **AvgAmplitude** | `(1/m) × Σ|X(k)|` — mean FFT magnitude across all frequency bins |
| 13 | **FreqCentroid** | `(Σ fk × |X(k)|) / (Σ |X(k)|)` — weighted centre frequency |
| 14 | **FreqVariance** | `(Σ (fk - fc)² × |X(k)|) / (Σ |X(k)|)` — spread around centroid |
| 15 | **SpectralEntropy** | `-Σ P(k) × log₂(P(k))` where `P(k) = |X(k)|² / Σ|X(k)|²` — spectral disorder |

**Total: 15 features × 8 attributes = 120 features per segment.**

### Step 10: FFT is applied for frequency-domain features

In `feature_engine.dart`, the `_computeFrequencyFeatures()` method calls `FftEngine.fft()`:

**FFT implementation** (`fft_engine.dart`):
- Implements the Cooley-Tukey radix-2 FFT algorithm in pure Dart (no external library).
- Input: a `List<double>` of time-domain samples.
- The input is zero-padded to the next power of 2 (e.g., 70 samples → 128).
- Output: a `List<Complex>` of frequency-domain coefficients.
- Only the first half of the output is used (positive frequencies), as the input is real-valued.
- The magnitude `|X(k)|` of each complex coefficient is computed as `sqrt(real² + imag²)`.
- The frequency of each bin is `k × (samplingRate / N)` where `samplingRate = 10 Hz` and `N` is the padded length.

### Step 11: Deviation is scored against both benchmark clusters

In `_closeSegment()`:
```dart
final scores = await _deviationEngine.score(terrain, features);
```

**Deviation scoring** (`deviation_engine.dart`):

1. **Load benchmark ranges**: On first call, queries the `benchmark_config` table for all ranges. If the DB read fails, falls back to `benchmark_tables.dart` hardcoded values. Ranges are cached in memory for the trip duration.

2. **Select terrain-specific features**: For each terrain type, exactly 10 features (out of 120) are designated as the most discriminating for that terrain. These are defined in `benchmark_tables.dart`:
   - **Plain**: Jy_Max, Jx_Max, Speed_Max, ay_FreqVariance, VV_Min, ax_Max, Speed_FreqCentroid, Jx_MarginFactor, YR_SpectralEntropy, R_SpectralEntropy
   - **Uphill**: Speed_Max, Jy_Max, VV_Max, Jx_Max, YR_MarginFactor, ax_Max, VV_PeakToPeak, ax_SpectralEntropy, Jy_SpectralEntropy, Speed_SpectralEntropy
   - **Downhill**: Speed_Max, Speed_SpectralEntropy, Jy_SpectralEntropy, ax_Max, ay_Max, Jy_Max, ax_SpectralEntropy, ax_Min, ax_FreqVariance, Jy_MarginFactor

3. **Compute deviation per feature per cluster**:
   ```dart
   double computeDeviation(double value, double minRange, double maxRange) {
     if (value < minRange) return minRange - value;
     if (value > maxRange) return value - maxRange;
     return 0.0; // Within range — no deviation
   }
   ```
   If a feature value falls within the benchmark range `[min, max]`, the deviation is 0. If it falls outside, the deviation is the absolute distance to the nearest range boundary.

4. **Sum deviations for each cluster**:
   ```dart
   double cluster0Deviation = sum of 10 feature deviations against Cluster 0 ranges
   double cluster1Deviation = sum of 10 feature deviations against Cluster 1 ranges
   ```

5. **Determine matched cluster**: The cluster with the lower total deviation is the match.
   ```dart
   int matchedCluster = cluster0Deviation <= cluster1Deviation ? 0 : 1;
   ```

6. **Return**: `{cluster0Deviation, cluster1Deviation, matchedCluster}`.

### Step 12: Segment data is written to SQLite

In `_closeSegment()`, after all computations:

**Order of DB writes:**

1. **`segments` table** — `insertSegment()`:
   ```
   trip_id, segment_index, start_time, end_time, terrain, distance,
   start_lat, start_lon, end_lat, end_lon, sample_count, is_valid, nearest_landmark
   ```

2. **`features` table** — `insertFeatures()` (120 rows per segment):
   ```
   segment_id, attribute, feature_name, value
   ```
   Each of the 120 features gets its own row, e.g., `(segId, 'Speed', 'Max', 52.3)`.

3. **`segment_scores` table** — `insertSegmentScore()`:
   ```
   segment_id, cluster0_deviation, cluster1_deviation, matched_cluster
   ```

4. **`raw_data` table** — already written sample-by-sample in `addSample()` before the segment closes:
   ```
   trip_id, timestamp, lat, lon, speed, ax, ay, yaw_rate, altitude
   ```

### Step 13: Trip summary is computed when Stop Trip is tapped

When the user taps Stop Trip, `TripProvider.stopTrip()` is called:
```dart
Future<void> stopTrip() async {
  _isRecording = false;
  _sensorSubscription?.cancel();
  if (AppConstants.demoMode) {
    (_sensorService as DemoSensorService).stop();
  } else {
    (_sensorService as SensorService).stopCapture();
  }
  await _tripProcessor.finishTrip();
  notifyListeners();
}
```

`TripProcessor.finishTrip()` calls `TripAnalytics.computeAndSave()`:

**Trip analytics** (`trip_analytics.dart`):
1. Queries all `segment_scores` for the trip.
2. Counts how many segments matched Cluster 0 and Cluster 1.
3. Computes percentages: `cluster0Percent = cluster0Count / totalSegments * 100`.
4. Groups segments by terrain and computes average deviation per terrain.
5. Computes overall average deviation across all segments.
6. Computes the 0-100 score (see Step 14).
7. Writes one row to `trip_summaries`:
   ```
   trip_id, total_segments, cluster0_percent, cluster1_percent,
   avg_deviation_plain, avg_deviation_uphill, avg_deviation_downhill,
   overall_avg_deviation, start_time, end_time, score
   ```

### Step 14: The 0-100 score is calculated

**Score calculator** (`score_calculator.dart`):
```dart
static int computeScore(double overallAvgDeviation) {
  const maxExpected = AppConstants.maxExpectedDeviation; // 50.0
  final score = (100 - (overallAvgDeviation / maxExpected) * 100).round();
  return score.clamp(0, 100);
}
```

Examples:
- Deviation 0.0 → Score 100 (perfect match to master driver)
- Deviation 25.0 → Score 50 (halfway)
- Deviation 50.0+ → Score 0 (very different from master driver)

---

## 6. AI Coaching Flow

### What happens after Stop Trip:

#### 6.1 Rule-based engine

**File:** `coaching_engine.dart`  
**Function:** `CoachingEngine.analyze(TripSummary summary, List<SegmentDetail> segments)`

The engine checks these conditions and generates text cards:

| Rule | Condition | Card Title |
|------|-----------|------------|
| High deviation | `overallAvgDeviation > 20` | "Needs Improvement" |
| Low deviation | `overallAvgDeviation < 10` | "Excellent Driving" |
| Uphill trouble | `avgDeviationUphill > avgDeviationPlain * 1.5` | "Uphill Driving" |
| Downhill trouble | `avgDeviationDownhill > avgDeviationPlain * 1.5` | "Downhill Driving" |
| Cluster dominance | `cluster0Percent > 70` or `cluster1Percent > 70` | "Driving Pattern: Cluster X Dominant" |
| Speed issues | Checks Speed_Max feature values | "Speed Management" |

Each card contains: title (bold), description (specific advice), severity colour (green/yellow/red).

#### 6.2 Gemini API call

**File:** `gemini_coaching_service.dart`  
**Function:** `GeminiCoachingService.getCoachingReport()`

**Prompt construction:**
```
You are a professional KSRTC bus driver coach. Based on this trip data,
write a coaching message in simple English...

Trip score: {score}/100.
Route: Kozhikode to Sulthan Bathery (NH-766).
Segments: {totalSegments} total — Plain: {plainCount} (avg deviation {plainAvgDev}),
Uphill: {uphillCount} (avg deviation {uphillAvgDev}),
Downhill: {downhillCount} (avg deviation {downhillAvgDev}).
Worst segment: near {worstSegmentLandmark} (Segment {worstSegmentNumber},
{worstSegmentTerrain} terrain, deviation {worstSegmentDeviation}).
Top 3 driving issues at that location: ...
```

**API call:**
```dart
final response = await http.post(
  Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'contents': [{'parts': [{'text': prompt}]}],
    'generationConfig': {'maxOutputTokens': 2048},
  }),
).timeout(Duration(seconds: 30));
```

**Response parsing:**
- The JSON response contains `candidates[0].content.parts[0].text`.
- The text is returned as-is (it contains the 3-part structure: SUMMARY, STRENGTHS, IMPROVEMENTS).

**Error handling:**
- Network errors, timeouts, and API errors are caught silently.
- On any failure, `null` is returned — the UI shows "AI coaching unavailable" instead.
- The app never crashes due to a Gemini failure.

#### 6.3 Caching in SQLite

After a successful Gemini response:
```dart
await _dbHelper.updateCoachingReport(tripId, responseText);
```
This writes the full text to the `coaching_report` column in `trip_summaries`.

#### 6.4 Loading from cache on revisit

**File:** `coaching_report_screen.dart`  
**Function:** `_loadData()` in `initState()`

```dart
final summary = await DbHelper.instance.getTripSummary(widget.tripId);
// summary.coachingReport contains the cached text (or null if never fetched)
```

The screen checks `summary.coachingReport`:
- If non-null and non-empty → displays the cached text immediately, no API call.
- If null → shows "No coaching report available for this trip".

No new Gemini API call is ever made when viewing a trip from history.

---

## 7. Admin Workflows

### 7.1 Editing terrain thresholds

1. Admin taps "Threshold Settings" on `AdminHomeScreen`.
2. `ThresholdEditorScreen` loads in `initState()`:
   ```dart
   final configs = await DbHelper.instance.getAllConfig();
   ```
3. All key-value pairs from the `config` table are displayed as editable TextFields.
4. Admin changes a value (e.g., `terrain_slope_uphill_threshold` from `0.02` to `0.025`).
5. Admin taps Save. For each changed value:
   ```dart
   await DbHelper.instance.setConfig(key, newValue);
   ```
   `setConfig()` uses an upsert: `INSERT OR REPLACE INTO config (key, value, updated_at) VALUES (?, ?, ?)`.
6. **How TerrainService picks up the new value at runtime**: `TerrainService` has a cache (`_thresholdsLoaded` flag). When the admin saves, the cache is NOT automatically invalidated in the current session. However, the next trip that starts will create a fresh `TripProcessor` which creates a fresh `TerrainService`, and `_loadThresholds()` will read the new DB values. To force immediate effect, `TerrainService.clearCache()` can be called.

### 7.2 Editing benchmark ranges

1. Admin taps "Benchmark Ranges" on `AdminHomeScreen`.
2. `ThresholdEditorScreen` switches to the "Benchmark Ranges" tab.
3. Three expandable sections: Plain, Uphill, Downhill. Each shows Cluster 0 and Cluster 1 feature ranges.
4. Admin edits a min or max value and taps Save.
5. For each changed range:
   ```dart
   await DbHelper.instance.updateBenchmarkRange(terrain, cluster, featureName, minValue, maxValue);
   ```
6. **How DeviationEngine uses the new values**: `DeviationEngine` loads ranges from DB on first call via `_loadBenchmarkRanges()`. Values are cached in memory for the trip duration. The next trip session will load fresh values. The `benchmark_tables.dart` hardcoded values serve as fallback if the DB read fails.
7. Admin can tap "Reset to Defaults" to restore all ranges from `benchmark_tables.dart`.

### 7.3 Adding a new driver

1. Admin taps "Driver Management" on `AdminHomeScreen`.
2. Taps the "+" FAB button.
3. A dialog appears with username, password, and bus number fields.
4. Admin fills in the fields and taps "Add".
5. The password is hashed:
   ```dart
   final hash = DbHelper.hashPassword(password);
   ```
6. The user is created:
   ```dart
   await DbHelper.instance.createUser(username, hash, 'driver');
   ```
   This inserts into the `users` table with `role = 'driver'`.
7. The driver list refreshes to show the new driver.

### 7.4 Updating bus number

1. Admin taps the pencil icon next to a driver's name.
2. A dialog appears with a TextField pre-filled with the current bus number.
3. Admin types a new bus number (e.g., `KL-39-A-5678`).
4. Validation: soft warning if format doesn't match `KL-DD-X-XXXX` pattern (does not block submission).
5. On Save:
   ```dart
   await DbHelper.instance.updateBusNumber(userId, busNumber);
   ```
   Updates the `bus_number` column in the `users` table.
6. The new bus number appears in grey below the driver's username in the list.

### 7.5 Viewing a driver's trips and coaching report

1. Admin taps on a driver name in the Driver Management screen.
2. Navigates to `DriverProfileScreen(userId: id, username: name)`.
3. The profile queries:
   ```dart
   final trips = await DbHelper.instance.getTripsForUser(userId);
   ```
   This joins `trip_summaries` with a user-trip mapping.
4. The profile shows: total trips, overall average deviation, best/worst terrain, score history chart.
5. The latest trip's cached `coaching_report` is displayed in an "AI Coach" card.
6. Admin can tap any trip to open `CoachingReportScreen(tripId: tripId)` for the full report.

---

## 8. Database Reference

### Database: `ksrtc_benchmarking.db` (SQLite, encrypted via sqflite_sqlcipher)

---

#### Table: `raw_data`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment row ID |
| trip_id | TEXT | Trip identifier (timestamp string) |
| timestamp | INTEGER | Milliseconds since epoch |
| lat | REAL | Latitude in degrees |
| lon | REAL | Longitude in degrees |
| speed | REAL | Speed in m/s |
| ax | REAL | Lateral acceleration in m/s² |
| ay | REAL | Longitudinal acceleration in m/s² |
| yaw_rate | REAL | Yaw rate in rad/s |
| altitude | REAL | Altitude in metres |

**Written by:** `TripProcessor.addSample()` → `DbHelper.insertRawData()`  
**Read by:** Not typically read back (archival; could be used for replay)

---

#### Table: `segments`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment row ID / segment_id |
| trip_id | TEXT | Trip identifier |
| segment_index | INTEGER | 0-based segment number within the trip |
| start_time | INTEGER | Timestamp of first sample in segment |
| end_time | INTEGER | Timestamp of last sample in segment |
| terrain | TEXT | 'Plain', 'Uphill', or 'Downhill' |
| distance | REAL | Actual distance in metres (≈100) |
| start_lat | REAL | GPS latitude at segment start |
| start_lon | REAL | GPS longitude at segment start |
| end_lat | REAL | GPS latitude at segment end |
| end_lon | REAL | GPS longitude at segment end |
| sample_count | INTEGER | Number of raw samples in segment |
| is_valid | INTEGER | 1 if segment has enough samples (≥5) |
| nearest_landmark | TEXT | Name of nearest NH-766 landmark |

**Written by:** `TripProcessor._closeSegment()` → `DbHelper.insertSegment()`  
**Read by:** `SegmentListScreen`, `CoachingReportScreen`, `TripAnalytics`

---

#### Table: `features`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment row ID |
| segment_id | INTEGER FK | References segments.id |
| attribute | TEXT | One of: Speed, ay, ax, YR, Jx, Jy, VV, R |
| feature_name | TEXT | One of the 15 feature names (Max, Min, ..., SpectralEntropy) |
| value | REAL | Computed feature value |

**Written by:** `TripProcessor._closeSegment()` → `DbHelper.insertFeatures()`  
**Read by:** `SegmentDetailScreen`, `SegmentFeatureTable`  
**Row count:** 120 rows per segment (8 attributes × 15 features)

---

#### Table: `segment_scores`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment row ID |
| segment_id | INTEGER FK | References segments.id |
| cluster0_deviation | REAL | Sum of 10 feature deviations vs Cluster 0 |
| cluster1_deviation | REAL | Sum of 10 feature deviations vs Cluster 1 |
| matched_cluster | INTEGER | 0 or 1 (whichever had lower deviation) |

**Written by:** `TripProcessor._closeSegment()` → `DbHelper.insertSegmentScore()`  
**Read by:** `TripAnalytics.computeAndSave()`, `SegmentDetailScreen`

---

#### Table: `trip_summaries`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment row ID |
| trip_id | TEXT UNIQUE | Trip identifier |
| total_segments | INTEGER | Count of valid segments |
| cluster0_percent | REAL | % of segments matching Cluster 0 |
| cluster1_percent | REAL | % of segments matching Cluster 1 |
| avg_deviation_plain | REAL | Mean deviation for Plain segments |
| avg_deviation_uphill | REAL | Mean deviation for Uphill segments |
| avg_deviation_downhill | REAL | Mean deviation for Downhill segments |
| overall_avg_deviation | REAL | Mean deviation across all segments |
| start_time | INTEGER | Trip start timestamp |
| end_time | INTEGER | Trip end timestamp |
| score | REAL | 0-100 driving score |
| coaching_report | TEXT | Cached Gemini AI coaching response |

**Written by:** `TripAnalytics.computeAndSave()` → `DbHelper.insertTripSummary()`  
**Updated by:** `GeminiCoachingService` → `DbHelper.updateCoachingReport()`  
**Read by:** `TripSummaryScreen`, `TripHistoryScreen`, `CoachingReportScreen`, `DriverProfileScreen`, `AdminHomeScreen`

---

#### Table: `users`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment row ID |
| username | TEXT UNIQUE | Login username |
| password_hash | TEXT | SHA-256 hash of password (64 hex chars) |
| role | TEXT | 'admin' or 'driver' (CHECK constraint) |
| bus_number | TEXT | Kerala bus plate (e.g., KL-39-A-5678), nullable |
| created_at | TEXT | ISO 8601 timestamp of account creation |

**Written by:** `DbHelper._seedUsers()` (first launch), `DbHelper.createUser()` (admin adds driver)  
**Read by:** `AuthProvider.login()` → `DbHelper.getUserByUsername()`, `DriverManagementScreen` → `DbHelper.getAllDrivers()`

---

#### Table: `config`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment row ID |
| key | TEXT UNIQUE | Configuration key name |
| value | TEXT | Configuration value (stored as string, parsed by consumer) |
| updated_at | TEXT | ISO 8601 timestamp of last update |

**Default keys:**

| Key | Default Value | Used By |
|-----|--------------|---------|
| terrain_slope_uphill_threshold | 0.02 | TerrainService |
| terrain_slope_downhill_threshold | -0.02 | TerrainService |
| segment_length_meters | 100 | (reserved for future use) |
| deviation_score_max | 1000 | (reserved for future use) |
| cluster0_label | Master Style A | UI labels |
| cluster1_label | Master Style B | UI labels |

**Written by:** `DbHelper._seedConfig()` (first launch), `DbHelper.setConfig()` (admin edits)  
**Read by:** `TerrainService._loadThresholds()` → `DbHelper.getConfig()`, `ThresholdEditorScreen` → `DbHelper.getAllConfig()`

---

#### Table: `benchmark_config`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment row ID |
| terrain | TEXT | 'Plain', 'Uphill', or 'Downhill' |
| cluster | INTEGER | 0 or 1 |
| feature_name | TEXT | e.g., 'Jy_Max', 'Speed_Max' |
| min_value | REAL | Lower bound of acceptable range |
| max_value | REAL | Upper bound of acceptable range |
| updated_at | TEXT | ISO 8601 timestamp of last update |

**Row count:** 60 rows (10 features × 2 clusters × 3 terrains)  
**Written by:** `DbHelper._seedBenchmarkConfig()` (first launch), `DbHelper.updateBenchmarkRange()` (admin edits)  
**Read by:** `DeviationEngine._loadBenchmarkRanges()` → `DbHelper.getBenchmarkRanges()`

---

## 9. Key Files Quick Reference

| File Path | Role | Key Functions |
|-----------|------|---------------|
| `lib/main.dart` | Entry point, route definitions | `main()`, `KsrtcBenchmarkingApp.build()` |
| `lib/config/constants.dart` | App-wide constants | `getFeatureUnit()`, all `static const` values |
| `lib/config/benchmark_tables.dart` | Hardcoded benchmark ranges (fallback) | `getSelectedFeatures()`, `getClusterRanges()` |
| `lib/models/raw_model.dart` | Single sensor reading data class | `RawSample()` constructor, `toMap()` |
| `lib/models/segment_model.dart` | Segment metadata data class | `SegmentData()`, `SegmentData.fromMap()` |
| `lib/models/trip_model.dart` | Trip summary data class | `TripSummary()`, `TripSummary.fromMap()` |
| `lib/database/db_helper.dart` | All SQLite operations | `insertRawData()`, `insertSegment()`, `insertFeatures()`, `insertSegmentScore()`, `insertTripSummary()`, `getUserByUsername()`, `createUser()`, `getConfig()`, `setConfig()`, `getBenchmarkRanges()`, `updateBenchmarkRange()`, `updateCoachingReport()`, `getTripSummary()`, `getAllTrips()`, `getSegmentsForTrip()`, `getFeaturesForSegment()` |
| `lib/providers/auth_provider.dart` | Auth state management | `login()`, `logout()`, `checkSessionTimeout()`, `updateActivity()` |
| `lib/providers/trip_provider.dart` | Trip state management | `startTrip()`, `stopTrip()`, `_onSensorData()` |
| `lib/services/sensor_service.dart` | Real hardware sensor capture | `startCapture()`, `stopCapture()`, `requestPermissions()` |
| `lib/services/demo_sensor_service.dart` | Simulated sensor replay | `start()`, `stop()`, `_tick()` |
| `lib/services/segmentation_service.dart` | GPS distance accumulation | `addPoint()`, `reset()`, `_haversine()` |
| `lib/services/terrain_service.dart` | Terrain classification from slope | `classify()`, `_loadThresholds()`, `clearCache()` |
| `lib/services/gemini_coaching_service.dart` | Gemini API client | `getCoachingReport()`, `_buildPrompt()` |
| `lib/analytics/trip_processor.dart` | Central processing pipeline | `init()`, `addSample()`, `_closeSegment()`, `finishTrip()` |
| `lib/analytics/feature_engine.dart` | 120-feature extraction | `extract()`, `_computeTimeFeatures()`, `_computeFrequencyFeatures()` |
| `lib/analytics/fft_engine.dart` | Radix-2 FFT | `fft()`, `_bitReverse()` |
| `lib/analytics/deviation_engine.dart` | Benchmark deviation scoring | `score()`, `_loadBenchmarkRanges()`, `_computeDeviation()` |
| `lib/analytics/trip_analytics.dart` | Post-trip summary aggregation | `computeAndSave()` |
| `lib/analytics/coaching_engine.dart` | Rule-based coaching cards | `analyze()` |
| `lib/analytics/score_calculator.dart` | 0-100 score computation | `computeScore()` |
| `lib/utils/landmark_utils.dart` | NH-766 landmark lookup | `getNearestLandmark()`, `_haversine()` |
| `lib/ui/theme/app_theme.dart` | Light/dark theme definitions | `lightTheme`, `darkTheme` |
| `lib/ui/theme/app_colors.dart` | Colour constants | `primary`, `terrainPlain`, `terrainUphill`, `terrainDownhill` |
| `lib/ui/widgets/admin_guard.dart` | Admin route protection | `AdminGuard.build()` |
| `lib/ui/screens/splash_screen.dart` | 2-second splash animation | `initState()` → delayed navigation |
| `lib/ui/screens/login_screen.dart` | Authentication UI | `_handleLogin()`, `_DeveloperQuickLoginButtons` |
| `lib/ui/screens/home_screen.dart` | Driver dashboard | `_startTrip()`, session timeout timer |
| `lib/ui/screens/trip_in_progress_screen.dart` | Live recording UI | Speed display, terrain badge, Stop Trip |
| `lib/ui/screens/trip_summary_screen.dart` | Post-trip results | Score badge, Gemini coaching, worst segment |
| `lib/ui/screens/trip_history_screen.dart` | Past trip list | Trip cards → CoachingReportScreen |
| `lib/ui/screens/segment_list_screen.dart` | Segments in a trip | Terrain badges, deviation scores |
| `lib/ui/screens/segment_detail_screen.dart` | 120 features for one segment | Feature table, benchmark comparison, landmark |
| `lib/ui/screens/segment_feature_table.dart` | Feature display widget | Name, value, unit, range bar |
| `lib/ui/screens/settings_screen.dart` | Driver settings | Theme toggle, logout |
| `lib/ui/screens/admin_home_screen.dart` | Admin dashboard | All Trips, Thresholds, Drivers, Benchmarks |
| `lib/ui/screens/threshold_editor_screen.dart` | Config + benchmark editor | Tabbed: Thresholds / Benchmark Ranges |
| `lib/ui/screens/driver_management_screen.dart` | Driver CRUD | Add/delete drivers, edit bus numbers |
| `lib/ui/screens/driver_profile_screen.dart` | Driver statistics | Trip count, deviation trend, score chart |
| `lib/ui/screens/coaching_report_screen.dart` | Full coaching report | Score badge, cached AI coach, rule cards |

---

## 10. State Management

### How Provider works in this app

Flutter uses a pattern called **Provider** (from the `provider` package) to share state between widgets without passing data through constructor parameters at every level. This app uses `ChangeNotifierProvider`, which is the most common variant.

### Which providers exist

| Provider | State it holds | Screens that use it |
|----------|---------------|-------------------|
| `AuthProvider` | `currentUser` (map of user data or null), `lastActivityTime` (for session timeout) | LoginScreen, HomeScreen, TripInProgressScreen, SettingsScreen, AdminHomeScreen, AdminGuard |
| `TripProvider` | `isRecording` (bool), `tripId` (string), `segmentCount` (int), `currentSpeed` (double), `currentTerrain` (string), `gpsTrail` (list of coordinates), `segments` (list of segment data) | HomeScreen, TripInProgressScreen, TripSummaryScreen |

### How screens access a provider

There are two ways to access a provider, and they behave differently:

**`context.read<T>()`** — Gets the provider ONCE, does NOT listen for changes:
```dart
// Used when you want to CALL a method but don't need to rebuild when state changes
final authProvider = context.read<AuthProvider>();
await authProvider.login(username, password);
```
Use this in button handlers (`onPressed`) where you're triggering an action.

**`context.watch<T>()`** — Gets the provider AND rebuilds the widget when state changes:
```dart
// Used when you want to DISPLAY state that updates over time
final tripProvider = context.watch<TripProvider>();
Text('Speed: ${tripProvider.currentSpeed.toStringAsFixed(1)} km/h')
```
Use this in `build()` methods where you're displaying live data.

**The difference matters because:**
- `watch` registers a listener. Every time the provider calls `notifyListeners()`, the widget's `build()` method runs again, updating the UI.
- `read` does not register a listener. The widget does not rebuild when state changes. This is correct for button handlers because you don't want to rebuild the entire widget tree just because the user tapped a button.

### How TripProvider coordinates between services

```
User taps Start Trip
       │
       ▼
TripProvider.startTrip()
       │
       ├── Creates trip ID
       ├── Resets SegmentationService
       ├── Initialises TripProcessor
       ├── Starts DemoSensorService (or real SensorService)
       │         │
       │         ▼ (10 Hz stream of RawSample)
       │
       ├── _onSensorData(sample) ← called for every sample
       │         │
       │         ├── Updates _currentSpeed, _currentPosition, _gpsTrail
       │         ├── Calls tripProcessor.addSample(sample)
       │         │         │
       │         │         ├── Writes to raw_data table
       │         │         ├── Feeds to segmentationService.addPoint()
       │         │         └── If distance >= 100m → _closeSegment()
       │         │                   │
       │         │                   ├── Classifies terrain
       │         │                   ├── Assigns landmark
       │         │                   ├── Extracts 120 features
       │         │                   ├── Scores against clusters
       │         │                   └── Writes segment, features, scores to DB
       │         │
       │         └── Calls notifyListeners() → UI rebuilds
       │
       │
User taps Stop Trip
       │
       ▼
TripProvider.stopTrip()
       │
       ├── Cancels sensor subscription
       ├── Stops sensor service
       ├── Calls tripProcessor.finishTrip()
       │         │
       │         └── TripAnalytics.computeAndSave()
       │                   │
       │                   ├── Aggregates all segment scores
       │                   ├── Computes 0-100 score
       │                   └── Writes trip_summaries row
       │
       └── Calls notifyListeners() → UI rebuilds (shows summary)
```

### How ChangeNotifier and notifyListeners() works

`ChangeNotifier` is a Dart mixin that maintains a list of listener callbacks. When a class that extends `ChangeNotifier` (like `TripProvider`) calls `notifyListeners()`, it iterates through all registered listeners and calls each one. In Flutter's Provider system, each widget that used `context.watch<TripProvider>()` has automatically registered a listener. When that listener fires, Flutter marks the widget as "dirty" and schedules a rebuild. On the next frame, the widget's `build()` method runs again, reading the updated values from the provider.

Example from `TripProvider`:
```dart
void _onSensorData(RawSample sample) {
  _currentSpeed = sample.speed * 3.6;  // Update state
  _currentPosition = LatLng(sample.lat, sample.lon);
  _gpsTrail.add(_currentPosition!);
  _tripProcessor.addSample(sample);
  notifyListeners();  // ← This triggers rebuild of all watching widgets
}
```

In `TripInProgressScreen.build()`:
```dart
final tripProvider = context.watch<TripProvider>();
// This entire build method re-runs every time notifyListeners() fires
// (10 times per second during recording)
Text('${tripProvider.currentSpeed.toStringAsFixed(1)} km/h')
```

---

## 11. Demo Mode

### What DemoSensorService does differently

When `AppConstants.demoMode == true`, `TripProvider` creates a `DemoSensorService` instead of the real `SensorService`. The demo service does **not** access any hardware sensors or GPS. Instead, it replays a pre-programmed bus route using a software timer.

### How the 93 NH-766 waypoints are replayed

The service contains a `static const List<List<double>> _waypoints` with 93 entries. Each entry is:
```dart
[latitude, longitude, altitude_metres, terrain_type, target_speed_kmh]
```

A `Timer.periodic(Duration(milliseconds: 100))` calls `_tick()` 10 times per second. Each tick:

1. **Determines the current waypoint pair** using `_waypointIndex` (which two waypoints we're between).
2. **Computes progress** between the pair using `_segmentProgress` (0.0 = at waypoint 1, 1.0 = at waypoint 2).
3. **Advances progress** based on current speed: `progressPerTick = (currentSpeed × 0.1) / waypointDistance`.
4. When `_segmentProgress >= 1.0`, advances to the next waypoint pair.
5. When the last waypoint is reached, the route **loops back to the start**.

### How altitude is interpolated

Each of the 93 waypoints has a specific altitude value set to match real-world elevations along NH-766:

| Section | Waypoint Range | Altitude |
|---------|---------------|----------|
| Kozhikode city | 0–8 | 10–18m |
| Kozhikode to Thamarassery | 9–24 | 20–62m |
| Thamarassery Ghat (9 hairpins) | 25–53 | 80–880m |
| Lakkidi viewpoint (peak) | 54–55 | 878–880m |
| Descent into Wayanad | 56–69 | 870–700m |
| Wayanad plateau | 70–88 | 700–660m |
| Sulthan Bathery | 89–92 | 660–658m |

Between waypoints, altitude is linearly interpolated: `alt = wp1_alt + (wp2_alt - wp1_alt) × progress`.

This produces authentic terrain classification: the 80→880m rise over the ghat waypoints creates slopes of 3-7% (well above the 0.02 threshold), triggering Uphill classification. The 880→700m descent triggers Downhill.

### How IMU data is simulated

**Speed**: Smoothly approaches the waypoint's target speed with damping:
```dart
_currentSpeed += (targetSpeed - _currentSpeed) * 0.05 + noise(0.2);
_currentSpeed = _currentSpeed.clamp(2.0, 20.0); // 7–72 km/h
```

**Lateral acceleration (ax)**: Terrain-dependent:
- Plain: random noise ±0.3g
- Uphill: 0.3g bias + sinusoidal lateral force (simulating hairpin turns) + noise
- Downhill: sinusoidal ±0.3g (simulating serpentine curves) + noise

**Longitudinal acceleration (ay)**: Terrain-dependent:
- Plain: random noise ±0.2g
- Uphill: positive bias (acceleration against gravity)
- Downhill: negative bias (braking events)

**Yaw rate**: Computed from the bearing change between consecutive waypoints:
```dart
final bearing = _bearing(wp1_lat, wp1_lon, wp2_lat, wp2_lon);
yawDelta = bearing - previousBearing; // normalised to [-π, π]
yawRate = yawDelta * 2.0 + noise(0.02);
```
This produces realistic yaw rate spikes at hairpin bends and near-zero yaw on straight road sections.

**GPS jitter**: ±0.00002° (approximately 2 metres) of random noise is added to lat/lon.

### Terrain distribution in a typical demo trip

Running the demo for 3+ minutes produces approximately:
- **59% Plain** (Kozhikode city + Wayanad plateau)
- **39% Uphill** (Thamarassery Ghat ascent)
- **3% Downhill** (Lakkidi descent)

The asymmetry (39% uphill vs 3% downhill) occurs because the ghat ascent has 28 waypoints covering 800m of elevation gain (long sustained climb), while the descent section has fewer waypoints covering only 180m of drop before the Wayanad plateau begins.

---

## 12. Security Architecture

### 12.1 SHA-256 password hashing

**Where the hash is computed:** `DbHelper.hashPassword()` in `lib/database/db_helper.dart`:
```dart
import 'package:crypto/crypto.dart';
import 'dart:convert';

static String hashPassword(String password) {
  final bytes = utf8.encode(password);     // Convert string to bytes
  final digest = sha256.convert(bytes);     // Compute SHA-256
  return digest.toString();                 // Return 64-char hex string
}
```

**What is stored in the DB:** Only the hash is stored in the `password_hash` column. The plaintext password is never written to disk.

**How login comparison works:** During login, the entered password is hashed with the same function, and the resulting hash string is compared with the stored hash:
```dart
final passwordHash = DbHelper.hashPassword(password);
final user = await db.getUserByUsername(username);
if (user['password_hash'] != passwordHash) return false;
```

**Seed data example:**
- Password `'admin123'` → hash `'240be518fabd2724ddb6f04eeb9d56b5...`' (64 chars)
- This hash is computed once during `_seedUsers()` on first launch and stored.

### 12.2 AES-256 database encryption

**How sqflite_sqlcipher works:** The app uses `sqflite_sqlcipher` instead of the standard `sqflite` package. SQLCipher is a fork of SQLite that adds transparent AES-256 encryption of the entire database file. Every page of the database (including data, indexes, and schema) is encrypted before being written to disk.

**Where the encryption key comes from:** In the current implementation, `sqflite_sqlcipher` is imported but the database is opened without an explicit password parameter, which means it uses SQLCipher's default behaviour. For production hardening, a password would be passed to `openDatabase()`:
```dart
_database = await openDatabase(
  path,
  version: AppConstants.dbVersion,
  password: 'encryption_key_here', // Production: use secure key storage
  onCreate: _onCreate,
  onUpgrade: _onUpgrade,
);
```

**What it protects:** If someone extracts the database file from the device, they cannot read any data (trips, sensor readings, user credentials, coaching reports) without the encryption key. The file appears as random bytes to any SQLite reader without SQLCipher.

### 12.3 Session timeout

**Which timer is used:** `AuthProvider` tracks `_lastActivityTime` as a `DateTime`.

**Where it is started:** `_lastActivityTime` is set to `DateTime.now()` in `login()`.

**Periodic checks:**
- `HomeScreen`: `Timer.periodic(Duration(minutes: 5))` calls `authProvider.checkSessionTimeout()`.
- `TripInProgressScreen`: `Timer.periodic(Duration(minutes: 1))` calls `authProvider.updateActivity()`.

**What happens when timeout fires:**
```dart
bool checkSessionTimeout() {
  if (!isLoggedIn) return false;
  final now = DateTime.now();
  if (now.difference(_lastActivityTime!).inMinutes >= 30) {
    logout();
    return true;  // Caller should navigate to /login
  }
  return false;
}
```
The calling screen checks the return value and, if `true`, navigates to `/login` with stack clearing.

**How trip screen keeps session alive:** During active recording, `TripInProgressScreen` calls `updateActivity()` every 60 seconds:
```dart
void updateActivity() {
  _lastActivityTime = DateTime.now();
}
```
This prevents timeout during a 2-hour bus trip.

### 12.4 AdminGuard widget

**How it works:** `AdminGuard` is a widget that wraps admin-only screens. It is used in the route definition in `main.dart`:
```dart
'/admin': (context) => AdminGuard(child: AdminHomeScreen()),
```

**What it checks** in its `build()` method:
1. First checks session timeout: `authProvider.checkSessionTimeout()`. If expired → navigates to `/login`.
2. Then checks `authProvider.isLoggedIn`. If not logged in → navigates to `/login`.
3. Then checks `authProvider.isAdmin`. If not admin → navigates to `/home` (driver home, not admin).
4. If all checks pass → renders the `child` widget normally.

**What it does if the check fails:** It calls `Navigator.pushNamedAndRemoveUntil(context, targetRoute, (route) => false)` to redirect, and returns a loading spinner as a placeholder widget while the navigation happens.

---

## 13. How Flutter UI Calls Functions — A Beginner's Guide

### 13.1 How a button calls a function

Let's trace the **Start Trip** button in `home_screen.dart`:

```dart
ElevatedButton(
  onPressed: () async {
    final tripProvider = context.read<TripProvider>();
    await tripProvider.startTrip();
    if (mounted) {
      Navigator.pushNamed(context, '/trip-in-progress');
    }
  },
  child: Text('Start Trip'),
)
```

Breaking this down:

1. **`ElevatedButton`** is a Flutter widget that renders a material-design raised button.
2. **`onPressed:`** is a parameter that accepts a function. This function runs when the user taps the button.
3. **`() async { ... }`** is an anonymous async function (a closure). The `async` keyword means it can use `await` inside.
4. **`context.read<TripProvider>()`** gets the `TripProvider` instance without subscribing to updates (because we're in a button handler, not in `build()`).
5. **`await tripProvider.startTrip()`** calls the `startTrip()` method on TripProvider and waits for it to complete before continuing. During this await, the UI remains responsive.
6. **`if (mounted)`** checks that the widget is still in the widget tree (hasn't been disposed during the async wait).
7. **`Navigator.pushNamed(context, '/trip-in-progress')`** navigates to the trip recording screen.

### 13.2 How to find which file a function lives in

Dart uses an `import` system similar to Python or Java. Let's look at `home_screen.dart`:

```dart
import 'package:flutter/material.dart';           // Flutter framework widgets
import 'package:provider/provider.dart';           // Provider state management
import '../../providers/trip_provider.dart';        // TripProvider class
import '../../providers/auth_provider.dart';        // AuthProvider class
import '../../config/constants.dart';               // AppConstants
```

**How to trace a function:**

1. You see `tripProvider.startTrip()` in the code.
2. `tripProvider` is typed as `TripProvider` (from `context.read<TripProvider>()`).
3. `TripProvider` is imported from `'../../providers/trip_provider.dart'`.
4. The `../../` means "go up two directories from the current file's location":
   - Current file: `lib/ui/screens/home_screen.dart`
   - `../` → `lib/ui/`
   - `../../` → `lib/`
   - `../../providers/trip_provider.dart` → `lib/providers/trip_provider.dart`
5. Open that file and search for `Future<void> startTrip()` — that's the function definition.

**Import path conventions in this project:**
- `'package:...'` — external packages installed via `pubspec.yaml`
- `'../../...'` — relative paths within the project (count the `../` to navigate directories)
- `'dart:...'` — Dart standard library (e.g., `dart:async`, `dart:math`, `dart:convert`)

### 13.3 How Provider connects UI to logic

Let's trace the complete flow of **TripProvider** from Start Trip through live updates:

**Step 1: The screen gets a reference to the provider**

In `trip_in_progress_screen.dart`, inside the `build()` method:
```dart
final tripProvider = context.watch<TripProvider>();
```

`context.watch<TripProvider>()` does two things:
1. Returns the `TripProvider` instance (the same one created in `main.dart`'s `MultiProvider`).
2. Registers this widget as a listener — whenever `TripProvider` calls `notifyListeners()`, this widget's `build()` method will run again.

Compare with:
```dart
final tripProvider = context.read<TripProvider>();
```
`context.read<TripProvider>()` only does thing #1 — returns the instance. It does NOT register a listener. The widget will NOT rebuild when state changes. This is used in `onPressed` handlers where rebuilding is unnecessary.

**Step 2: Start Trip calls the provider method**

```dart
// In home_screen.dart (using read, not watch — we're in a button handler)
final tripProvider = context.read<TripProvider>();
await tripProvider.startTrip();
```

**Step 3: Inside TripProvider.startTrip()**

```dart
Future<void> startTrip() async {
  _tripId = DateTime.now().millisecondsSinceEpoch.toString();
  _isRecording = true;
  _segmentCount = 0;
  notifyListeners(); // ← Widgets watching TripProvider rebuild NOW

  _segmentationService.reset();
  await _tripProcessor.init(_tripId!);

  final demoService = _sensorService as DemoSensorService;
  _sensorSubscription = demoService.start().listen(_onSensorData);
  // Now _onSensorData will be called 10 times per second
}
```

**Step 4: Each sensor sample triggers a state update**

```dart
void _onSensorData(RawSample sample) {
  _currentSpeed = sample.speed * 3.6;           // State change
  _currentPosition = LatLng(sample.lat, sample.lon); // State change
  _gpsTrail.add(_currentPosition!);             // State change
  _tripProcessor.addSample(sample);             // Processing
  notifyListeners(); // ← All watching widgets rebuild AGAIN
}
```

**Step 5: The UI reads the updated state and displays it**

```dart
// In trip_in_progress_screen.dart build()
final tripProvider = context.watch<TripProvider>();

Text('${tripProvider.currentSpeed.toStringAsFixed(1)} km/h')
// This Text widget now shows the latest speed value
// It rebuilds 10 times per second because notifyListeners() fires at 10 Hz
```

**The full cycle repeats:** sensor emits sample → `_onSensorData` updates state → `notifyListeners()` fires → all watching widgets rebuild → UI shows new data.

### 13.4 How navigation works

Flutter uses a **Navigator** with a stack of screens (called "routes"). Named routes are defined in `main.dart`:

```dart
MaterialApp(
  initialRoute: '/',  // The first screen shown
  routes: {
    '/': (context) => SplashScreen(),
    '/login': (context) => LoginScreen(),
    '/home': (context) => HomeScreen(),
    '/admin': (context) => AdminGuard(child: AdminHomeScreen()),
    '/settings': (context) => SettingsScreen(),
    '/trip-history': (context) => TripHistoryScreen(),
    '/coaching-report': (context) => CoachingReportScreen(...),
  },
)
```

**Common navigation calls used in this codebase:**

**Push (add to stack):** Opens a new screen on top of the current one. The back button returns to the previous screen.
```dart
Navigator.pushNamed(context, '/trip-in-progress');
```

**Push and remove all (clear stack):** Opens a new screen and removes ALL previous screens from the stack. The back button exits the app (no previous screen to return to). Used after login and logout.
```dart
Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
```

**Push with arguments (for screens that need data):** Some screens need parameters. This is done by creating the screen widget directly instead of using named routes:
```dart
Navigator.push(context, MaterialPageRoute(
  builder: (context) => CoachingReportScreen(tripId: trip.tripId),
));
```

**Pop (go back):** Returns to the previous screen on the stack. Equivalent to pressing the back button.
```dart
Navigator.pop(context);
```

### 13.5 How async/await works in this codebase

Let's trace the **Gemini API call** in `gemini_coaching_service.dart`:

```dart
Future<String?> getCoachingReport({
  required int score,
  required int totalSegments,
  // ... more parameters
}) async {
  try {
    final prompt = _buildPrompt(score, totalSegments, ...);

    final response = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/...'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({...}),
    ).timeout(Duration(seconds: 30));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final text = json['candidates'][0]['content']['parts'][0]['text'];
      return text;
    }
    return null;
  } catch (e) {
    return null;
  }
}
```

**Breaking this down for someone new to Dart:**

1. **`Future<String?>`** — This function returns a `Future`, which is Dart's equivalent of a JavaScript `Promise` or Python `asyncio.Task`. The `String?` means the eventual value will be either a `String` or `null`. The function does not return immediately — it returns a placeholder that will be filled later.

2. **`async`** — This keyword on the function declaration enables the use of `await` inside the function body. Without `async`, you cannot use `await`.

3. **`await http.post(...)`** — This pauses execution of THIS function until the HTTP request completes. While paused:
   - The UI continues running normally (animations, scrolling, etc.)
   - Other code can execute
   - The sensor timer continues firing
   - The function "resumes" from this line when the response arrives

4. **`.timeout(Duration(seconds: 30))`** — If the HTTP request hasn't completed after 30 seconds, it throws a `TimeoutException`. This is caught by the `catch (e)` block, which returns `null`.

5. **Where the caller uses `await`:** In `trip_summary_screen.dart`:
   ```dart
   void _fetchCoaching() async {
     setState(() { _isLoadingCoaching = true; });

     final report = await GeminiCoachingService().getCoachingReport(...);
     // Execution pauses here while the API call happens
     // A shimmer animation shows on screen during this pause

     if (report != null) {
       await DbHelper.instance.updateCoachingReport(tripId, report);
     }

     setState(() {
       _coachingReport = report;
       _isLoadingCoaching = false;
       // This setState causes the widget to rebuild,
       // now showing the report instead of the shimmer
     });
   }
   ```

### 13.6 How a screen receives data

Let's trace **`CoachingReportScreen`** which receives a `tripId` parameter:

**Step 1: The screen is opened with a parameter**

In `trip_history_screen.dart`:
```dart
Navigator.push(context, MaterialPageRoute(
  builder: (context) => CoachingReportScreen(tripId: trip.tripId),
));
```

**Step 2: The screen declares the parameter in its constructor**

In `coaching_report_screen.dart`:
```dart
class CoachingReportScreen extends StatefulWidget {
  final String tripId;  // Declared as a field on the widget

  const CoachingReportScreen({Key? key, required this.tripId}) : super(key: key);
  // 'required' means the caller MUST provide this parameter

  @override
  State<CoachingReportScreen> createState() => _CoachingReportScreenState();
}
```

**Step 3: The screen uses the parameter in initState to fetch data**

```dart
class _CoachingReportScreenState extends State<CoachingReportScreen> {
  TripSummary? _summary;
  List<SegmentDetail> _segments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();  // Called once when the screen first appears
  }

  Future<void> _loadData() async {
    final db = DbHelper.instance;

    // widget.tripId accesses the tripId parameter from the parent widget
    final summary = await db.getTripSummary(widget.tripId);
    final segments = await db.getSegmentsForTrip(widget.tripId);

    setState(() {
      _summary = summary;
      _segments = segments;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    // Use _summary and _segments to build the UI
    return Column(children: [
      Text('Score: ${ScoreCalculator.computeScore(_summary!.overallAvgDeviation)}'),
      Text('Coaching: ${_summary!.coachingReport ?? "No report"}'),
      // ... more widgets
    ]);
  }
}
```

**Key concepts for someone new to Flutter:**

- **`StatefulWidget`** vs **`StatelessWidget`**: A StatefulWidget can change its appearance after being created (e.g., loading data from DB and then displaying it). A StatelessWidget's appearance never changes after creation.
- **`State`** class: Contains mutable fields (like `_summary`, `_isLoading`) and the `build()` method.
- **`widget.tripId`**: Inside the `State` class, `widget` refers to the parent `StatefulWidget` instance. This is how the State accesses the constructor parameters.
- **`initState()`**: Called exactly once when the widget is first inserted into the widget tree. This is where you start async loading operations.
- **`setState(() { ... })`**: Updates mutable fields AND tells Flutter to call `build()` again. Without `setState`, changing a field has no effect on the UI. This is different from `notifyListeners()` in Provider — `setState` is local to one widget, while `notifyListeners` broadcasts to all watching widgets.

---

*This document was generated on March 10, 2026 and reflects the codebase at version 2.0 with all 8 feature phases implemented.*