import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../widgets/map_widget.dart';
import '../widgets/big_speed_display.dart';
import '../widgets/terrain_badge.dart';
import '../widgets/buttons.dart';
import '../theme/app_colors.dart';
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

class _HomeScreenState extends State<HomeScreen>
  with WidgetsBindingObserver, TickerProviderStateMixin {
  Timer? _sessionTimer;
  bool _pendingStartTripAfterLocationSettings = false;
  bool _isCalibrated = false;
  List<String> _activeVehicleTypes = [];
  late final AnimationController _calibrationReminderController;
  late final Animation<double> _calibrationReminderOpacity;

  final CalibrationService _calibrationService = CalibrationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _calibrationReminderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _calibrationReminderOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 1,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 3),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 3),
    ]).animate(_calibrationReminderController);
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
      setState(() {
        _isCalibrated = _calibrationService.isCalibrated;
      });
      if (_isCalibrated) {
        _calibrationReminderController.stop();
      } else if (!_calibrationReminderController.isAnimating) {
        _calibrationReminderController.repeat();
      }
    }
  }

  Future<void> _loadVehicleTypes() async {
    final provider = context.read<TripProvider>();
    final types = await provider.getActiveVehicleTypes();
    if (mounted) {
      setState(() => _activeVehicleTypes = types);
    }
  }

  Future<void> _maybeShowCalibrationPrompt() async {
    if (AppConstants.demoMode || !mounted) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isDriver) return;

    final username = auth.username;
    if (username.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final promptKey = 'calibration_prompted_$username';
    final alreadyPrompted = prefs.getBool(promptKey) ?? false;
    if (alreadyPrompted || !mounted) return;

    await prefs.setBool(promptKey, true);
    if (!mounted) return;

    final shouldCalibrate = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(l10n.calibratePhone),
          content: Text(l10n.calibrationPromptMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.doItLater),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.calibrateNow),
            ),
          ],
        );
      },
    );

    if (shouldCalibrate == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const CalibrationScreen(showContinueButton: true),
        ),
      );
      await _loadCalibrationStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _calibrationReminderController.dispose();
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
      Navigator.of(context).pushReplacementNamed(
        '/trip',
        arguments: {'sourceTab': 2},
      );
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeShowCalibrationPrompt();
      });

    if (action == 'open_settings') {
      _pendingStartTripAfterLocationSettings = true;
      await Geolocator.openLocationSettings();
    }

    return false;
  }

  Future<void> _onStartTripPressed(TripProvider provider) async {
    _updateActivity();
    // Read profile vehicle type before any await (BuildContext safety)
    final profileVehicleType =
        context.read<AuthProvider>().currentUser?['vehicle_type'] as String? ??
            '';
    final serviceEnabled = await _ensureLocationServiceEnabledForTripStart();
    if (!serviceEnabled || !mounted) return;

    _pendingStartTripAfterLocationSettings = false;

    // Use driver's saved vehicle type if set; otherwise prompt
    String vehicleType = '';
    if (profileVehicleType.isNotEmpty) {
      vehicleType = profileVehicleType;
    } else if (_activeVehicleTypes.length > 1) {
      vehicleType = await _showVehicleTypeSelection() ?? '';
      if (!mounted) return;
    } else if (_activeVehicleTypes.length == 1) {
      vehicleType = _activeVehicleTypes.first;
    }

    await provider.startTrip(vehicleType: vehicleType);
    if (!mounted) return;
    if (provider.state == TripState.recording) {
      Navigator.of(context).pushReplacementNamed(
        '/trip',
        arguments: {'sourceTab': 2},
      );
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

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: AppConstants.demoMode
          ? null
          : FloatingActionButton(
              mini: true,
              tooltip: 'Calibrate Sensors',
              backgroundColor:
                  _isCalibrated ? AppColors.success : AppColors.warning,
              foregroundColor: Colors.white,
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CalibrationScreen(),
                  ),
                );
                await _loadCalibrationStatus();
              },
              child: Icon(
                _isCalibrated ? Icons.check_rounded : Icons.tune_rounded,
              ),
            ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildBenchmarkTab(provider, isDark, l10n),
            ),
            if (AppConstants.demoMode == false && !_isCalibrated)
              Positioned(
                left: 18,
                bottom: 86,
                child: FadeTransition(
                  opacity: _calibrationReminderOpacity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.65)
                          : Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text(
                        'Tap to calibrate',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
                color: Colors.black.withValues(alpha: 0.08),
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
