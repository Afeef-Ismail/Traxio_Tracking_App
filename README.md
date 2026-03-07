# KSRTC Master Driver Benchmarking System

A Flutter-based Android telematics application developed at **NIT Calicut (NITC)** for benchmarking **KSRTC (Kerala State Road Transport Corporation)** bus driver behavior using smartphone sensors.

The app captures real-time accelerometer, gyroscope, and GPS data at **10 Hz**, segments the route into **100-meter windows**, extracts **120 time- and frequency-domain features**, and scores each segment against research-derived master-driver benchmarks using **cluster deviation analysis**.

---

## Features

- **Real-Time Sensor Capture** — 10 Hz accelerometer, gyroscope, and GPS sampling with 2-second bias calibration
- **100m Segment Analysis** — Automatic GPS-based route segmentation with Haversine distance accumulation
- **120 Feature Extraction** — 8 driving attributes × 15 features each (11 time-domain + 4 frequency-domain)
- **Terrain Classification** — Automatic plain/uphill/downhill detection from altitude gradient
- **Cluster Deviation Scoring** — Per-segment scoring against terrain-specific master-driver benchmark profiles
- **Live Trip Dashboard** — Real-time speed display, GPS trail, segment markers, and running score
- **Trip History** — SQLite-backed trip logs with per-segment drill-down
- **Interactive Map** — Flutter Map with live GPS trail and segment markers
- **Demo Mode** — Built-in route simulation (Kozhikode → Sulthan Bathery) for emulator testing
- **Dark Mode** — Full dark/light theme support with persistent preference

---

## Driving Attributes

| # | Attribute | Symbol | Description |
|---|-----------|--------|-------------|
| 1 | Speed | `Speed` | GPS-derived vehicle speed (m/s) |
| 2 | Longitudinal Acceleration | `ay` | Acceleration along direction of travel |
| 3 | Lateral Acceleration | `ax` | Acceleration perpendicular to travel |
| 4 | Yaw Rate | `YR` | Rotational rate around vertical axis (°/s) |
| 5 | Lateral Jerk | `Jx` | Rate of change of lateral acceleration |
| 6 | Longitudinal Jerk | `Jy` | Rate of change of longitudinal acceleration |
| 7 | Vertical Velocity | `VV` | Altitude-derived vertical speed |
| 8 | Radius of Turn | `R` | Instantaneous turning radius from speed/yaw rate |

## Features Per Attribute (15)

**Time Domain (11):** Max, Min, Mean, Std, Peak-to-Peak, ARV, RMS, Shape Factor, Crest Factor, Impulse Factor, Margin Factor

**Frequency Domain (4):** Avg Amplitude, Frequency Centroid, Frequency Variance, Spectral Entropy

---

## Project Structure

```
lib/
├── main.dart                     # App entry point, routes, Provider setup
├── config/
│   ├── constants.dart            # App-wide constants (sensor rates, thresholds)
│   └── benchmark_tables.dart     # Research-derived master-driver benchmark profiles
├── models/
│   ├── raw_model.dart            # Raw sensor sample data model
│   ├── segment_model.dart        # Processed segment data model
│   ├── trip_model.dart           # Trip metadata model
│   └── feature_result.dart       # Feature extraction result model
├── services/
│   ├── sensor_service.dart       # Real hardware sensor capture (accelerometer + gyro + GPS)
│   ├── demo_sensor_service.dart  # Simulated sensor data for emulator testing
│   ├── segmentation_service.dart # GPS-based 100m segment boundary detection
│   ├── terrain_service.dart      # Altitude-based terrain classification
│   └── trip_processor.dart       # Orchestrates segment processing pipeline
├── analytics/
│   ├── feature_engine.dart       # 120-feature extraction (time + frequency domain)
│   ├── fft_engine.dart           # Fast Fourier Transform implementation
│   ├── smoothing.dart            # Moving average signal smoothing
│   ├── deviation_engine.dart     # Cluster deviation scoring against benchmarks
│   └── trip_analytics.dart       # Trip-level analytics aggregation
├── database/
│   └── db_helper.dart            # SQLite database helper (trips, segments, features)
├── providers/
│   └── trip_provider.dart        # Central state manager (ChangeNotifier + Provider)
├── ui/
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── home_screen.dart
│   │   ├── trip_in_progress_screen.dart
│   │   ├── trip_summary_screen.dart
│   │   ├── segment_list_screen.dart
│   │   ├── segment_detail_screen.dart
│   │   ├── trip_history_screen.dart
│   │   └── settings_screen.dart
│   ├── widgets/
│   │   ├── big_speed_display.dart
│   │   ├── stat_card.dart
│   │   ├── summary_card.dart
│   │   ├── map_widget.dart
│   │   ├── segment_feature_table.dart
│   │   ├── terrain_badge.dart
│   │   └── buttons.dart
│   └── theme/
│       ├── app_theme.dart
│       └── app_colors.dart
├── utils/
│   ├── haversine.dart            # Haversine distance & bearing calculations
│   └── math_utils.dart           # Statistical helper functions
backend/
├── main.py                       # Python backend for benchmark clustering
└── requirements.txt
test/
├── deviation_engine_test.dart
├── feature_engine_test.dart
├── fft_engine_test.dart
├── smoothing_test.dart
├── terrain_service_test.dart
├── integration_test.dart
└── utils_test.dart
```

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | Flutter 3.27+ / Dart 3.6+ |
| Sensors | `sensors_plus` (accelerometer, gyroscope) |
| GPS | `geolocator` + `permission_handler` |
| Database | `sqflite` (SQLite) |
| State Management | `provider` (ChangeNotifier) |
| Charts | `fl_chart` |
| Maps | `flutter_map` + `latlong2` (OpenStreetMap) |
| FFT / Math | `scidart` |
| Backend | Python (scikit-learn for benchmark clustering) |

---

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.0.0
- Android SDK (API 26+, compileSdk 35)
- Java 17+
- Android device with accelerometer, gyroscope, and GPS (for real data capture)

### Setup

```bash
# Clone the repository
git clone https://github.com/Afeef-Ismail/KSRTC_Benchmarking_App_NITC.git
cd KSRTC_Benchmarking_App_NITC

# Install dependencies
flutter pub get

# Run on connected device / emulator
flutter run
```

### Demo Mode

To test on an emulator without hardware sensors, set `demoMode = true` in [lib/config/constants.dart](lib/config/constants.dart):

```dart
static const bool demoMode = true;
```

This simulates a trip along the **Kozhikode → Sulthan Bathery** route (NH-766) through the Western Ghats with realistic terrain changes.

### Build Release APK

```bash
flutter build apk --release
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

---

## Demo Route

The built-in demo simulates the **Kozhikode → Sulthan Bathery** route (~95 km via NH-766) with 6 anchored landmarks:

1. **Kozhikode Bus Stand** (11.2588°N, 75.7804°E) — Start, plain terrain
2. **Thamarassery** (11.3678°N, 75.8595°E) — Foothills
3. **Lakkidi Viewpoint** (11.5133°N, 76.0195°E) — Ghat peak, steep uphill
4. **Vythiri** (11.5425°N, 76.0425°E) — Downhill into valley
5. **Kalpetta** (11.6087°N, 76.0816°E) — Wayanad plateau, plain
6. **Sulthan Bathery** (11.6634°N, 76.2673°E) — Destination

---

## Scoring Methodology

Each 100m segment is scored by comparing its 120-dimensional feature vector against terrain-specific **master-driver benchmark clusters**:

1. **Feature Extraction** — 8 attributes × 15 features = 120 features per segment
2. **Terrain Matching** — Segment classified as Plain/Uphill/Downhill from altitude gradient
3. **Benchmark Lookup** — Top 10 most discriminative features selected per terrain type
4. **Deviation Calculation** — Euclidean distance from master-driver cluster centroid
5. **Normalization** — Score mapped to 0–100 scale (100 = perfect match to master driver)

---

## License

This project is developed as part of academic research at the **National Institute of Technology Calicut (NITC)** in collaboration with **KSRTC Kerala**.

---

## Acknowledgments

- **NIT Calicut** — Department of Mechanical Engineering
- **KSRTC Kerala** — For domain expertise and route data
- Research references on smartphone-based telematics and driver behavior analysis
