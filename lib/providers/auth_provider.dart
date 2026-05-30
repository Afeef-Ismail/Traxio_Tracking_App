import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../database/db_helper.dart';
import '../services/firebase_sync_service.dart';

/// Authentication provider managing user sessions.
class AuthProvider extends ChangeNotifier {
  final DbHelper _db = DbHelper();
  final FirebaseAuth? _firebaseAuth;
  final FirebaseFirestore? _firestore;
  static final RegExp _passwordPolicyRegex = RegExp(
    r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z\d]).{6,}$',
  );

  AuthProvider({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
      : _firebaseAuth = firebaseAuth,
        _firestore = firestore;

  FirebaseAuth get _auth => _firebaseAuth ?? FirebaseAuth.instance;
  FirebaseFirestore get _cloudFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  /// Currently logged-in user data (null if not logged in).
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;
  String? _lastAuthError;
  String? get lastAuthError => _lastAuthError;

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

  String get username => _currentUser?['username'] as String? ?? '';
  String get email => _currentUser?['email'] as String? ?? '';
  String get fullName => _currentUser?['full_name'] as String? ?? '';

  // ─── Auth Methods ─────────────────────────────────────────────────

  static bool isStrongPassword(String password) =>
      _passwordPolicyRegex.hasMatch(password);

  Future<bool> login(String identifier, String password) async {
    final normalizedIdentifier = identifier.trim();
    if (normalizedIdentifier.isEmpty) return false;

    final passwordHash = DbHelper.hashPassword(password);
    final cloudUser = normalizedIdentifier.contains('@')
        ? await _loadCloudUserProfileByEmail(normalizedIdentifier)
        : await _loadCloudUserProfileByUsername(normalizedIdentifier);

    if (cloudUser != null) {
      final emailAddress = (cloudUser['email'] as String?)?.trim() ?? '';
      if (emailAddress.isEmpty) {
        _lastAuthError = 'Cloud account is missing an email address.';
        return false;
      }

      try {
        await _signInWithEmail(emailAddress, password);
        final firebaseUid = _auth.currentUser?.uid;
        final cloudProfile = await _loadCloudUserProfile(firebaseUid) ?? cloudUser;
        final usernameValue = (cloudProfile['username'] as String?)?.trim() ??
            normalizedIdentifier.split('@').first;
        final existingLocalUser = await _resolveLocalUser(usernameValue) ??
            await _resolveLocalUser(emailAddress);

        if (existingLocalUser == null) {
          await _db.createUser(
            usernameValue,
            passwordHash,
            (cloudProfile['role'] as String?) ?? 'driver',
            fullName: (cloudProfile['full_name'] as String?) ?? '',
            email: emailAddress,
            firebaseUid: firebaseUid ?? '',
            busNumber: (cloudProfile['bus_number'] as String?) ?? '',
            vehicleType: (cloudProfile['vehicle_type'] as String?) ?? '',
            vehicleNumber: (cloudProfile['vehicle_number'] as String?) ?? '',
          );
        }

        final hydratedLocalUser =
            await _resolveLocalUser(usernameValue) ?? cloudProfile;
        _setCurrentUser(hydratedLocalUser ?? {
          'username': usernameValue,
          'email': emailAddress,
          'role': (cloudProfile['role'] as String?) ?? 'driver',
        });
        await _seedFirestoreAdminDocIfNeeded(hydratedLocalUser ?? cloudProfile, firebaseUid);
        await _runZeroSegmentCleanupIfNeeded(hydratedLocalUser ?? cloudProfile);
        return true;
      } catch (e) {
        _lastAuthError = 'Firebase login failed. Please check your credentials.';
        debugPrint('Firebase sign-in failed for cloud user: $e');
        return false;
      }
    }

    final localUser = await _resolveLocalUser(normalizedIdentifier);
    if (localUser == null) {
      _lastAuthError = 'No account found for "$normalizedIdentifier".';
      return false;
    }

    if (localUser['password_hash'] == passwordHash) {
      _setCurrentUser(localUser);
      // Silent auto-link: if this user's local SQLite row has no Firebase UID,
      // create (or sign into) a synthetic-email Firebase Auth account using
      // the password just supplied, then backfill the UID into SQLite. This
      // keeps drivers' Firestore syncs working without any UI prompt.
      final hydratedUser =
          await _autoLinkFirebaseUidIfPossible(localUser, password);
      await _seedFirestoreAdminDocIfNeeded(
          hydratedUser, hydratedUser['firebase_uid'] as String?);
      await _runZeroSegmentCleanupIfNeeded(hydratedUser);
      return true;
    }

    _lastAuthError = 'Invalid password.';

    return false;
  }

  /// Backfills the SQLite firebase_uid column for any local user whose row
  /// pre-dates Firebase Auth integration (or lost its UID).
  ///
  /// Resolution order:
  ///   1. If the SQLite row has a real email, sign in with that email + the
  ///      plaintext password just typed. This is the account the user's
  ///      Firestore data actually lives under, so it must be tried first.
  ///   2. Only if the row has no email, or the real-email sign-in returns
  ///      user-not-found, fall back to the synthetic "username@traxio.app"
  ///      account (create, or sign in if it already exists).
  ///
  /// All failures are logged to the console and swallowed — the local login
  /// still succeeds so offline use isn't broken. Returns the (possibly
  /// updated) local user map.
  Future<Map<String, dynamic>> _autoLinkFirebaseUidIfPossible(
    Map<String, dynamic> localUser,
    String password,
  ) async {
    final existingUid =
        (localUser['firebase_uid'] as String?)?.trim() ?? '';
    if (existingUid.isNotEmpty) {
      return localUser;
    }

    final username = (localUser['username'] as String?)?.trim() ?? '';
    if (username.isEmpty || password.isEmpty) {
      debugPrint(
          'Auto-link skipped: missing username or password for local user.');
      return localUser;
    }

    final localId = localUser['id'];
    if (localId is! int) {
      debugPrint('Auto-link skipped: local user has no integer id.');
      return localUser;
    }

    final realEmail = (localUser['email'] as String?)?.trim() ?? '';

    String? firebaseUid;
    bool linkedViaRealEmail = false;

    // ── 1. Prefer the user's REAL email account ───────────────────────────
    // This is the account created at register() time, under which their
    // Firestore documents are stored. Signing in here yields the correct UID.
    if (realEmail.isNotEmpty && realEmail.contains('@')) {
      try {
        final cred = await _auth.signInWithEmailAndPassword(
          email: realEmail,
          password: password,
        );
        firebaseUid = cred.user?.uid;
        linkedViaRealEmail = true;
        debugPrint(
            'Auto-link: signed into real-email account "$realEmail" → uid=$firebaseUid');
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          // No Firebase account at the real email — fall through to synthetic.
          debugPrint(
              'Auto-link: no Firebase account at real email "$realEmail"; '
              'falling back to synthetic email.');
        } else {
          // wrong-password / network / etc. Do NOT create a synthetic account
          // with possibly-wrong credentials — abort and keep local login.
          debugPrint(
              'Auto-link: real-email sign-in failed for "$realEmail": '
              '${e.code} ${e.message}');
          return localUser;
        }
      } catch (e) {
        if (_looksLikePigeonCastError(e)) {
          final recovered = _auth.currentUser;
          if (recovered != null &&
              recovered.email != null &&
              recovered.email!.toLowerCase() == realEmail.toLowerCase()) {
            firebaseUid = recovered.uid;
            linkedViaRealEmail = true;
            debugPrint(
                'Auto-link: recovered uid=$firebaseUid from pigeon cast error (real email).');
          } else {
            debugPrint(
                'Auto-link real-email plugin cast error with no recoverable session: $e');
            return localUser;
          }
        } else {
          debugPrint(
              'Auto-link real-email unexpected error for "$realEmail": $e');
          return localUser;
        }
      }
    }

    // ── 2. Fall back to the synthetic username@traxio.app account ─────────
    // Only when there is no real email, or the real email had no Firebase
    // account (user-not-found).
    if (!linkedViaRealEmail && (firebaseUid == null || firebaseUid.isEmpty)) {
      final syntheticEmail = '${username.toLowerCase()}@traxio.app';
      try {
        final cred = await _auth.createUserWithEmailAndPassword(
          email: syntheticEmail,
          password: password,
        );
        firebaseUid = cred.user?.uid;
        debugPrint(
            'Auto-link: created synthetic account "$syntheticEmail" → uid=$firebaseUid');
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          try {
            final cred = await _auth.signInWithEmailAndPassword(
              email: syntheticEmail,
              password: password,
            );
            firebaseUid = cred.user?.uid;
            debugPrint(
                'Auto-link: signed into existing synthetic account "$syntheticEmail" → uid=$firebaseUid');
          } catch (signInError) {
            debugPrint(
                'Auto-link synthetic sign-in fallback failed for "$syntheticEmail": $signInError');
            return localUser;
          }
        } else {
          debugPrint(
              'Auto-link synthetic signup failed for "$syntheticEmail": ${e.code} ${e.message}');
          return localUser;
        }
      } catch (e) {
        if (_looksLikePigeonCastError(e)) {
          final recovered = _auth.currentUser;
          if (recovered != null &&
              recovered.email != null &&
              recovered.email!.toLowerCase() == syntheticEmail) {
            firebaseUid = recovered.uid;
            debugPrint(
                'Auto-link: recovered uid=$firebaseUid from pigeon cast error (synthetic).');
          } else {
            debugPrint(
                'Auto-link synthetic plugin cast error with no recoverable session: $e');
            return localUser;
          }
        } else {
          debugPrint(
              'Auto-link synthetic unexpected error for "$syntheticEmail": $e');
          return localUser;
        }
      }
    }

    final newUid = firebaseUid?.trim() ?? '';
    if (newUid.isEmpty) {
      debugPrint(
          'Auto-link aborted: no UID returned after Firebase Auth call.');
      return localUser;
    }

    try {
      await _db.updateUserFirebaseUid(localId, newUid);
    } catch (e) {
      debugPrint(
          'Auto-link DB update failed for "$username" (uid=$newUid): $e');
      return localUser;
    }

    final updated = Map<String, dynamic>.from(localUser)
      ..['firebase_uid'] = newUid;
    // If the row had no email and we linked via the synthetic account, record
    // the synthetic email so subsequent logins resolve to the same account.
    final localEmail = (localUser['email'] as String?)?.trim() ?? '';
    if (localEmail.isEmpty && !linkedViaRealEmail) {
      updated['email'] = '${username.toLowerCase()}@traxio.app';
    }
    _setCurrentUser(updated);
    debugPrint(
        'Auto-link complete: SQLite user "$username" linked to Firebase uid=$newUid '
        '(via ${linkedViaRealEmail ? 'real email' : 'synthetic email'}).');
    return updated;
  }

  Future<bool> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required String role,
    String vehicleType = '',
    String vehicleNumber = '',
    String busNumber = '',
  }) async {
    _lastAuthError = null;
    final safeUsername = username.trim();
    final safeUsernameLower = safeUsername.toLowerCase();
    final safeEmail = email.trim().toLowerCase();
    final safeFullName = fullName.trim();

    if (safeUsername.isEmpty || safeEmail.isEmpty) {
      _lastAuthError = 'Username and email are required.';
      return false;
    }

    if (!isStrongPassword(password)) {
      _lastAuthError =
          'Password must contain at least 1 uppercase, 1 lowercase, 1 number, 1 special character, and be at least 6 characters long.';
      return false;
    }

    final existingUsername =
        await _db.getUserByUsernameInsensitive(safeUsernameLower);
    if (existingUsername != null) {
      _lastAuthError = 'Username "$safeUsername" is already taken.';
      return false;
    }

    final existingEmail = await _db.getUserByEmail(safeEmail);
    if (existingEmail != null) {
      _lastAuthError = 'An account with this email already exists.';
      return false;
    }

    User? firebaseUser;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: safeEmail,
        password: password,
      );
      firebaseUser = credential.user;
    } on FirebaseAuthException catch (e) {
      _lastAuthError = _mapFirebaseAuthError(e);
      debugPrint('Firebase account creation failed: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      if (_looksLikePigeonCastError(e)) {
        final currentUser = _auth.currentUser;
        if (currentUser != null &&
            currentUser.email != null &&
            currentUser.email!.toLowerCase() == safeEmail) {
          firebaseUser = currentUser;
          debugPrint(
              'Recovered Firebase user after plugin cast error during registration.');
        } else {
          _lastAuthError =
              'Account creation had an unexpected Firebase plugin issue. Please try again.';
          debugPrint('Firebase account creation plugin cast failure: $e');
          return false;
        }
      } else {
        _lastAuthError =
            'Could not create account right now. Please check internet and try again.';
        debugPrint('Firebase account creation failed: $e');
        return false;
      }
    }

    if (firebaseUser == null) {
      _lastAuthError = 'Account was not created. Please try again.';
      return false;
    }

    try {
      try {
        await firebaseUser.updateDisplayName(safeFullName);
      } catch (e) {
        debugPrint('Display name update failed (non-fatal): $e');
      }

      final profile = <String, dynamic>{
        'uid': firebaseUser.uid,
        'email': safeEmail,
        'username': safeUsername,
        'username_lower': safeUsernameLower,
        'full_name': safeFullName,
        'role': role,
        'vehicle_type': vehicleType,
        'vehicle_number': vehicleNumber,
        'bus_number': busNumber,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

      await _cloudFirestore.collection('users').doc(firebaseUser.uid).set(
            profile,
            SetOptions(merge: true),
          );

      final passwordHash = DbHelper.hashPassword(password);
      final existingByUid = await _db.getUserByFirebaseUid(firebaseUser.uid);
      if (existingByUid == null) {
        await _db.createUser(
          safeUsername,
          passwordHash,
          role,
          fullName: safeFullName,
          email: safeEmail,
          firebaseUid: firebaseUser.uid,
          busNumber: busNumber,
          vehicleType: vehicleType,
          vehicleNumber: vehicleNumber,
        );
      }

      await _resolveLocalUser(safeUsername);
      await _auth.signOut();
      _currentUser = null;
      notifyListeners();
      return true;
    } on FirebaseException catch (e) {
      _lastAuthError =
          'Account created but profile could not be saved to cloud: ${e.message ?? e.code}';
      debugPrint('Registration cloud profile failure: ${e.code} ${e.message}');
      try {
        await firebaseUser.delete();
      } catch (_) {}
      try {
        await _auth.signOut();
      } catch (_) {}
      return false;
    } catch (e) {
      _lastAuthError =
          'Account setup failed unexpectedly. Please try again.';
      debugPrint('Registration rollback triggered: $e');
      try {
        await firebaseUser.delete();
      } catch (_) {
        // Ignore rollback failures; user creation may already be partially committed.
      }
      try {
        await _auth.signOut();
      } catch (_) {}
      return false;
    }
  }

  Future<bool> linkLegacyAdminToFirebase(String email, String password) async {
    _lastAuthError = null;

    final localUser = _currentUser;
    if (localUser == null || (localUser['role'] as String?) != 'admin') {
      _lastAuthError = 'Only admin users can link a cloud account.';
      return false;
    }

    final localFirebaseUid = (localUser['firebase_uid'] as String?)?.trim() ?? '';
    if (localFirebaseUid.isNotEmpty) {
      _lastAuthError = 'This admin account is already linked to Firebase.';
      return false;
    }

    final safeEmail = email.trim().toLowerCase();
    if (safeEmail.isEmpty || password.isEmpty) {
      _lastAuthError = 'Email and password are required to link a cloud account.';
      return false;
    }

    User? firebaseUser;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: safeEmail,
        password: password,
      );
      firebaseUser = credential.user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        try {
          await _signInWithEmail(safeEmail, password);
          firebaseUser = _auth.currentUser;
        } catch (signInError) {
          _lastAuthError = 'Cloud account exists, but sign-in failed.';
          debugPrint('Legacy admin cloud link sign-in failed: $signInError');
          return false;
        }
      } else {
        _lastAuthError = _mapFirebaseAuthError(e);
        debugPrint('Legacy admin cloud link failed: ${e.code} ${e.message}');
        return false;
      }
    } catch (e) {
      _lastAuthError = 'Could not create the cloud account right now.';
      debugPrint('Legacy admin cloud link failed unexpectedly: $e');
      return false;
    }

    if (firebaseUser == null) {
      _lastAuthError = 'Cloud account link did not complete.';
      return false;
    }

    try {
      await _db.updateUserFirebaseUid(localUser['id'] as int, firebaseUser.uid);

      final updatedUser = Map<String, dynamic>.from(localUser)
        ..['firebase_uid'] = firebaseUser.uid
        ..['email'] = safeEmail;
      _setCurrentUser(updatedUser);

      await _seedFirestoreAdminDocIfNeeded(updatedUser, firebaseUser.uid);
      return true;
    } catch (e) {
      _lastAuthError = 'Firebase account was created, but local linking failed.';
      debugPrint('Legacy admin local link failure: $e');
      return false;
    }
  }

  String _mapFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already in use. Try logging in instead.';
      case 'invalid-email':
        return 'The email address format is invalid.';
      case 'weak-password':
        return 'Password is too weak. Use uppercase, lowercase, number, and special character.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled for this app.';
      case 'network-request-failed':
        return 'Network error while creating account. Please check internet.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return e.message ?? 'Signup failed due to an authentication error.';
    }
  }

  bool _looksLikePigeonCastError(Object error) {
    final text = error.toString();
    return text.contains('PigeonUserDetails') ||
        text.contains('List<Object?>') && text.contains('type cast');
  }

  /// Log out the current user.
  void logout() {
    try {
      _auth.signOut();
    } catch (_) {
      // Ignore sign-out failures when Firebase is not initialized in tests.
    }
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

  Future<Map<String, dynamic>?> _resolveLocalUser(String identifier) async {
    final normalized = identifier.trim();
    if (normalized.contains('@')) {
      final byEmail = await _db.getUserByEmail(normalized.toLowerCase());
      if (byEmail != null) return byEmail;
    }

    final byUsername = await _db.getUserByUsername(normalized);
    if (byUsername != null) return byUsername;

    final byEmail = await _db.getUserByEmail(normalized.toLowerCase());
    return byEmail;
  }

  Future<void> _signInWithEmail(String email, String password) async {
    final current = _auth.currentUser;
    if (current != null) {
      await _auth.signOut();
    }
    await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<Map<String, dynamic>?> _loadCloudUserProfile(String? uid) async {
    if (uid == null || uid.isEmpty) return null;

    try {
      final doc = await _cloudFirestore.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadCloudUserProfileByUsername(
      String username) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    try {
      final query = await _cloudFirestore
          .collection('users')
          .where('username_lower', isEqualTo: normalized)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return query.docs.first.data();
      }

      final legacyQuery = await _cloudFirestore
          .collection('users')
          .where('username', isEqualTo: username.trim())
          .limit(1)
          .get();
      if (legacyQuery.docs.isNotEmpty) {
        return legacyQuery.docs.first.data();
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<Map<String, dynamic>?> _loadCloudUserProfileByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    try {
      final query = await _cloudFirestore
          .collection('users')
          .where('email', isEqualTo: normalized)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return query.docs.first.data();
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<void> _seedFirestoreAdminDocIfNeeded(
    Map<String, dynamic>? user,
    String? firebaseUid,
  ) async {
    if (user == null) return;
    if ((user['role'] as String?) != 'admin') return;

    final uid = (firebaseUid ?? '').trim();
    if (uid.isEmpty) {
      debugPrint('Skipping admin Firestore seeding: no Firebase UID available.');
      return;
    }

    try {
      final adminRef = _cloudFirestore.collection('admins').doc(uid);
      final snapshot = await adminRef.get();
      if (!snapshot.exists || snapshot.data() == null) {
        await adminRef.set({
          'isAdmin': true,
          'seededAt': DateTime.now().millisecondsSinceEpoch,
          'username': (user['username'] as String?) ?? '',
          'email': (user['email'] as String?) ?? '',
          'role': 'admin',
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Admin Firestore self-seed skipped due to error: $e');
    }
  }

  Future<void> _runZeroSegmentCleanupIfNeeded(
    Map<String, dynamic>? user,
  ) async {
    if (user == null) return;
    if ((user['role'] as String?) != 'admin') return;

    try {
      await FirebaseSyncService.instance.cleanupZeroSegmentCollectionTrips();
    } catch (e) {
      debugPrint('Zero-segment Firestore cleanup failed: $e');
    }
  }

  void _setCurrentUser(Map<String, dynamic> user) {
    _currentUser = user;
    _lastActivityTime = DateTime.now();
    notifyListeners();
  }
}
