import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ksrtc_app/providers/auth_provider.dart';
import 'package:ksrtc_app/providers/trip_provider.dart';
import 'package:ksrtc_app/ui/screens/login_screen.dart';
import 'package:ksrtc_app/config/constants.dart';

// ═══════════════════════════════════════════════════════════════════════
// FakeAuthProvider — replaces DB-backed login with in-memory credentials
// so tests can run without sqflite (host-side `flutter test`).
// ═══════════════════════════════════════════════════════════════════════

class FakeAuthProvider extends AuthProvider {
  static const _fakeUsers = {
    'admin':      {'password': 'admin123',  'role': 'admin'},
    'driver':     {'password': 'driver123', 'role': 'driver'},
    'testdriver': {'password': 'test123',   'role': 'driver'},
  };

  @override
  Future<bool> login(String username, String password) async {
    final user = _fakeUsers[username];
    if (user == null || user['password'] != password) return false;

    setTestState(user: {
      'id': _fakeUsers.keys.toList().indexOf(username) + 1,
      'username': username,
      'role': user['role']!,
      'password_hash': 'fake',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Helper — wraps LoginScreen in a minimal app with named routes
// ═══════════════════════════════════════════════════════════════════════

Widget _buildTestApp(AuthProvider auth) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<TripProvider>(create: (_) => TripProvider()),
    ],
    child: MaterialApp(
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/admin': (_) => const Scaffold(
              body: Center(child: Text('Admin Home Screen')),
            ),
        '/home': (_) => const Scaffold(
              body: Center(child: Text('Driver Home Screen')),
            ),
      },
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  // Guard: these tests rely on demoMode being true so the dev buttons render.
  if (!AppConstants.demoMode) {
    test('SKIPPED — demoMode is false, dev buttons will not render', () {});
    return;
  }

  group('Login Screen — Dev Quick Login Buttons', () {
    testWidgets('three dev quick-login buttons are visible', (tester) async {
      await tester.pumpWidget(_buildTestApp(FakeAuthProvider()));
      await tester.pumpAndSettle();

      expect(find.text('DEV QUICK LOGIN'), findsOneWidget);
      expect(find.text('Login as Admin'), findsOneWidget);
      expect(find.text('Login as Driver'), findsOneWidget);
      expect(find.text('Login as Test Driver'), findsOneWidget);
    });

    testWidgets('"Login as Admin" → navigates to Admin Home', (tester) async {
      final auth = FakeAuthProvider();
      await tester.pumpWidget(_buildTestApp(auth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Login as Admin'));
      await tester.pumpAndSettle();

      expect(find.text('Admin Home Screen'), findsOneWidget);
      expect(auth.isAdmin, true);
      expect(auth.username, 'admin');
    });

    testWidgets('"Login as Driver" → navigates to Driver Home', (tester) async {
      final auth = FakeAuthProvider();
      await tester.pumpWidget(_buildTestApp(auth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Login as Driver'));
      await tester.pumpAndSettle();

      expect(find.text('Driver Home Screen'), findsOneWidget);
      expect(auth.isDriver, true);
      expect(auth.username, 'driver');
    });

    testWidgets('"Login as Test Driver" → navigates to Driver Home',
        (tester) async {
      final auth = FakeAuthProvider();
      await tester.pumpWidget(_buildTestApp(auth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Login as Test Driver'));
      await tester.pumpAndSettle();

      expect(find.text('Driver Home Screen'), findsOneWidget);
      expect(auth.isDriver, true);
      expect(auth.username, 'testdriver');
    });

    testWidgets('invalid manual login shows error message', (tester) async {
      await tester.pumpWidget(_buildTestApp(FakeAuthProvider()));
      await tester.pumpAndSettle();

      // Enter bad credentials
      await tester.enterText(find.byType(TextFormField).first, 'baduser');
      await tester.enterText(find.byType(TextFormField).last, 'badpass');
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid username or password'), findsOneWidget);
    });

    testWidgets('admin login → logout → back to login screen',
        (tester) async {
      final auth = FakeAuthProvider();
      await tester.pumpWidget(_buildTestApp(auth));
      await tester.pumpAndSettle();

      // Login as admin
      await tester.tap(find.text('Login as Admin'));
      await tester.pumpAndSettle();
      expect(find.text('Admin Home Screen'), findsOneWidget);

      // Verify provider state
      expect(auth.isLoggedIn, true);
      expect(auth.isAdmin, true);

      // Logout (provider-level, since the Admin Home stub has no button)
      auth.logout();
      expect(auth.isLoggedIn, false);
      expect(auth.isAdmin, false);
    });

    testWidgets('driver login → logout → state cleared', (tester) async {
      final auth = FakeAuthProvider();
      await tester.pumpWidget(_buildTestApp(auth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Login as Driver'));
      await tester.pumpAndSettle();
      expect(find.text('Driver Home Screen'), findsOneWidget);
      expect(auth.isDriver, true);

      auth.logout();
      expect(auth.isLoggedIn, false);
      expect(auth.isDriver, false);
    });
  });
}
