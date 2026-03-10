import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import '../database/db_helper.dart';

/// Authentication provider managing user sessions.
class AuthProvider extends ChangeNotifier {
  final DbHelper _db = DbHelper();

  /// Currently logged-in user data (null if not logged in).
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;

  /// Timestamp of last user activity (for session timeout).
  DateTime _lastActivityTime = DateTime.now();
  DateTime get lastActivityTime => _lastActivityTime;

  /// Session timeout duration.
  static const Duration sessionTimeout = Duration(minutes: 30);

  // ─── Computed properties ──────────────────────────────────────────

  bool get isLoggedIn => _currentUser != null;

  bool get isAdmin =>
      _currentUser != null && _currentUser!['role'] == 'admin';

  bool get isDriver =>
      _currentUser != null && _currentUser!['role'] == 'driver';

  String get username =>
      _currentUser?['username'] as String? ?? '';

  // ─── Auth Methods ─────────────────────────────────────────────────

  /// Attempt login with username and password.
  /// Returns true on success, false on failure.
  Future<bool> login(String username, String password) async {
    final passwordHash = DbHelper.hashPassword(password);
    final user = await _db.getUserByUsername(username);

    if (user == null) return false;
    if (user['password_hash'] != passwordHash) return false;

    _currentUser = user;
    _lastActivityTime = DateTime.now();
    notifyListeners();
    return true;
  }

  /// Log out the current user.
  void logout() {
    _currentUser = null;
    notifyListeners();
  }

  /// Update the last activity timestamp (call on user interaction).
  void updateActivity() {
    _lastActivityTime = DateTime.now();
  }

  /// Set internal state for testing. DO NOT use in production code.
  @visibleForTesting
  void setTestState({
    Map<String, dynamic>? user,
    DateTime? lastActivity,
  }) {
    _currentUser = user;
    if (lastActivity != null) _lastActivityTime = lastActivity;
  }

  /// Check if the session has timed out (30 min inactivity).
  /// Returns true if the session was expired and the user was logged out.
  bool checkSessionTimeout() {
    if (!isLoggedIn) return false;

    final elapsed = DateTime.now().difference(_lastActivityTime);
    if (elapsed >= sessionTimeout) {
      logout();
      return true;
    }
    return false;
  }
}
