import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../widgets/map_widget.dart';
import '../widgets/big_speed_display.dart';
import '../widgets/terrain_badge.dart';
import '../widgets/buttons.dart';
import '../theme/app_colors.dart';
import 'data_collection_screen.dart';
import 'calibration_screen.dart';
import '../../services/calibration_service.dart';
import '../../config/constants.dart';
import '../screens/cluster_management_screen.dart' show vehicleTypeIcon;

/// Home / Start Trip Screen.
///
/// Layout:
///   - Top: App title + Settings icon
///   - Main: Large Map Widget (60%+ height)
///   - Bottom: Speed display, terrain badge, Start Trip button
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _sessionTimer;
  bool _pendingStartTripAfterLocationSettings = false;
  bool _isCalibrated = false;
  List<String> _activeVehicleTypes = [];

  final CalibrationService _calibrationService = CalibrationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check session timeout every 5 minutes
    _sessionTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final auth = context.read<AuthProvider>();
      if (auth.checkSessionTimeout() && mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    });
    _loadCalibrationStatus();
    _loadVehicleTypes();
  }

  Future<void> _loadCalibrationStatus() async {
    await _calibrationService.load();
    if (mounted) {
      setState(() => _isCalibrated = _calibrationService.isCalibrated);
    }
  }

  Future<void> _loadVehicleTypes() async {
    final provider = context.read<TripProvider>();
    final types = await provider.getActiveVehicleTypes();
    if (mounted) {
      setState(() => _activeVehicleTypes = types);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleLocationResumeForPendingTripStart();
    }
  }

  void _updateActivity() {
    context.read<AuthProvider>().updateActivity();
  }

  Future<void> _handleLocationResumeForPendingTripStart() async {
    if (!_pendingStartTripAfterLocationSettings || !mounted) return;

    final provider = context.read<TripProvider>();
    if (provider.state != TripState.idle) {
      _pendingStartTripAfterLocationSettings = false;
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled || !mounted) return;

    _pendingStartTripAfterLocationSettings = false;
    await provider.startTrip();
    if (!mounted) return;
    if (provider.state == TripState.recording) {
      Navigator.of(context).pushReplacementNamed('/trip');
    }
  }

  Future<bool> _ensureLocationServiceEnabledForTripStart() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (serviceEnabled) return true;

    if (!mounted) return false;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(l10n.locationServiceDisabled),
          content: Text(l10n.locationServiceMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('open_settings'),
            child: Text(l10n.openSettings),
          ),
        ],
      );
      },
    );

    if (action == 'open_settings') {
      _pendingStartTripAfterLocationSettings = true;
      await Geolocator.openLocationSettings();
    }

    return false;
  }

  Future<void> _onStartTripPressed(TripProvider provider) async {
    _updateActivity();
    final serviceEnabled = await _ensureLocationServiceEnabledForTripStart();
    if (!serviceEnabled || !mounted) return;

    _pendingStartTripAfterLocationSettings = false;

    // In real mode: prompt calibration if not calibrated yet
    if (!AppConstants.demoMode && !_isCalibrated) {
      final didCalibrate = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const CalibrationScreen(showContinueButton: true),
        ),
      );
      if (!mounted) return;
      if (didCalibrate != true) return;
      await _loadCalibrationStatus();
    }

    // Select vehicle type if multiple types exist across active clusters
    String vehicleType = '';
    if (_activeVehicleTypes.length > 1) {
      vehicleType = await _showVehicleTypeSelection() ?? '';
      if (!mounted) return;
    } else if (_activeVehicleTypes.length == 1) {
      vehicleType = _activeVehicleTypes.first;
    }

    await provider.startTrip(vehicleType: vehicleType);
    if (!mounted) return;
    if (provider.state == TripState.recording) {
      Navigator.of(context).pushReplacementNamed('/trip');
    }
  }

  Future<String?> _showVehicleTypeSelection() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('What are you driving?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _activeVehicleTypes.map((type) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(type),
                    icon: Icon(vehicleTypeIcon(type), size: 24),
                    label: Text(
                      type,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<TripProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                  ),
                ),
                child: TabBar(
                  indicatorColor: AppColors.primary,
                  labelColor: AppColors.primary,
                  unselectedLabelColor:
                      isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    overflow: TextOverflow.ellipsis,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 13,
                    overflow: TextOverflow.ellipsis,
                  ),
                  tabs: [
                    Tab(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(l10n.benchmark),
                      ),
                    ),
                    Tab(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(l10n.dataCollection),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildBenchmarkTab(provider, isDark, l10n),
                    const DataCollectionScreen(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenchmarkTab(
      TripProvider provider, bool isDark, AppLocalizations l10n) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.directions_bus_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        l10n.appName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/profile');
                    },
                    icon: Icon(
                      Icons.person_rounded,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textSecondary,
                    ),
                    tooltip: l10n.driverProfile,
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/history');
                    },
                    icon: Icon(
                      Icons.history_rounded,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textSecondary,
                    ),
                    tooltip: l10n.tripHistory,
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/settings');
                    },
                    icon: Icon(
                      Icons.settings_rounded,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textSecondary,
                    ),
                    tooltip: l10n.settings,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: MapWidget(
                latitude: provider.currentLat,
                longitude: provider.currentLon,
                trail: provider.gpsTrail,
                segmentMarkers: provider.segmentMarkers,
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  BigSpeedDisplay(
                    speedMs: provider.currentSpeed,
                    compact: true,
                  ),
                  TerrainBadge(
                    terrain: provider.currentTerrain,
                    large: true,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Calibration status indicator (real mode only)
              if (!AppConstants.demoMode) ...[
                GestureDetector(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CalibrationScreen(),
                      ),
                    );
                    _loadCalibrationStatus();
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isCalibrated
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        size: 16,
                        color: _isCalibrated
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isCalibrated
                            ? 'Calibrated'
                            : 'Not calibrated — tap to calibrate',
                        style: TextStyle(
                          fontSize: 13,
                          color: _isCalibrated
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              PrimaryButton(
                label: l10n.startTrip,
                icon: Icons.play_arrow_rounded,
                loading: provider.state == TripState.calibrating,
                onPressed: provider.state == TripState.idle
                    ? () => _onStartTripPressed(provider)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
