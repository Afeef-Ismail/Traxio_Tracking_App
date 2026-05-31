import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
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
    final isEmail = normalizedIdentifier.contains('@');

    // ── PRIMARY PATH: email → Firebase Auth sign-in ──────────────────────
    // signInWithEmailAndPassword requires NO Firestore read, so it never hits
    // the permission deadlock that a pre-auth username→email lookup does.
    // After a session exists, users/{uid} and admins/{uid} become readable.
    if (isEmail) {
      final hydrated = await _signInWithEmailAndHydrate(
        normalizedIdentifier.toLowerCase(),
        password,
        passwordHash,
      );
      if (hydrated != null) {
        _setCurrentUser(hydrated);
        await _seedFirestoreAdminDocIfNeeded(
            hydrated, hydrated['firebase_uid'] as String?);
        await _runZeroSegmentCleanupIfNeeded(hydrated);
        return true;
      }
      // Firebase sign-in failed (offline, or a local-only seeded account whose
      // email exists only in SQLite, e.g. admin@traxio.local). Fall through to
      // the local password-hash check below.
    }

    // ── LOCAL PATH: SQLite check (offline, seeded accounts, synced users) ──
    final localUser = await _resolveLocalUser(normalizedIdentifier);
    if (localUser != null && localUser['password_hash'] == passwordHash) {
      _setCurrentUser(localUser);
      // Silent auto-link: if this row has no Firebase UID but its stored email
      // + password match a real Firebase account, establish the session and
      // backfill the UID so Firestore sync works.
      final hydratedUser =
          await _autoLinkFirebaseUidIfPossible(localUser, password);
      await _seedFirestoreAdminDocIfNeeded(
          hydratedUser, hydratedUser['firebase_uid'] as String?);
      await _runZeroSegmentCleanupIfNeeded(hydratedUser);
      return true;
    }

    // ── RECOVERY PATH: account in Firebase Auth but no local row ──────────
    // (e.g. a fresh install wiped the local DB). Tries email/synthetic sign-in
    // and rebuilds the local row from the Firestore profile.
    final recovered = await _recoverLocalUserFromFirebase(
      normalizedIdentifier,
      password,
    );
    if (recovered != null) {
      _setCurrentUser(recovered);
      await _seedFirestoreAdminDocIfNeeded(
          recovered, recovered['firebase_uid'] as String?);
      await _runZeroSegmentCleanupIfNeeded(recovered);
      return true;
    }

    _lastAuthError = localUser != null
        ? 'Invalid password.'
        : 'No account found for "$normalizedIdentifier". '
            'Try your email address.';
    return false;
  }

  /// Signs into Firebase Auth with [email] + [password] (no Firestore read
  /// required), then finds-or-rebuilds the local SQLite row from the Firestore
  /// users/{uid} profile. Returns the local user map on success, or null if the
  /// Firebase sign-in itself failed (wrong password, no such account, offline).
  Future<Map<String, dynamic>?> _signInWithEmailAndHydrate(
    String email,
    String password,
    String passwordHash,
  ) async {
    try {
      await _signInWithEmail(email, password);
    } on FirebaseAuthException catch (e) {
      debugPrint('Email sign-in failed for "$email": ${e.code}');
      return null;
    } catch (e) {
      if (_looksLikePigeonCastError(e)) {
        final recovered = _auth.currentUser;
        if (recovered == null ||
            recovered.email?.toLowerCase() != email.toLowerCase()) {
          debugPrint('Email sign-in pigeon cast with no recoverable session.');
          return null;
        }
        // Session is valid despite the plugin cast error — continue.
      } else {
        debugPrint('Email sign-in unexpected error for "$email": $e');
        return null;
      }
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;

    final cloudProfile = await _loadCloudUserProfile(uid);

    // ── Resolve the role from the strongest available signal ──────────────
    // Priority: admin-email allowlist (survives a Firestore wipe) → the
    // admins/{uid} Firestore doc → the cloud users/{uid} profile role →
    // default 'driver'. This is what previously regressed: with Firestore
    // cleared, an admin had no signal and was rebuilt as a driver.
    String resolvedRole = (cloudProfile?['role'] as String?) ?? 'driver';
    if (AppConstants.isAdminEmail(email) || await _isAdminInFirestore(uid)) {
      resolvedRole = 'admin';
    }

    Map<String, dynamic>? localRow =
        await _db.getUserByFirebaseUid(uid) ?? await _resolveLocalUser(email);

    if (localRow == null) {
      // Rebuild a local row from the cloud profile (or minimal defaults).
      final cloudUsername = (cloudProfile?['username'] as String?)?.trim();
      final resolvedUsername =
          (cloudUsername != null && cloudUsername.isNotEmpty)
              ? cloudUsername
              : await _deriveUniqueUsername(email);
      try {
        await _db.createUser(
          resolvedUsername,
          passwordHash,
          resolvedRole,
          fullName: (cloudProfile?['full_name'] as String?) ?? '',
          email: email,
          firebaseUid: uid,
          busNumber: (cloudProfile?['bus_number'] as String?) ?? '',
          vehicleType: (cloudProfile?['vehicle_type'] as String?) ?? '',
          vehicleNumber: (cloudProfile?['vehicle_number'] as String?) ?? '',
        );
      } catch (e) {
        debugPrint('Email-login local row rebuild failed: $e');
      }
      localRow =
          await _db.getUserByFirebaseUid(uid) ?? await _resolveLocalUser(email);
    } else {
      // Ensure the existing row carries the Firebase UID.
      final existingUid = (localRow['firebase_uid'] as String?)?.trim() ?? '';
      final localId = localRow['id'];
      if (existingUid.isEmpty && localId is int) {
        try {
          await _db.updateUserFirebaseUid(localId, uid);
          localRow = await _db.getUserByFirebaseUid(uid) ?? localRow;
        } catch (e) {
          debugPrint('Email-login UID backfill failed: $e');
        }
      }
    }

    // Promote the local row to admin if our resolved role says so but the
    // stored row doesn't (e.g. it was rebuilt as a driver before, or the
    // admins doc/allowlist now applies). Never downgrade an existing admin.
    if (localRow != null) {
      final storedRole = (localRow['role'] as String?) ?? 'driver';
      final effectiveRole =
          (storedRole == 'admin' || resolvedRole == 'admin') ? 'admin' : storedRole;
      if (effectiveRole != storedRole) {
        final localId = localRow['id'];
        if (localId is int) {
          try {
            await _db.updateUserRole(localId, effectiveRole);
          } catch (e) {
            debugPrint('Email-login role update failed: $e');
          }
        }
        localRow = Map<String, dynamic>.from(localRow)..['role'] = effectiveRole;
      }
    }

    return localRow;
  }

  /// Reads the admins/{uid} Firestore doc to confirm admin status. Returns
  /// false on any error (offline, permission, missing doc).
  Future<bool> _isAdminInFirestore(String uid) async {
    if (uid.isEmpty) return false;
    try {
      final doc = await _cloudFirestore.collection('admins').doc(uid).get();
      if (!doc.exists) return false;
      final data = doc.data();
      return data != null && data['isAdmin'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Derives a unique SQLite username from an email local-part, since the
  /// signup form no longer asks for a username but the schema requires one.
  Future<String> _deriveUniqueUsername(String email) async {
    final base = email.split('@').first.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final seed = base.isEmpty ? 'user' : base;
    var candidate = seed;
    var suffix = 0;
    while (await _db.getUserByUsernameInsensitive(candidate) != null) {
      suffix++;
      candidate = '$seed$suffix';
    }
    return candidate;
  }

  /// Recovery path for when a user exists in Firebase Auth but has no local
  /// SQLite row (e.g. a fresh install wiped the local DB). Attempts to sign
  /// into Firebase using the supplied [identifier] + [password], then rebuilds
  /// the local SQLite row from the Firestore users/{uid} profile.
  ///
  /// Email resolution order for sign-in:
  ///   1. If [identifier] is itself an email, use it directly.
  ///   2. Look up the Firestore users collection by username to get the real
  ///      registration email.
  ///   3. Fall back to the synthetic "username@traxio.app" email.
  ///
  /// Returns the rebuilt local user map on success, or null if recovery is not
  /// possible (no matching account, wrong password, offline, etc.).
  Future<Map<String, dynamic>?> _recoverLocalUserFromFirebase(
    String identifier,
    String password,
  ) async {
    if (password.isEmpty) return null;

    // Build the ordered list of candidate emails to try signing in with.
    final candidateEmails = <String>[];
    if (identifier.contains('@')) {
      candidateEmails.add(identifier.toLowerCase());
    }

    // Try to find the real email via the Firestore profile (by username).
    Map<String, dynamic>? cloudProfile;
    if (!identifier.contains('@')) {
      cloudProfile = await _loadCloudUserProfileByUsername(identifier);
      final profileEmail =
          (cloudProfile?['email'] as String?)?.trim().toLowerCase() ?? '';
      if (profileEmail.isNotEmpty && !candidateEmails.contains(profileEmail)) {
        candidateEmails.add(profileEmail);
      }
      // Synthetic fallback.
      final synthetic = '${identifier.toLowerCase()}@traxio.app';
      if (!candidateEmails.contains(synthetic)) {
        candidateEmails.add(synthetic);
      }
    }

    if (candidateEmails.isEmpty) return null;

    User? firebaseUser;
    for (final email in candidateEmails) {
      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        firebaseUser = credential.user;
        if (firebaseUser != null) {
          debugPrint('Recovery: signed into Firebase via "$email".');
          break;
        }
      } on FirebaseAuthException catch (e) {
        // user-not-found / wrong-password / invalid-credential → try next.
        debugPrint('Recovery sign-in attempt failed for "$email": ${e.code}');
        continue;
      } catch (e) {
        if (_looksLikePigeonCastError(e)) {
          final recovered = _auth.currentUser;
          if (recovered != null &&
              recovered.email != null &&
              recovered.email!.toLowerCase() == email) {
            firebaseUser = recovered;
            debugPrint(
                'Recovery: recovered session via "$email" after plugin cast error.');
            break;
          }
        }
        debugPrint('Recovery sign-in unexpected error for "$email": $e');
        continue;
      }
    }

    if (firebaseUser == null) {
      return null;
    }

    final uid = firebaseUser.uid;

    // Prefer the authoritative Firestore profile (now readable with a session).
    final profile =
        await _loadCloudUserProfile(uid) ?? cloudProfile ?? <String, dynamic>{};

    final resolvedUsername = (profile['username'] as String?)?.trim().isNotEmpty == true
        ? (profile['username'] as String).trim()
        : (identifier.contains('@') ? identifier.split('@').first : identifier);
    final resolvedEmail = (profile['email'] as String?)?.trim().isNotEmpty == true
        ? (profile['email'] as String).trim()
        : (firebaseUser.email ?? '');
    var resolvedRole = (profile['role'] as String?) ?? 'driver';
    // Admin signal that survives a Firestore wipe: the email allowlist or the
    // admins/{uid} doc. Otherwise an admin recovered on a fresh install would
    // be rebuilt as a driver and land on the wrong UI.
    if (AppConstants.isAdminEmail(resolvedEmail) ||
        AppConstants.isAdminEmail(firebaseUser.email) ||
        await _isAdminInFirestore(uid)) {
      resolvedRole = 'admin';
    }

    try {
      // Rebuild the local row only if one doesn't already exist for this UID.
      final existingByUid = await _db.getUserByFirebaseUid(uid);
      if (existingByUid == null) {
        await _db.createUser(
          resolvedUsername,
          DbHelper.hashPassword(password),
          resolvedRole,
          fullName: (profile['full_name'] as String?) ?? '',
          email: resolvedEmail,
          firebaseUid: uid,
          busNumber: (profile['bus_number'] as String?) ?? '',
          vehicleType: (profile['vehicle_type'] as String?) ?? '',
          vehicleNumber: (profile['vehicle_number'] as String?) ?? '',
        );
        debugPrint('Recovery: rebuilt local SQLite row for "$resolvedUsername".');
      }
    } catch (e) {
      debugPrint('Recovery: local row rebuild failed: $e');
      // Even if the rebuild failed, the Firebase session is valid; fall through
      // and return whatever local row we can resolve.
    }

    final rebuilt = await _resolveLocalUser(resolvedUsername) ??
        await _resolveLocalUser(resolvedEmail);
    return rebuilt;
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

    // Short-circuit ONLY when a Firebase Auth session is already active — that
    // live session (request.auth) is what Firestore rules actually require.
    // We must NOT skip merely because firebase_uid is already saved in SQLite:
    // on a repeat login the UID is present but _auth.currentUser is null, so
    // skipping here left the admin with no Firebase session and every
    // Firestore read/write (incl. delete) failed with permission-denied.
    final activeUid = _auth.currentUser?.uid;
    if (activeUid != null && activeUid.isNotEmpty) {
      final localId = localUser['id'];
      if (localId is int && existingUid != activeUid) {
        // Live session UID drifted from SQLite — reconcile to the session.
        try {
          await _db.updateUserFirebaseUid(localId, activeUid);
        } catch (_) {}
        final synced = Map<String, dynamic>.from(localUser)
          ..['firebase_uid'] = activeUid;
        _setCurrentUser(synced);
        return synced;
      }
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
    String username = '',
    required String email,
    required String password,
    required String role,
    String vehicleType = '',
    String vehicleNumber = '',
    String busNumber = '',
  }) async {
    _lastAuthError = null;
    final safeEmail = email.trim().toLowerCase();
    final safeFullName = fullName.trim();

    if (safeFullName.isEmpty || safeEmail.isEmpty) {
      _lastAuthError = 'Full name and email are required.';
      return false;
    }

    if (!isStrongPassword(password)) {
      _lastAuthError =
          'Password must contain at least 1 uppercase, 1 lowercase, 1 number, 1 special character, and be at least 6 characters long.';
      return false;
    }

    // The signup form no longer collects a username. Keep an internal username
    // (required by the SQLite schema and legacy code) by deriving a unique one
    // from the email local-part when none is supplied.
    var safeUsername = username.trim();
    if (safeUsername.isEmpty) {
      safeUsername = await _deriveUniqueUsername(safeEmail);
    }
    final safeUsernameLower = safeUsername.toLowerCase();

    final existingUsername =
        await _db.getUserByUsernameInsensitive(safeUsernameLower);
    if (existingUsername != null) {
      // Derived usernames are guaranteed unique; an explicit one may collide.
      if (username.trim().isEmpty) {
        safeUsername = await _deriveUniqueUsername(safeEmail);
      } else {
        _lastAuthError = 'Username "$safeUsername" is already taken.';
        return false;
      }
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
      if (e.code == 'email-already-in-use') {
        // A Firebase Auth account already exists for this email (e.g. the
        // local SQLite row was wiped on reinstall, or a prior registration
        // half-completed). Sign in to recover the existing UID and continue
        // creating a fresh local row under it, completing registration.
        try {
          final credential = await _auth.signInWithEmailAndPassword(
            email: safeEmail,
            password: password,
          );
          firebaseUser = credential.user;
          debugPrint(
              'Registration: email already in use — signed into existing Firebase account.');
        } on FirebaseAuthException catch (signInErr) {
          _lastAuthError = (signInErr.code == 'wrong-password' ||
                  signInErr.code == 'invalid-credential')
              ? 'This email is already registered. Please log in with the correct password.'
              : _mapFirebaseAuthError(signInErr);
          debugPrint(
              'Registration sign-in fallback failed: ${signInErr.code} ${signInErr.message}');
          return false;
        } catch (signInErr) {
          if (_looksLikePigeonCastError(signInErr)) {
            final recovered = _auth.currentUser;
            if (recovered != null &&
                recovered.email != null &&
                recovered.email!.toLowerCase() == safeEmail) {
              firebaseUser = recovered;
              debugPrint(
                  'Registration: recovered existing account after plugin cast error.');
            } else {
              _lastAuthError =
                  'Could not sign into the existing account. Please try logging in.';
              debugPrint(
                  'Registration sign-in fallback plugin cast with no recoverable session: $signInErr');
              return false;
            }
          } else {
            _lastAuthError =
                'Could not sign into the existing account. Please try logging in.';
            debugPrint('Registration sign-in fallback error: $signInErr');
            return false;
          }
        }
      } else {
        _lastAuthError = _mapFirebaseAuthError(e);
        debugPrint('Firebase account creation failed: ${e.code} ${e.message}');
        return false;
      }
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
