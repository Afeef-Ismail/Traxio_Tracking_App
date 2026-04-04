# KSRTC Master Driver Benchmarking System — Codebase Guide

> **Current version:** v5 (DB schema v8)  
> **Last updated:** 2026-04-04  
> **Platform:** Flutter / Android  
> **Branch:** main

---

## Section 1 — Project Overview

The KSRTC Master Driver Benchmarking System is a Flutter Android app that records bus trips on the **NH-766 Kozhikode–Sulthan Bathery ghat route**, segments them into 100 m intervals, extracts 120 signal features per segment, and scores driver behaviour against admin-configured master driver cluster benchmarks.

**Key capabilities:**

| Capability | Detail |
|---|---|
| Trip recording | GPS + IMU at 10 Hz, 100 m segments |
| Feature extraction | 120 features (8 attributes × 15: 11 time-domain + 4 frequency-domain) |
| Dynamic cluster scoring | Admin creates N clusters via UI; scored at runtime against only active clusters |
| Multi-vehicle support | Clusters carry a vehicle type; driver selects vehicle type before trip |
| Sensor calibration | Angle-aware gravity compensation at any phone mounting angle |
| AI coaching | Grok (Groq API, llama-3.3-70b-versatile) generates post-trip coaching report in English, Malayalam, or Hindi |
| Localisation | English, Malayalam, Hindi via ARB files + LanguageProvider |
| Demo mode | Fully simulated sensor data for emulator/UI testing |
| Admin dashboard | Cluster management, driver management, threshold tuning, data collection mode, trip export |

---

## Section 2 — Directory Structure

```
lib/
├── main.dart                          App entry point; loads .env, LanguageProvider, routes
│
├── config/
│   ├── constants.dart                 App-wide constants (DB version, sensor rates, terrain labels, feature units)
│   └── benchmark_tables.dart          Hardcoded fallback benchmark ranges (used only when no active DB clusters)
│
├── models/
│   ├── raw_model.dart                 RawSample — single 10 Hz sensor reading
│   ├── segment_model.dart             Segment — 100 m segment metadata
│   ├── feature_result.dart            FeatureResult — one named feature value for a segment
│   ├── trip_model.dart                TripSummary, SegmentScore, SegmentDetail — trip aggregate data
│   └── cluster_model.dart             ClusterDefinition, ClusterFeatureRange — dynamic cluster data
│
├── database/
│   └── db_helper.dart                 Singleton SQLite helper; all DB operations; schema v8
│
├── providers/
│   ├── auth_provider.dart             Login/logout, session timeout, role checking
│   ├── language_provider.dart         Locale state; persists to SharedPreferences
│   └── trip_provider.dart             Central trip state machine; wires sensor→segment→process→analytics
│
├── services/
│   ├── sensor_service.dart            Real accelerometer + gyroscope stream at 10 Hz
│   ├── demo_sensor_service.dart       Simulated sensor stream (demoMode = true)
│   ├── calibration_service.dart       Stores/loads gravity offsets; runs calibration stream
│   ├── segmentation_service.dart      Accumulates GPS fixes; emits SegmentData every 100 m
│   ├── terrain_service.dart           Classifies Plain/Uphill/Downhill from slope
│   ├── trip_processor.dart            Orchestrates feature extraction + deviation scoring per segment
│   ├── csv_export_service.dart        Exports benchmark trips to CSV (Downloads folder)
│   └── grok_coaching_service.dart     Calls Groq API (llama-3.3-70b-versatile) for AI coaching report
│
├── analytics/
│   ├── feature_engine.dart            11 time-domain features per signal array
│   ├── fft_engine.dart                4 frequency-domain features per signal array
│   ├── smoothing.dart                 3-point moving average per attribute array
│   ├── deviation_engine.dart          Per-feature and per-cluster deviation scoring (static + dynamic)
│   ├── trip_analytics.dart            Aggregates segment scores into TripSummary
│   ├── coaching_engine.dart           Rule-based CoachingInsight generation
│   └── score_calculator.dart          Maps overallAvgDeviation → 0–100 trip score
│
├── utils/
│   ├── math_utils.dart                Derivative, zero-crossing, statistical helpers
│   ├── haversine.dart                 GPS distance calculation
│   ├── landmark_utils.dart            Nearest NH-766 landmark lookup by GPS coordinates
│   └── feature_display_utils.dart     Converts feature keys (Speed_Max) → human labels (Speed — Maximum)
│
└── ui/
    ├── theme/
    │   ├── app_colors.dart            Centralised colour palette (light + dark)
    │   └── app_theme.dart             ThemeData builder; uses Noto Sans for multilingual support
    │
    ├── widgets/
    │   ├── admin_guard.dart           Route guard — redirects non-admin to home
    │   ├── big_speed_display.dart     Large speed readout widget
    │   ├── buttons.dart               PrimaryButton, SecondaryButton (reusable)
    │   ├── map_widget.dart            flutter_map tile widget with GPS trail and segment markers
    │   ├── segment_feature_table.dart  Feature value table in segment detail view
    │   ├── stat_card.dart             Small stat display card
    │   ├── summary_card.dart          Deviation summary card with icon + accent colour
    │   ├── terrain_badge.dart         Coloured terrain label chip
    │   └── trip_score_chart.dart      Score bar/chart widget
    │
    └── screens/
        ├── splash_screen.dart         Splash → auto-navigate based on auth state
        ├── login_screen.dart          Username/password login; dev quick-login buttons
        ├── home_screen.dart           Driver home; tab bar (Benchmark | Data Collection); calibration status; vehicle selection
        ├── trip_in_progress_screen.dart  Live trip screen; speed, terrain, elapsed, stop button
        ├── trip_summary_screen.dart   Post-trip summary; dynamic cluster cards; Grok AI report
        ├── trip_history_screen.dart   Driver's past trip list
        ├── segment_list_screen.dart   All segments for a trip
        ├── segment_detail_screen.dart  Per-segment features, deviation table, map pin
        ├── settings_screen.dart       Slope threshold, sensor calibration link, dark mode, language, logout
        ├── driver_profile_screen.dart  Driver name and bus number setup
        ├── calibration_screen.dart    3-step guided sensor calibration UI (stability ring → recording → result)
        ├── data_collection_screen.dart  Driver-side data collection trip launcher
        ├── admin_home_screen.dart     Admin dashboard grid: Threshold, Drivers, Data Collection, Clusters
        ├── admin_collection_screen.dart  Admin view of data collection trips
        ├── cluster_management_screen.dart  CRUD for clusters; 3-step wizard; feature search bottom sheet
        ├── benchmark_editor_screen.dart  Legacy benchmark range editor (file kept; not in admin grid)
        ├── threshold_editor_screen.dart  Terrain slope threshold editor
        ├── driver_management_screen.dart  Add/edit/delete driver accounts
        └── coaching_report_screen.dart   Full-screen AI coaching report viewer
```

---

## Section 3 — App Startup Flow

```
main()
  ├── WidgetsFlutterBinding.ensureInitialized()
  ├── dotenv.load('.env')            ← loads GROK_API_KEY
  ├── LanguageProvider.loadSavedLanguage()   ← reads SharedPreferences 'language_code'
  ├── SystemChrome: portrait lock + edge-to-edge
  └── runApp(KsrtcApp)
        ├── MultiProvider [AuthProvider, TripProvider, LanguageProvider]
        ├── MaterialApp with AppLocalizations delegates (en, ml, hi)
        └── SplashScreen → /login or /home or /admin
```

---

## Section 4 — Trip Recording Pipeline

```
Driver taps "Start Trip"
  ├── Location service check (dialog + redirect to settings if off)
  ├── Calibration check — if not calibrated in real mode:
  │     Navigate to CalibrationScreen (showContinueButton: true)
  │     CalibrationService.startCalibration() → Stream<CalibrationProgress>
  │       Phase 1: waitingForStillness
  │         2-second sliding window, stdDev(ax/ay/az) < 0.05 g for 5 consecutive stable windows
  │       Phase 2: recording (5 s, 50 samples)
  │         Averages ax/ay/az/yaw as static gravity offsets
  │       Phase 3: complete → saveOffsets() persisted in SharedPreferences
  ├── Vehicle type selection:
  │     DB.getActiveVehicleTypes() → distinct vehicle_type from active clusters
  │     if multiple types → "What are you driving?" dialog (large icon buttons)
  │     if single type → auto-select; if none → vehicleType = ''
  └── TripProvider.startTrip(vehicleType)
        ├── TripProcessor.loadBenchmarks(vehicleType)
        │     Active clusters from DB filtered by vehicleType
        │     Cluster features cached per (clusterId, terrain)
        ├── SensorService (or DemoSensorService) starts at 10 Hz
        │     Each raw sample: CalibrationService offsets subtracted from ax/ay/az/yaw
        └── SegmentationService accumulates GPS → emits SegmentData at 100 m

Per 100 m segment — TripProcessor.processSegment(segData):
  1. Extract 8 attribute arrays: Speed, ay, ax, YR, Jx, Jy, VV, R
  2. 3-point smoothing (Smoothing.applySmoothing)
  3. Terrain classification from altitude slope (TerrainService)
  4. Validity check (min 5 samples, non-zero signals)
  5. 15 features × 8 attributes = 120 features (FeatureEngine + FftEngine)
  6. Persist segment + features to DB
  7a. Dynamic scoring (active clusters loaded):
      DeviationEngine.computeSegmentDeviationDynamic()
        Per cluster: sum |feature − range| for each feature outside [min, max]
        Best cluster = min total deviation → matchedClusterName stored as TEXT
  7b. Fallback scoring (no active clusters):
      DeviationEngine.computeSegmentDeviation() vs BenchmarkTables
  8. Persist SegmentScore (cluster0Dev, cluster1Dev, matchedCluster int, matchedClusterName)

Trip end — TripProvider.stopTrip():
  TripAnalytics.generateSummary(tripId, vehicleType)
    Aggregates cluster match counts, per-terrain avg deviations → TripSummary
  Navigate to TripSummaryScreen
```

---

## Section 5 — AI Coaching Flow

**Service:** `lib/services/grok_coaching_service.dart`  
**Provider:** Groq (formerly Gemini — fully replaced)  
**Endpoint:** `https://api.groq.com/openai/v1/chat/completions`  
**Model:** `llama-3.3-70b-versatile`  
**API Key:** `GROK_API_KEY` in `.env` (git-ignored), loaded via `flutter_dotenv`

```
TripSummaryScreen._loadCoaching()
  ├── DB cache check: if coaching_report non-empty, return immediately (no API call)
  └── GrokCoachingService.getCoachingReport(summary, segments)
        ├── Read language_code from SharedPreferences
        ├── Language instruction prepended to prompt:
        │     en → "Respond in English."
        │     ml → "Respond entirely in Malayalam (മലയാളം)..."
        │     hi → "Respond entirely in Hindi (हिन्दी)..."
        ├── Structured prompt: score, terrain breakdown, cluster match %, worst segment landmark
        ├── POST to Groq API with Bearer token (30 s timeout)
        ├── Parse choices[0].message.content
        ├── Cache in DB: trip_summaries.coaching_report
        └── Return SUMMARY / STRENGTHS / IMPROVEMENTS plain text
```

---

## Section 6 — Dynamic Cluster System

### Data model

| Entity | Table | Key fields |
|---|---|---|
| ClusterDefinition | `clusters` | id, name, description, route, vehicle_type, is_active, deleted_at |
| ClusterFeatureRange | `cluster_features` | id, cluster_id, terrain, feature_name, min_value, max_value |

### Admin workflow

1. Admin opens **Clusters** from admin dashboard
2. Taps FAB → 3-step wizard:
   - **Step 1:** Name, description, route, vehicle type (large icon buttons)
   - **Step 2:** Per-terrain feature ranges (expandable terrain sections; bottom sheet search across all 120 features)
   - **Step 3:** Review summary → Save
3. Cluster cards: toggle active/inactive, edit, soft-delete (`deleted_at` timestamp)
4. Default clusters seeded on v7→v8 migration: "Master Driver A" (CEB data) and "Master Driver B" (DEB data)

### Runtime scoring

```
loadBenchmarks(vehicleType):
  active = DB.getActiveClusters()          -- WHERE is_active=1 AND deleted_at IS NULL
  filtered = active where vehicleType matches (or cluster.vehicleType is empty)
  fallback: use all active if filtered is empty

computeSegmentDeviationDynamic(featureValues, clusters, featuresCache, terrain):
  for each cluster: total = sum(max(0, feature - max_range) + max(0, min_range - feature))
  bestClusterName = cluster with minimum total
  cluster0/cluster1 = first two by ID (backward-compat storage columns)
  matchedClusterName = bestClusterName TEXT (correct for any N)
```

### Trip summary display

`_buildClusterCards()` in `trip_summary_screen.dart`:
- Loads active clusters from DB filtered by `summary.vehicleType`
- Queries `matched_cluster_name` counts via `DbHelper.getClusterMatchCounts(tripId)`
- 1 cluster → full-width card; 2+ → 2-column `Wrap`
- Falls back to stored cluster0/cluster1 percentage if no active clusters found

---

## Section 7 — Sensor Calibration

**Service:** `lib/services/calibration_service.dart` (singleton)  
**Storage:** SharedPreferences — `cal_ax_offset`, `cal_ay_offset`, `cal_az_offset`, `cal_yaw_offset`, `cal_is_calibrated`, `cal_date`

### Process

```
Phase 1 — waitingForStillness:
  Reads accelerometer at 10 Hz in a 2-second sliding window (20 samples)
  Stable = stdDev(ax) < 0.05 AND stdDev(ay) < 0.05 AND stdDev(az) < 0.05
  Requires 5 consecutive stable windows before advancing

Phase 2 — recording (5 s, 50 samples):
  Averages all ax/ay/az/yaw readings = static gravity vector at current angle

Phase 3 — complete:
  saveOffsets() → SharedPreferences
  pitchDegrees = asin(ayOffset) in degrees   (forward/backward tilt)
  rollDegrees  = asin(axOffset) in degrees   (sideways tilt)
```

### Applied calibration

Every raw sensor reading: `calibrated_ax = raw_ax − axOffset` (same for ay, az, yaw). This ensures features measure only driving-induced forces regardless of phone mount angle.

### UI

| Location | Behaviour |
|---|---|
| Home screen | Green ✓ (calibrated) or amber ⚠ (not calibrated) — tap to open CalibrationScreen |
| Pre-trip (real mode) | Forced calibration if `isCalibrated == false` |
| Settings → Sensor | "Calibrate Sensors" button (hidden in demo mode) |

---

## Section 8 — Multi-Vehicle Support

```
ClusterDefinition.vehicleType: "Bus" | "Minibus" | "Car" | "" (any)

Before trip:
  activeTypes = DB.getActiveVehicleTypes()
  > 1 type  → dialog: "What are you driving?" (large ElevatedButton.icon per type)
  = 1 type  → auto-selected
  = 0 types → vehicleType = '' → scores all active clusters

TripProvider.startTrip(vehicleType):
  TripProcessor.loadBenchmarks(vehicleType)
    → filters active clusters to vehicleType match
    → fallback: all active if none match

TripSummary.vehicleType persisted in trip_summaries.vehicle_type
TripSummaryScreen: shows vehicle type badge; filters cluster cards to matching type
CSV export: includes vehicle_type column
Admin All Trips view: shows vehicle type badge per trip
```

---

## Section 9 — Localisation

**Languages:** English (`en`), Malayalam (`ml`), Hindi (`hi`)  
**ARB files:** `lib/l10n/app_en.arb`, `lib/l10n/app_ml.arb`, `lib/l10n/app_hi.arb`  
**Generated class:** `flutter_gen/gen_l10n/app_localizations.dart` — do not edit manually

### LanguageProvider

```dart
class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');
  void setLanguage(String code)          // persists 'language_code' to SharedPreferences
  Future<void> loadSavedLanguage()       // called in main() before runApp
}
```

Selected language is forwarded to `GrokCoachingService` which prepends a language instruction to the AI prompt — the coaching report arrives in the driver's chosen language.

### Long-string handling

Malayalam strings are significantly longer than English. Fixes applied:
- `FittedBox(fit: BoxFit.scaleDown)` wraps tab label text in the benchmark tab bar
- App title wrapped in `Flexible` + `overflow: TextOverflow.ellipsis` to avoid clash with header icon buttons

### Font

`Noto Sans` via `google_fonts` — full Unicode coverage for Devanagari (Hindi) and Malayalam scripts.

---

## Section 10 — State Management

Three `ChangeNotifier` providers at app root (`MultiProvider` in `main.dart`):

| Provider | Responsibility |
|---|---|
| `AuthProvider` | Login/logout, role (admin/driver), session timeout (60 min inactivity check every 5 min) |
| `TripProvider` | Trip state machine: idle → calibrating → recording → processing → complete; exposes currentSpeed, currentTerrain, gpsTrail, segmentsCompleted |
| `LanguageProvider` | `Locale` state; persisted in SharedPreferences |

- Reactive rebuilds: `context.watch<T>()`
- One-shot reads: `context.read<T>()`

---

## Section 11 — Database Reference

**Engine:** SQLite via `sqflite_sqlcipher` (AES encrypted at rest)  
**DB file:** `ksrtc_benchmarking.db`  
**Schema version:** 8 (migrated from v7 in latest release)

### `raw_data`
10 Hz sensor samples during a trip.
`trip_id, timestamp, lat, lon, speed, ax, ay, yaw_rate, altitude`

### `segments`
One row per 100 m segment.
`trip_id, mode, segment_index, terrain, distance, start/end lat/lon/altitude, is_valid, nearest_landmark`

### `segment_features`
120 named feature values per valid segment.
`segment_id, feature_name, value`

### `segment_scores`
Deviation scoring results per valid benchmark segment.

| Column | Type | Notes |
|---|---|---|
| trip_id | TEXT | |
| segment_id | INTEGER | |
| cluster0_deviation | REAL | deviation vs 1st active cluster by ID (backward compat) |
| cluster1_deviation | REAL | deviation vs 2nd active cluster by ID (backward compat) |
| matched_cluster | INTEGER | 0 or 1 (backward compat) |
| **matched_cluster_name** | **TEXT** | **actual best cluster name — correct for any N clusters** |
| is_valid | INTEGER | |
| csv_row_number | INTEGER | |

### `trip_summaries`
One row per completed benchmark trip.

| Column | Notes |
|---|---|
| trip_id TEXT PK | |
| driver_id TEXT | |
| **vehicle_type TEXT** | **driver's selected vehicle type (added v8)** |
| start_time, end_time INTEGER | epoch ms |
| total/valid_segments INTEGER | |
| cluster0/1_matches INTEGER | match counts (backward compat) |
| cluster0/1_percentage REAL | |
| plain/uphill/downhill_segments INTEGER | |
| avg_deviation_plain/uphill/downhill REAL | |
| overall_avg_deviation REAL | |
| coaching_report TEXT | cached Grok AI response |

### `clusters` (added v8)
Admin-managed master driver definitions.

| Column | Notes |
|---|---|
| id INTEGER PK | |
| name TEXT | custom display name |
| vehicle_type TEXT | matched against driver selection |
| is_active INTEGER | 0/1; inactive clusters excluded from scoring |
| deleted_at TEXT | NULL = not deleted (soft delete pattern) |

### `cluster_features` (added v8)
Feature ranges per cluster per terrain.

`cluster_id, terrain ("Plain"|"Uphill"|"Downhill"), feature_name, min_value, max_value`

### `benchmark_config` (legacy)
Original 2-cluster hardcoded ranges. Seeded into `clusters` on migration. Still editable via `BenchmarkEditorScreen` (not in admin grid). Used as fallback when no active clusters exist.

### `drivers`
`id, name, bus_number, role, password_hash (SHA-256)`

---

## Section 12 — Security

| Item | Status |
|---|---|
| API key location | `.env` file only (git-ignored) |
| Hardcoded keys in source | None — `geminiApiKey` removed; `gemini_coaching_service.dart` deleted |
| `.env` in `.gitignore` | ✓ |
| DB encryption | `sqflite_sqlcipher` AES |
| Password storage | SHA-256 hash |

### `.env` format

```
GROK_API_KEY=your-groq-api-key-here
```

Loaded at startup:
```dart
await dotenv.load(fileName: '.env');
// Access: dotenv.env['GROK_API_KEY'] ?? ''
```

---

## Section 13 — Key Files Quick Reference

| File | Purpose |
|---|---|
| `lib/main.dart` | Entry; dotenv load, providers, routes |
| `lib/config/constants.dart` | All non-secret constants; feature units map; DB version = 8 |
| `lib/config/benchmark_tables.dart` | Hardcoded fallback 2-cluster ranges |
| `lib/database/db_helper.dart` | All CRUD; migrations v1→v8; cluster CRUD; `getClusterMatchCounts()` |
| `lib/models/cluster_model.dart` | `ClusterDefinition`, `ClusterFeatureRange` |
| `lib/models/trip_model.dart` | `TripSummary` (+ vehicleType), `SegmentScore` (+ matchedClusterName) |
| `lib/providers/trip_provider.dart` | State machine; `startTrip(vehicleType)`, `getActiveVehicleTypes()` |
| `lib/providers/language_provider.dart` | Locale + SharedPreferences persistence |
| `lib/services/calibration_service.dart` | Gravity offset capture; `startCalibration()` stream; SharedPreferences |
| `lib/services/trip_processor.dart` | Per-segment pipeline; dynamic cluster load + score |
| `lib/services/grok_coaching_service.dart` | Groq API client; multilingual prompt; DB cache |
| `lib/analytics/deviation_engine.dart` | `computeSegmentDeviationDynamic()` for N clusters |
| `lib/analytics/trip_analytics.dart` | `generateSummary(tripId, vehicleType)` |
| `lib/utils/feature_display_utils.dart` | `getDisplayName("Speed_Max")` → `"Speed — Maximum"` |
| `lib/ui/screens/home_screen.dart` | Calibration status indicator; vehicle type selection |
| `lib/ui/screens/calibration_screen.dart` | 3-step calibration UI with animated ring |
| `lib/ui/screens/cluster_management_screen.dart` | Cluster CRUD wizard; `vehicleTypeIcon()` |
| `lib/ui/screens/trip_summary_screen.dart` | Dynamic cluster cards via `_buildClusterCards()` |
| `lib/ui/screens/admin_home_screen.dart` | Admin grid (4 cards: Threshold, Drivers, Data Collection, Clusters) |
| `lib/l10n/app_en.arb` | English strings |
| `lib/l10n/app_ml.arb` | Malayalam strings |
| `lib/l10n/app_hi.arb` | Hindi strings |
| `.env` | `GROK_API_KEY=...` (git-ignored, never committed) |

---

*Generated 2026-04-04 — reflects codebase at v5 / DB schema v8.*
