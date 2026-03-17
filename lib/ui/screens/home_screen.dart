import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../widgets/map_widget.dart';
import '../widgets/big_speed_display.dart';
import '../widgets/terrain_badge.dart';
import '../widgets/buttons.dart';
import '../theme/app_colors.dart';
import 'data_collection_screen.dart';

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

class _HomeScreenState extends State<HomeScreen> {
  Timer? _sessionTimer;

  @override
  void initState() {
    super.initState();
    // Check session timeout every 5 minutes
    _sessionTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final auth = context.read<AuthProvider>();
      if (auth.checkSessionTimeout() && mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }

  void _updateActivity() {
    context.read<AuthProvider>().updateActivity();
  }

  @override
  Widget build(BuildContext context) {
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
                  tabs: const [
                    Tab(text: 'Benchmark'),
                    Tab(text: 'Data Collection'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildBenchmarkTab(provider, isDark),
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

  Widget _buildBenchmarkTab(TripProvider provider, bool isDark) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.directions_bus_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'KSRTC Benchmarking',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                    ),
                  ),
                ],
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
                    tooltip: 'Profile',
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
                    tooltip: 'Trip History',
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
                    tooltip: 'Settings',
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
              PrimaryButton(
                label: 'Start Trip',
                icon: Icons.play_arrow_rounded,
                loading: provider.state == TripState.calibrating,
                onPressed: provider.state == TripState.idle
                    ? () async {
                        _updateActivity();
                        await provider.startTrip();
                        if (!mounted) return;
                        if (provider.state == TripState.recording) {
                          Navigator.of(context).pushReplacementNamed('/trip');
                        }
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
