import 'package:flutter_test/flutter_test.dart';
import 'package:ksrtc_app/providers/auth_provider.dart';

void main() {
  group('AuthProvider Session Timeout', () {
    test('checkSessionTimeout returns false when not logged in', () {
      final auth = AuthProvider();
      expect(auth.isLoggedIn, false);
      expect(auth.checkSessionTimeout(), false);
    });

    test('session expires after 31 minutes of inactivity', () {
      final auth = AuthProvider();
      // Simulate a logged-in user with stale activity
      auth.setTestState(
        user: {
          'id': 1,
          'username': 'driver',
          'role': 'driver',
          'password_hash': 'x',
          'created_at': 0,
        },
        lastActivity: DateTime.now().subtract(const Duration(minutes: 31)),
      );

      expect(auth.isLoggedIn, true);
      final expired = auth.checkSessionTimeout();
      expect(expired, true, reason: 'Session should expire after 31 min');
      expect(auth.isLoggedIn, false, reason: 'User should be logged out');
    });

    test('session stays active within 29 minutes', () {
      final auth = AuthProvider();
      auth.setTestState(
        user: {
          'id': 1,
          'username': 'driver',
          'role': 'driver',
          'password_hash': 'x',
          'created_at': 0,
        },
        lastActivity: DateTime.now().subtract(const Duration(minutes: 29)),
      );

      expect(auth.isLoggedIn, true);
      final expired = auth.checkSessionTimeout();
      expect(expired, false, reason: 'Session should still be active');
      expect(auth.isLoggedIn, true);
    });

    test('session expires at exactly 30 minutes', () {
      final auth = AuthProvider();
      auth.setTestState(
        user: {
          'id': 1,
          'username': 'admin',
          'role': 'admin',
          'password_hash': 'x',
          'created_at': 0,
        },
        lastActivity: DateTime.now().subtract(const Duration(minutes: 30)),
      );

      expect(auth.isLoggedIn, true);
      final expired = auth.checkSessionTimeout();
      expect(expired, true, reason: 'Session should expire at exactly 30 min');
      expect(auth.isLoggedIn, false);
    });

    test('updateActivity resets the timer', () {
      final auth = AuthProvider();
      auth.setTestState(
        user: {
          'id': 1,
          'username': 'driver',
          'role': 'driver',
          'password_hash': 'x',
          'created_at': 0,
        },
        lastActivity: DateTime.now().subtract(const Duration(minutes: 29)),
      );

      // Activity refresh should reset the timer
      auth.updateActivity();
      final elapsed = DateTime.now().difference(auth.lastActivityTime);
      expect(elapsed.inSeconds, lessThan(2));
      expect(auth.checkSessionTimeout(), false);
    });

    test('logout clears user state', () {
      final auth = AuthProvider();
      auth.setTestState(
        user: {
          'id': 1,
          'username': 'admin',
          'role': 'admin',
          'password_hash': 'x',
          'created_at': 0,
        },
      );

      expect(auth.isLoggedIn, true);
      expect(auth.isAdmin, true);
      expect(auth.username, 'admin');

      auth.logout();

      expect(auth.isLoggedIn, false);
      expect(auth.isAdmin, false);
      expect(auth.username, '');
    });

    test('role properties work correctly', () {
      final auth = AuthProvider();

      // Admin
      auth.setTestState(
        user: {'id': 1, 'username': 'admin', 'role': 'admin',
               'password_hash': 'x', 'created_at': 0},
      );
      expect(auth.isAdmin, true);
      expect(auth.isDriver, false);

      // Driver
      auth.setTestState(
        user: {'id': 2, 'username': 'driver', 'role': 'driver',
               'password_hash': 'x', 'created_at': 0},
      );
      expect(auth.isAdmin, false);
      expect(auth.isDriver, true);
    });
  });
}
