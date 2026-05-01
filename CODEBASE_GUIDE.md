# Traxio Driver Benchmarking System — Codebase Guide

Current state: April 2026 (DB schema v9)
Platform: Flutter (Android-first)

## 1) Directory Structure

```text
lib/
├── main.dart
├── analytics/
│   ├── coaching_engine.dart
│   ├── deviation_engine.dart
│   ├── feature_engine.dart
│   ├── fft_engine.dart
│   ├── score_calculator.dart
│   ├── smoothing.dart
│   └── trip_analytics.dart
├── config/
│   ├── benchmark_tables.dart
│   └── constants.dart
├── database/
│   └── db_helper.dart
├── l10n/
│   ├── app_en.arb
│   ├── app_hi.arb
│   └── app_ml.arb
├── models/
│   ├── cluster_model.dart
│   ├── feature_result.dart
│   ├── raw_model.dart
│   ├── segment_model.dart
│   └── trip_model.dart
├── providers/
│   ├── auth_provider.dart
│   ├── language_provider.dart
│   └── trip_provider.dart
├── services/
│   ├── calibration_service.dart
│   ├── csv_export_service.dart
│   ├── demo_sensor_service.dart
│   ├── groq_coaching_service.dart
│   ├── segmentation_service.dart
│   ├── sensor_service.dart
│   ├── terrain_service.dart
│   └── trip_processor.dart
├── ui/
│   ├── screens/
│   │   ├── admin_collection_screen.dart
│   │   ├── admin_home_screen.dart
│   │   ├── benchmark_editor_screen.dart
│   │   ├── calibration_screen.dart
│   │   ├── cluster_management_screen.dart
│   │   ├── coaching_report_screen.dart
│   │   ├── data_collection_screen.dart
│   │   ├── data_viewer_screen.dart
│   │   ├── driver_management_screen.dart
│   │   ├── driver_profile_screen.dart
│   │   ├── home_screen.dart
│   │   ├── login_screen.dart
│   │   ├── segment_detail_screen.dart
│   │   ├── segment_list_screen.dart
│   │   ├── settings_screen.dart
│   │   ├── splash_screen.dart
│   │   ├── threshold_editor_screen.dart
│   │   ├── trip_history_screen.dart
│   │   ├── trip_in_progress_screen.dart
│   │   └── trip_summary_screen.dart
│   ├── theme/
│   │   ├── app_colors.dart
│   │   └── app_theme.dart
│   └── widgets/
│       ├── admin_guard.dart
│       ├── big_speed_display.dart
│       ├── buttons.dart
│       ├── map_widget.dart
│       ├── segment_feature_table.dart
│       ├── stat_card.dart
│       ├── summary_card.dart
│       ├── terrain_badge.dart
│       └── trip_score_chart.dart
└── utils/
    ├── feature_display_utils.dart
    ├── haversine.dart
    ├── landmark_utils.dart
    └── math_utils.dart
```

---

## 2) Startup Flow

1. `main()` runs `WidgetsFlutterBinding.ensureInitialized()`.
2. Loads `.env` via `flutter_dotenv`.
3. Loads saved language via `LanguageProvider.loadSavedLanguage()`.
4. Locks app orientation to portrait.
5. Sets system UI mode to edge-to-edge.
6. Boots `KsrtcApp` with `MultiProvider`:
   - `AuthProvider`
   - `TripProvider`
   - `LanguageProvider`
7. Routes are registered in `MaterialApp`.
8. Initial route is `/` (`SplashScreen`).
9. `SplashScreen` waits ~2 seconds and always navigates to `/login`.
10. Role routing happens after login (`/home` for driver, `/admin` for admin).

Notes:
- Theme mode is loaded from `SharedPreferences` (`dark_mode`).
- Localisation delegates are enabled for `en`, `ml`, `hi`.

---

## 3) Trip Recording Pipeline

### 3.1 Driver benchmark mode

1. Driver starts trip in `HomeScreen`.
2. App checks location services.
3. In real mode, app enforces calibration if not calibrated.
4. Vehicle type is resolved:
   - Driver profile vehicle type if set, else
   - selected from active cluster vehicle types.
5. `TripProvider.startTrip(vehicleType)`:
   - creates `tripId`
   - loads slope threshold from settings
   - starts sensor stream:
     - `SensorService` (real) or
     - `DemoSensorService` (demo)
   - initializes `SegmentationService` (default 100m)
   - clears and reloads benchmark/cluster cache in `TripProcessor`
6. Each incoming sample:
   - updates live speed/location UI state
   - is buffered and batch-written to `raw_data`
   - is fed into segmentation
7. Every completed segment (100m by default):
   - `TripProcessor.processSegment()` extracts 8 attributes
   - computes derivatives `Jx/Jy/VV` and radius `R`
   - unit conversion to benchmark units
   - smoothing + terrain classification
   - 120 features generated and saved
   - deviation score computed vs dynamic clusters (or fallback)
   - segment score saved in `segment_scores`
8. On stop:
   - streams stop, final raw batch flushes
   - `TripAnalytics.generateSummary()` writes `trip_summaries`
   - score computed and persisted
   - UI moves to summary/report views

### 3.2 Data collection mode

- Started from `DataCollectionScreen`.
- Uses same raw capture + segmentation pipeline.
- Mode is `collection`.
- No benchmark summary scoring pipeline is triggered.
- Metadata is written to `data_collection_trips`.

---

## 4) Dynamic Cluster System

### Data model

- `clusters` table: cluster metadata (`name`, `route`, `vehicle_type`, active/deleted flags)
- `cluster_features` table: min/max feature ranges by terrain

### Runtime behavior

1. `TripProcessor.loadBenchmarks(vehicleType)` loads active clusters.
2. If `vehicleType` is provided, clusters are filtered to that vehicle type.
3. Feature ranges are cached by key `${clusterId}_${terrain}`.
4. For each segment, `DeviationEngine.computeSegmentDeviationDynamic()`:
   - computes deviation against every loaded cluster with feature rows
   - chooses best cluster by lowest total deviation
   - stores:
     - `matched_cluster_name` (authoritative for N-cluster reporting)
     - backward-compatible `cluster0_deviation`, `cluster1_deviation`, `matched_cluster`

### Summary display behavior

- Summary cards use `matched_cluster_name` counts for trip-level percentages.
- UI now includes all relevant active clusters for the trip vehicle type (even 0% clusters), and also shows matched inactive clusters when needed.

---

## 5) Sensor Calibration

`CalibrationService` stores offsets in `SharedPreferences`:
- `cal_ax_offset`, `cal_ay_offset`, `cal_az_offset`, `cal_yaw_offset`
- `cal_is_calibrated`, `cal_date`

Guided flow:
1. Wait-for-stillness phase (sliding window std-dev check).
2. Recording phase (fixed sample count at 10 Hz).
3. Mean offsets are saved and then subtracted from live signals.

Purpose:
- make capture robust to dashboard mount angle and orientation drift.

---

## 6) AI Coaching (Current State)

### Active coaching path (enabled)

- Rule-based coaching only.
- Implemented in `analytics/coaching_engine.dart`.
- Used by:
  - `trip_summary_screen.dart`
  - `coaching_report_screen.dart`
  - `driver_profile_screen.dart`
- Produces deterministic insights from trip summary + segment deviation data.

### Groq path (kept in code, currently not wired in primary flow)

- `services/groq_coaching_service.dart` still exists.
- It can call Groq and cache text into `trip_summaries.coaching_report`.
- Current UI flows do not require network generation; they rely on local data and rule-based insights.
- `coaching_report` column is still read and shown if already populated.

---

## 7) Localisation

- Implemented using Flutter gen-l10n + ARB files.
- Supported languages:
  - English (`app_en.arb`)
  - Malayalam (`app_ml.arb`)
  - Hindi (`app_hi.arb`)
- `LanguageProvider` persists selected language in `SharedPreferences` under `language_code`.
- `MaterialApp.locale` is driven by `LanguageProvider`.

---

## 8) State Management

Provider-based architecture:

- `AuthProvider`
  - login/logout
  - role flags (`isAdmin`, `isDriver`)
  - session timeout (30 minutes inactivity)

- `TripProvider`
  - trip lifecycle state machine
  - stream subscription management
  - live telemetry state for UI
  - benchmark and collection mode entry/exit
  - history/data retrieval helpers

- `LanguageProvider`
  - locale state and persistence

---

## 9) Database Schema (v9)

Database file: `ksrtc_benchmarking.db`

Primary tables:
- `raw_data`
- `segments`
- `features`
- `segment_scores`
- `trip_summaries`
- `users`
- `config`
- `benchmark_config`
- `clusters`
- `cluster_features`
- `data_collection_trips`

Key points:
- `segment_scores` includes `matched_cluster_name` for N-cluster matching.
- `trip_summaries` still stores legacy cluster0/cluster1 aggregate fields and `coaching_report`.
- Default seed creates:
  - users (`admin`, `driver`)
  - baseline config
  - benchmark defaults
  - default clusters `Master Driver A/B`.

---

## 10) Security Notes

Current implementation details:

- Passwords are SHA-256 hashed (`DbHelper.hashPassword`) without salt.
- Default credentials are seeded (`admin123`, `driver123`) on first DB creation.
- `.env` is loaded at startup; API keys should remain out of version control.
- App requests GPS + sensor + storage permissions needed for capture/export.
- `AdminGuard` protects admin route rendering in app navigation.

Operational cautions:
- Unsalted SHA-256 and default seeded credentials are not production-hard by modern standards.
- This app is local-first; no server-side auth/session revocation exists.

---

## 11) Demo Mode

Switch: `AppConstants.demoMode`

Current value in code: `true`

Behavior:
- Uses `DemoSensorService` instead of real sensor service.
- Replays a dense NH-766 waypoint simulation (Kozhikode to Sulthan Bathery).
- Keeps emulator/dev testing functional without hardware sensors.

When set to `false`:
- Uses real sensors (`SensorService`) and real calibration gating.

---

## 12) Key Files Quick Reference

- Startup + app wiring: `lib/main.dart`
- Core trip state machine: `lib/providers/trip_provider.dart`
- Segment processing + scoring: `lib/services/trip_processor.dart`
- Dynamic deviation logic: `lib/analytics/deviation_engine.dart`
- Trip-level aggregation: `lib/analytics/trip_analytics.dart`
- Rule-based coaching: `lib/analytics/coaching_engine.dart`
- Optional Groq service (not primary flow): `lib/services/groq_coaching_service.dart`
- DB schema + all persistence: `lib/database/db_helper.dart`
- Cluster admin UI: `lib/ui/screens/cluster_management_screen.dart`
- Summary UI (post-trip): `lib/ui/screens/trip_summary_screen.dart`
- History + report UI: `lib/ui/screens/trip_history_screen.dart`, `lib/ui/screens/coaching_report_screen.dart`
- Data collection + in-app data viewer: `lib/ui/screens/data_collection_screen.dart`, `lib/ui/screens/admin_collection_screen.dart`, `lib/ui/screens/data_viewer_screen.dart`
- Calibration runtime: `lib/services/calibration_service.dart`
- Demo replay runtime: `lib/services/demo_sensor_service.dart`
- Localisation resources: `lib/l10n/*.arb`
- Android permissions/config: `android/app/src/main/AndroidManifest.xml`

---

## 13) Practical Runtime Notes

- Project currently runs local-first (SQLite-based, no cloud sync pipeline).
- Export uses CSV files written to Downloads when permitted.
- `android/app/build.gradle` contains a Gradle task-state workaround for OneDrive reparse-point issues during Flutter build tasks.
