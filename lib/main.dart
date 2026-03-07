import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/trip_provider.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/trip_in_progress_screen.dart';
import 'ui/screens/trip_summary_screen.dart';
import 'ui/screens/trip_history_screen.dart';
import 'ui/screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait orientation (phone is mounted on dashboard)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Keep screen on during trips
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const KsrtcApp());
}

class KsrtcApp extends StatefulWidget {
  const KsrtcApp({super.key});

  @override
  State<KsrtcApp> createState() => _KsrtcAppState();
}

class _KsrtcAppState extends State<KsrtcApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('dark_mode') ?? false;
    if (mounted) {
      setState(() {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      });
    }
  }

  void _setDarkMode(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', isDark);
    if (mounted) {
      setState(() {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TripProvider(),
      child: MaterialApp(
        title: 'KSRTC Benchmarking',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeMode,
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
          '/home': (_) => const HomeScreen(),
          '/trip': (_) => const TripInProgressScreen(),
          '/summary': (_) => const TripSummaryScreen(),
          '/history': (_) => const TripHistoryScreen(),
          '/settings': (_) => SettingsScreen(
                onDarkModeChanged: _setDarkMode,
              ),
        },
      ),
    );
  }
}
