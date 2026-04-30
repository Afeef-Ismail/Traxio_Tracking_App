import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'providers/auth_provider.dart';
import 'providers/language_provider.dart';
import 'providers/trip_provider.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/consent_notice_screen.dart';
import 'ui/screens/signup_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/admin_home_screen.dart';
import 'ui/screens/trip_in_progress_screen.dart';
import 'ui/screens/trip_summary_screen.dart';
import 'ui/screens/trip_history_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/driver_profile_screen.dart';
import 'ui/widgets/admin_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final languageProvider = LanguageProvider();
  await languageProvider.loadSavedLanguage();

  // Lock to portrait orientation (phone is mounted on dashboard)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Keep screen on during trips
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(KsrtcApp(languageProvider: languageProvider));
}

class KsrtcApp extends StatefulWidget {
  final LanguageProvider languageProvider;

  const KsrtcApp({super.key, required this.languageProvider});

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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => TripProvider()),
        ChangeNotifierProvider.value(value: widget.languageProvider),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, child) {
          return MaterialApp(
            title: 'KSRTC Benchmarking',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: _themeMode,
            locale: languageProvider.locale,
            supportedLocales: const [
              Locale('en'),
              Locale('ml'),
              Locale('hi'),
            ],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            initialRoute: '/',
            routes: {
              '/': (_) => const SplashScreen(),
              '/onboarding': (_) => const OnboardingScreen(),
              '/login': (_) => const LoginScreen(),
              '/consent': (_) => const ConsentNoticeScreen(),
              '/signup': (_) => const SignupScreen(),
              '/home': (_) => const HomeScreen(),
              '/admin': (_) => const AdminGuard(child: AdminHomeScreen()),
              '/trip': (_) => const TripInProgressScreen(),
              '/summary': (_) => const TripSummaryScreen(),
              '/history': (_) => const TripHistoryScreen(),
              '/profile': (_) => const DriverProfileScreen(),
              '/settings': (_) => SettingsScreen(
                    onDarkModeChanged: _setDarkMode,
                  ),
            },
          );
        },
      ),
    );
  }
}
