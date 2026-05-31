import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../database/db_helper.dart';
import '../models/segment_model.dart';
import '../models/trip_model.dart';

class FirebaseSyncService {
  FirebaseSyncService._();

  static final FirebaseSyncService instance = FirebaseSyncService._();
  bool _zeroSegmentCleanupDone = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Connectivity _connectivity = Connectivity();
  final DbHelper _db = DbHelper();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  /// Initialize connectivity listeners for offline queue retry
  void initConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (result) {
        if (result != ConnectivityResult.none) {
          // Retry failed syncs when connection is restored
          retryFailedSyncs();
        }
      },
    );
  }

  /// Dispose of connectivity listener
  void dispose() {
    _connectivitySubscription?.cancel();
  }

  Future<void> cleanupZeroSegmentCollectionTrips() async {
    if (_zeroSegmentCleanupDone) {
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    _zeroSegmentCleanupDone = true;

    try {
      final snapshot = await _firestore
          .collection('collectionTrips')
          .where('total_segments', isEqualTo: 0)
          .get();

      var cleanedCount = 0;
      for (final doc in snapshot.docs) {
        final tripId = doc.id;
        final deleted = await deletePublishedCollectionTrip(tripId);
        if (deleted) {
          cleanedCount++;
        }
      }

      print('Zero-segment Firestore cleanup complete: cleaned $cleanedCount docs.');
    } catch (e) {
      print('Zero-segment Firestore cleanup skipped due to error: $e');
    }
  }

  Future<bool> syncBenchmarkTrip(String tripId) async {
    // Explicit auth guard: Firestore rules require request.auth != null, so a
    // write with no Firebase Auth session is silently rejected with
    // permission-denied. Surface it clearly and queue for later retry.
    if (FirebaseAuth.instance.currentUser == null) {
      print('Firestore sync skipped: user not authenticated');
      await _db.addToSyncQueue(tripId, 'benchmark',
          'User not authenticated; queued for retry');
      await _db.setTripSummarySyncStatus(tripId, 'failed');
      return false;
    }

    if (!await _canSync()) {
      await _db.addToSyncQueue(tripId, 'benchmark',
          'Connection unavailable; queued for retry');
      await _db.setTripSummarySyncStatus(tripId, 'failed');
      return false;
    }

    try {
      final summary = await _db.getTripSummary(tripId);
      if (summary == null) {
        return false;
      }

      final segments = await _db.getSegmentsForTrip(tripId);
      final scores = await _db.getScoresForTrip(tripId);
      final featuresBySegment = await _db.getFeaturesBySegmentForTrip(tripId);

      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('trips')
          .doc(tripId)
          .set({
        'tripId': summary.tripId,
        'mode': 'benchmark',
        'summary': _summaryToMap(summary),
        'syncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _writeUserSegments(tripId, segments,
          featuresBySegment: featuresBySegment);
      await _writeUserScores(tripId, scores);
      await _writePublicBenchmarkTrip(summary, segments, scores,
          featuresBySegment: featuresBySegment);
      await _db.setTripSummarySyncStatus(tripId, 'synced');
      
      // Remove from queue on successful sync
      await _db.removeFromSyncQueue(tripId, 'benchmark');
      return true;
    } catch (e) {
      // Queue for retry on failure
      await _db.addToSyncQueue(tripId, 'benchmark', e.toString());
      await _db.updateSyncQueueError(tripId, 'benchmark', e.toString());
      await _db.setTripSummarySyncStatus(tripId, 'failed');
      return false;
    }
  }

  Future<bool> syncCollectionTrip(String tripId) async {
    // Explicit auth guard: Firestore rules require request.auth != null, so a
    // write with no Firebase Auth session is silently rejected with
    // permission-denied. Surface it clearly and queue for later retry.
    if (FirebaseAuth.instance.currentUser == null) {
      print('Firestore sync skipped: user not authenticated');
      await _db.addToSyncQueue(tripId, 'collection',
          'User not authenticated; queued for retry');
      await _db.setDataCollectionTripSyncStatus(tripId, 'failed');
      return false;
    }

    if (!await _canSync()) {
      await _db.addToSyncQueue(tripId, 'collection',
          'Connection unavailable; queued for retry');
      await _db.setDataCollectionTripSyncStatus(tripId, 'failed');
      return false;
    }

    try {
      final tripMap = await _db.getDataCollectionTripById(tripId);
      if (tripMap == null) {
        return false;
      }

      final totalSegments = (tripMap['total_segments'] as num?)?.toInt() ?? 0;
      if (totalSegments == 0) {
        await _db.setDataCollectionTripSyncStatus(tripId, 'synced');
        await _db.removeFromSyncQueue(tripId, 'collection');
        return true;
      }

      final segments = await _db.getSegmentsForTrip(tripId);
      final featureRows = await _db.getSegmentsWithFeaturesForTrip(tripId);
      final featuresBySegment = await _db.getFeaturesBySegmentForTrip(tripId);

      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('collectionTrips')
          .doc(tripId)
          .set({
        'tripId': tripId,
        'mode': 'collection',
        'trip': tripMap,
        'syncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _writeUserSegments(tripId, segments,
          featuresBySegment: featuresBySegment);
      await _writePublicCollectionTrip(tripMap, featureRows);
      await _db.setDataCollectionTripSyncStatus(tripId, 'synced');
      
      // Remove from queue on successful sync
      await _db.removeFromSyncQueue(tripId, 'collection');
      return true;
    } catch (e) {
      // Queue for retry on failure
      await _db.addToSyncQueue(tripId, 'collection', e.toString());
      await _db.updateSyncQueueError(tripId, 'collection', e.toString());
      await _db.setDataCollectionTripSyncStatus(tripId, 'failed');
      return false;
    }
  }

  Future<void> retryFailedSyncs() async {
    if (!await _canSync()) {
      return;
    }

    try {
      final queuedTrips = await _db.getSyncQueue();
      
      for (final item in queuedTrips) {
        final tripId = item['trip_id'] as String;
        final tripType = item['trip_type'] as String;
        final attempts = (item['attempts'] as int?) ?? 0;

        // Skip if max attempts exceeded (5 retries)
        if (attempts >= 5) {
          continue;
        }

        // Retry the appropriate sync type
        bool success = false;
        if (tripType == 'benchmark') {
          success = await syncBenchmarkTrip(tripId);
        } else if (tripType == 'collection') {
          success = await syncCollectionTrip(tripId);
        }

        // Attempts are tracked in sync methods when failures occur.
        if (!success) {
          continue;
        }
      }
    } catch (_) {
      // Silent failure; will retry on next connectivity change
    }
  }

  Future<bool> _canSync() async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }

    final connectivityResult = await _connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _writeUserSegments(
    String tripId,
    List<Segment> segments, {
    Map<int, Map<String, double>>? featuresBySegment,
  }) async {
    final tripRef = _firestore
        .collection('users')
        .doc(_auth.currentUser!.uid)
        .collection('trips')
        .doc(tripId)
        .collection('segments');

    final batch = _firestore.batch();
    for (final segment in segments) {
      final segmentId = segment.id?.toString() ?? segment.segmentIndex.toString();
      final features =
          segment.id == null ? null : featuresBySegment?[segment.id!];
      batch.set(tripRef.doc(segmentId),
          _segmentToMap(segment, features: features), SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> _writeUserScores(String tripId, List<SegmentScore> scores) async {
    final scoreRef = _firestore
        .collection('users')
        .doc(_auth.currentUser!.uid)
        .collection('trips')
        .doc(tripId)
        .collection('scores');

    final batch = _firestore.batch();
    for (final score in scores) {
      final scoreId = score.id?.toString() ?? score.segmentId.toString();
      batch.set(scoreRef.doc(scoreId), _scoreToMap(score), SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> _writePublicBenchmarkTrip(
    TripSummary summary,
    List<Segment> segments,
    List<SegmentScore> scores, {
    Map<int, Map<String, double>>? featuresBySegment,
  }) async {
    final tripRef = _firestore.collection('benchmarkTrips').doc(summary.tripId);
    await tripRef.set({
      'trip_id': summary.tripId,
      'start_time': summary.startTime.millisecondsSinceEpoch,
      'end_time': summary.endTime.millisecondsSinceEpoch,
      'total_segments': summary.totalSegments,
      'valid_segments': summary.validSegments,
      'cluster0_matches': summary.cluster0Matches,
      'cluster1_matches': summary.cluster1Matches,
      'cluster0_percentage': summary.cluster0Percentage,
      'cluster1_percentage': summary.cluster1Percentage,
      'avg_deviation_plain': summary.avgDeviationPlain,
      'avg_deviation_uphill': summary.avgDeviationUphill,
      'avg_deviation_downhill': summary.avgDeviationDownhill,
      'overall_avg_deviation': summary.overallAvgDeviation,
      'plain_segments': summary.plainSegments,
      'uphill_segments': summary.uphillSegments,
      'downhill_segments': summary.downhillSegments,
      'user_id': summary.userId,
      'coaching_report': summary.coachingReport,
      'score': summary.score,
      'vehicle_type': summary.vehicleType,
      'driver_name': summary.driverName,
      'bus_number': summary.busNumber,
      'ownerUid': _auth.currentUser!.uid,
      'syncedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final segmentBatch = _firestore.batch();
    final segmentRef = tripRef.collection('segments');
    for (final segment in segments) {
      final segmentId = segment.id?.toString() ?? segment.segmentIndex.toString();
      final features =
          segment.id == null ? null : featuresBySegment?[segment.id!];
      segmentBatch.set(segmentRef.doc(segmentId),
          _segmentToMap(segment, features: features), SetOptions(merge: true));
    }
    await segmentBatch.commit();

    final scoreBatch = _firestore.batch();
    final scoreRef = tripRef.collection('scores');
    for (final score in scores) {
      final scoreId = score.id?.toString() ?? score.segmentId.toString();
      scoreBatch.set(scoreRef.doc(scoreId), _scoreToMap(score), SetOptions(merge: true));
    }
    await scoreBatch.commit();
  }

  Future<void> _writePublicCollectionTrip(
    Map<String, dynamic> tripMap,
    List<Map<String, dynamic>> rows,
  ) async {
    final tripId = tripMap['trip_id']?.toString();
    if (tripId == null || tripId.isEmpty) {
      return;
    }

    final tripRef = _firestore.collection('collectionTrips').doc(tripId);
    await tripRef.set({
      ...tripMap,
      'ownerUid': _auth.currentUser!.uid,
      'syncedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final rowBatch = _firestore.batch();
    final rowRef = tripRef.collection('rows');
    for (final row in rows) {
      final segmentIndex = row['segment_index']?.toString() ??
          row['segment_id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString();
      rowBatch.set(rowRef.doc(segmentIndex), row, SetOptions(merge: true));
    }
    await rowBatch.commit();
  }

  Future<List<TripSummary>> getPublishedBenchmarkTrips() async {
    final snapshot = await _firestore
        .collection('benchmarkTrips')
        .orderBy('start_time', descending: true)
        .get();
    if (snapshot.docs.isNotEmpty) {
      return snapshot.docs.map((doc) => _benchmarkTripFromMap(doc.data())).toList();
    }

    try {
      final mirrorSnapshot = await _firestore.collectionGroup('trips').get();
      final trips = mirrorSnapshot.docs
          .map((doc) => doc.data())
          .where((data) => (data['mode'] as String?) == 'benchmark')
          .map(_benchmarkTripFromUserMirror)
          .toList();
      trips.sort((a, b) => b.startTime.compareTo(a.startTime));
      return trips;
    } catch (_) {
      return [];
    }
  }

  Future<List<TripSummary>> getCurrentUserBenchmarkTrips() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('trips')
        .orderBy('syncedAt', descending: true)
        .get();

    final trips = <TripSummary>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final summary = data['summary'];
      if (summary is Map) {
        trips.add(_benchmarkTripFromMap(Map<String, dynamic>.from(summary as Map)));
      }
    }
    return trips;
  }

  Future<TripSummary?> getPublishedBenchmarkTrip(String tripId) async {
    final doc = await _firestore.collection('benchmarkTrips').doc(tripId).get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return _benchmarkTripFromMap(doc.data()!);
  }

  Future<List<Segment>> getPublishedBenchmarkSegments(String tripId) async {
    final snapshot = await _firestore
        .collection('benchmarkTrips')
        .doc(tripId)
        .collection('segments')
        .orderBy('segmentIndex')
        .get();
    return snapshot.docs.map((doc) => _segmentFromMap(doc.data(), doc.id)).toList();
  }

  Future<List<SegmentScore>> getPublishedBenchmarkScores(String tripId) async {
    final snapshot = await _firestore
        .collection('benchmarkTrips')
        .doc(tripId)
        .collection('scores')
        .get();
    return snapshot.docs.map((doc) => _scoreFromMap(doc.data(), doc.id)).toList();
  }

  Future<List<DataCollectionTrip>> getPublishedCollectionTrips() async {
    final snapshot = await _firestore
        .collection('collectionTrips')
        .orderBy('start_time', descending: true)
        .get();
    if (snapshot.docs.isNotEmpty) {
      return snapshot.docs.map((doc) => _collectionTripFromMap(doc.data())).toList();
    }

    try {
      final mirrorSnapshot = await _firestore.collectionGroup('collectionTrips').get();
      final trips = mirrorSnapshot.docs
          .map((doc) => _collectionTripFromUserMirror(doc.data()))
          .toList();
      trips.sort((a, b) => b.startTime.compareTo(a.startTime));
      return trips;
    } catch (_) {
      return [];
    }
  }

  Future<List<DataCollectionTrip>> getCurrentUserCollectionTrips() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('collectionTrips')
        .orderBy('syncedAt', descending: true)
        .get();

    final trips = <DataCollectionTrip>[];
    for (final doc in snapshot.docs) {
      trips.add(_collectionTripFromUserMirror(doc.data()));
    }
    return trips;
  }

  Future<List<Map<String, dynamic>>> getPublishedCollectionTripRows(String tripId) async {
    final snapshot = await _firestore
        .collection('collectionTrips')
        .doc(tripId)
        .collection('rows')
        .orderBy('segment_index')
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Future<bool> deletePublishedBenchmarkTrip(String tripId) async {
    try {
      final tripRef = _firestore.collection('benchmarkTrips').doc(tripId);

      // Resolve the owner before deleting the public doc so we can clean up the
      // user-scoped tree at users/{uid}/trips/{tripId} (+ segments/ scores/).
      final ownerUid = await _resolveOwnerUid('benchmarkTrips', tripId);

      // Delete subcollections in batches of 500 before removing the parent doc.
      await _deleteCollectionInBatches(tripRef.collection('segments'));
      await _deleteCollectionInBatches(tripRef.collection('scores'));

      // Delete the user-scoped trip tree (the per-user mirror at
      // users/{uid}/trips/{tripId} with its segments/ and scores/).
      try {
        await _deleteUserTripTree(ownerUid, tripId);
      } catch (e) {
        print('Warning: Failed to delete user-scoped trips tree: $e');
      }

      // Sweep any other user mirrors that match this tripId, deleting each
      // matched doc's subcollections too (a plain doc delete leaves them).
      final mirrorSnapshot = await _firestore.collectionGroup('trips').get();
      for (final doc in mirrorSnapshot.docs) {
        final data = doc.data();
        final summary = data['summary'];
        final mirrorTripId = summary is Map
            ? (summary['tripId'] ?? summary['trip_id'])?.toString()
            : (data['tripId'] ?? data['trip_id'])?.toString();
        if (mirrorTripId == tripId) {
          try {
            await _deleteCollectionInBatches(doc.reference.collection('segments'));
            await _deleteCollectionInBatches(doc.reference.collection('scores'));
          } catch (e) {
            print('Warning: Failed to delete mirror subcollections: $e');
          }
          await doc.reference.delete();
        }
      }

      // Delete the trip itself
      await tripRef.delete();
      await _db.deleteTripSummary(tripId);
      return true;
    } on FirebaseException catch (e, st) {
      // Surface the specific Firestore error code so auth failures
      // (permission-denied) are distinguishable from not-found etc.
      print(
          'FirebaseSyncService.deletePublishedBenchmarkTrip Firestore error: '
          'code=${e.code} message=${e.message}');
      if (e.code == 'permission-denied') {
        print('Hint: admin Firestore rules require an admins/{uid} doc; the '
            'signed-in admin may not be linked/seeded in Firebase Auth.');
      }
      try {
        print(st);
      } catch (_) {}
      return false;
    } catch (e, st) {
      // Log the error for debugging (visible in `flutter run` output)
      try {
        // ignore: avoid_print
        print('FirebaseSyncService.deletePublishedBenchmarkTrip error: $e');
        // ignore: avoid_print
        print(st);
      } catch (_) {}
      return false;
    }
  }

  Future<bool> deletePublishedCollectionTrip(String tripId) async {
    try {
      final tripRef = _firestore.collection('collectionTrips').doc(tripId);

      // Resolve the owner before deleting the public doc (we need its
      // ownerUid field to locate the user-scoped mirror tree).
      final ownerUid = await _resolveOwnerUid('collectionTrips', tripId);

      // Step 1: Delete subcollection rows in batches of 500.
      try {
        await _deleteCollectionInBatches(tripRef.collection('rows'));
      } catch (e) {
        print('Warning: Failed to delete public rows: $e');
        // Continue anyway - try to delete the trip itself
      }

      // Step 2: Delete the user-scoped trip tree. Collection sync writes
      // segments to users/{uid}/trips/{tripId}/segments (via _writeUserSegments)
      // AND a doc at users/{uid}/collectionTrips/{tripId}. Both must go.
      try {
        await _deleteUserTripTree(ownerUid, tripId);
      } catch (e) {
        print('Warning: Failed to delete user-scoped trips tree: $e');
      }

      // Step 3: Try to delete user-scoped collectionTrips mirrors.
      try {
        final mirrorSnapshot = await _firestore.collectionGroup('collectionTrips').get();
        final mirrorBatch = _firestore.batch();
        int deleteCount = 0;
        for (final doc in mirrorSnapshot.docs) {
          final data = doc.data();
          final mirrorTripId = (data['tripId'] ?? data['trip_id'])?.toString();
          if (mirrorTripId == tripId) {
            mirrorBatch.delete(doc.reference);
            deleteCount++;
          }
        }
        if (deleteCount > 0) {
          await mirrorBatch.commit();
        }
      } catch (e) {
        print('Warning: Failed to delete mirrors (non-critical): $e');
        // Continue - mirrors will eventually be cleaned up or orphaned
      }

      // Step 4: Delete the main public collection trip doc
      await tripRef.delete();
      
      // Step 5: Clean up local database
      await _db.deleteDataCollectionTrip(tripId);
      
      return true;
    } on FirebaseException catch (e, st) {
      // Surface the specific Firestore error code so auth failures
      // (permission-denied) are distinguishable from not-found etc.
      print(
          'FirebaseSyncService.deletePublishedCollectionTrip Firestore error: '
          'code=${e.code} message=${e.message}');
      if (e.code == 'permission-denied') {
        print('Hint: admin Firestore rules require an admins/{uid} doc; the '
            'signed-in admin may not be linked/seeded in Firebase Auth.');
      }
      try {
        print(st);
      } catch (_) {}
      return false;
    } catch (e, st) {
      // Log the error for debugging (visible in `flutter run` output)
      try {
        // ignore: avoid_print
        print('FirebaseSyncService.deletePublishedCollectionTrip error: $e');
        // ignore: avoid_print
        print(st);
      } catch (_) {}
      return false;
    }
  }

  /// Deletes a user-scoped trip document and all of its subcollections.
  /// Collection trips write segments to users/{uid}/trips/{tripId}/segments via
  /// _writeUserSegments, and benchmark trips additionally write a summary doc
  /// there plus segments/ and scores/. Deleting the parent doc does NOT remove
  /// its subcollections in Firestore, so they must be deleted explicitly.
  Future<void> _deleteUserTripTree(String ownerUid, String tripId) async {
    if (ownerUid.isEmpty || tripId.isEmpty) return;
    final tripDocRef = _firestore
        .collection('users')
        .doc(ownerUid)
        .collection('trips')
        .doc(tripId);
    await _deleteCollectionInBatches(tripDocRef.collection('segments'));
    await _deleteCollectionInBatches(tripDocRef.collection('scores'));
    await tripDocRef.delete();
  }

  /// Resolves the ownerUid stamped on a public trip doc (benchmarkTrips or
  /// collectionTrips). Returns the current signed-in uid as a fallback so a
  /// self-owned trip is still cleaned up even if the field is missing.
  Future<String> _resolveOwnerUid(
    String collection,
    String tripId,
  ) async {
    try {
      final doc = await _firestore.collection(collection).doc(tripId).get();
      final owner = (doc.data()?['ownerUid'] as String?)?.trim() ?? '';
      if (owner.isNotEmpty) return owner;
    } catch (_) {
      // Ignore and fall back to the current user below.
    }
    return _auth.currentUser?.uid ?? '';
  }

  Future<void> _deleteCollectionInBatches(
    Query<Map<String, dynamic>> query,
  ) async {
    while (true) {
      final snapshot = await query.limit(500).get();
      if (snapshot.docs.isEmpty) {
        return;
      }

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < 500) {
        return;
      }
    }
  }

  Map<String, dynamic> _summaryToMap(TripSummary summary) {
    return {
      'tripId': summary.tripId,
      'startTime': Timestamp.fromDate(summary.startTime),
      'endTime': Timestamp.fromDate(summary.endTime),
      'totalSegments': summary.totalSegments,
      'validSegments': summary.validSegments,
      'cluster0Matches': summary.cluster0Matches,
      'cluster1Matches': summary.cluster1Matches,
      'cluster0Percentage': summary.cluster0Percentage,
      'cluster1Percentage': summary.cluster1Percentage,
      'avgDeviationPlain': summary.avgDeviationPlain,
      'avgDeviationUphill': summary.avgDeviationUphill,
      'avgDeviationDownhill': summary.avgDeviationDownhill,
      'overallAvgDeviation': summary.overallAvgDeviation,
      'plainSegments': summary.plainSegments,
      'uphillSegments': summary.uphillSegments,
      'downhillSegments': summary.downhillSegments,
      'userId': summary.userId,
      'coachingReport': summary.coachingReport,
      'score': summary.score,
      'vehicleType': summary.vehicleType,
      'driverName': summary.driverName,
      'busNumber': summary.busNumber,
    };
  }

  Map<String, dynamic> _segmentToMap(
    Segment segment, {
    Map<String, double>? features,
  }) {
    return {
      'id': segment.id,
      'tripId': segment.tripId,
      'mode': segment.mode,
      'segmentIndex': segment.segmentIndex,
      'startTime': segment.startTime,
      'endTime': segment.endTime,
      'terrain': segment.terrain,
      'distance': segment.distance,
      'startLat': segment.startLat,
      'startLon': segment.startLon,
      'endLat': segment.endLat,
      'endLon': segment.endLon,
      'startAltitude': segment.startAltitude,
      'endAltitude': segment.endAltitude,
      'isValid': segment.isValid,
      'nearestLandmark': segment.nearestLandmark,
      // Merge the full 120-feature set so cloud segment docs match the CSV
      // export column-for-column. Without this, segment docs carried only the
      // 16 summary fields and all feature columns were lost on sync.
      ...?features,
    };
  }

  Map<String, dynamic> _scoreToMap(SegmentScore score) {
    return {
      'id': score.id,
      'segmentId': score.segmentId,
      'cluster0Deviation': score.cluster0Deviation,
      'cluster1Deviation': score.cluster1Deviation,
      'matchedCluster': score.matchedCluster,
      'matchedClusterName': score.matchedClusterName,
    };
  }

  TripSummary _benchmarkTripFromMap(Map<String, dynamic> map) {
    return TripSummary(
      tripId: map['trip_id']?.toString() ?? '',
      startTime: DateTime.fromMillisecondsSinceEpoch((map['start_time'] as num?)?.toInt() ?? 0),
      endTime: DateTime.fromMillisecondsSinceEpoch((map['end_time'] as num?)?.toInt() ?? 0),
      totalSegments: (map['total_segments'] as num?)?.toInt() ?? 0,
      validSegments: (map['valid_segments'] as num?)?.toInt() ?? 0,
      cluster0Matches: (map['cluster0_matches'] as num?)?.toInt() ?? 0,
      cluster1Matches: (map['cluster1_matches'] as num?)?.toInt() ?? 0,
      cluster0Percentage: (map['cluster0_percentage'] as num?)?.toDouble() ?? 0.0,
      cluster1Percentage: (map['cluster1_percentage'] as num?)?.toDouble() ?? 0.0,
      avgDeviationPlain: (map['avg_deviation_plain'] as num?)?.toDouble() ?? 0.0,
      avgDeviationUphill: (map['avg_deviation_uphill'] as num?)?.toDouble() ?? 0.0,
      avgDeviationDownhill: (map['avg_deviation_downhill'] as num?)?.toDouble() ?? 0.0,
      overallAvgDeviation: (map['overall_avg_deviation'] as num?)?.toDouble() ?? 0.0,
      plainSegments: (map['plain_segments'] as num?)?.toInt() ?? 0,
      uphillSegments: (map['uphill_segments'] as num?)?.toInt() ?? 0,
      downhillSegments: (map['downhill_segments'] as num?)?.toInt() ?? 0,
      userId: (map['user_id'] as num?)?.toInt() ?? 0,
      coachingReport: (map['coaching_report'] as String?) ?? '',
      score: (map['score'] as num?)?.toDouble() ?? -1,
      vehicleType: (map['vehicle_type'] as String?) ?? '',
      driverName: (map['driver_name'] as String?) ?? '',
      busNumber: (map['bus_number'] as String?) ?? '',
    );
  }

  Segment _segmentFromMap(Map<String, dynamic> map, String fallbackId) {
    return Segment(
      id: int.tryParse((map['id'] ?? fallbackId).toString()),
      tripId: (map['tripId'] ?? map['trip_id'] ?? '').toString(),
      mode: (map['mode'] as String?) ?? 'collection',
      segmentIndex: (map['segment_index'] as num?)?.toInt() ??
        (map['segmentIndex'] as num?)?.toInt() ??
        0,
      startTime: (map['start_time'] as num?)?.toInt() ??
        (map['startTime'] as num?)?.toInt() ??
        0,
      endTime: (map['end_time'] as num?)?.toInt() ??
        (map['endTime'] as num?)?.toInt() ??
        0,
      terrain: (map['terrain'] as String?) ?? '',
      distance: (map['distance_m'] as num?)?.toDouble() ?? (map['distance'] as num?)?.toDouble() ?? 0.0,
      startLat: (map['start_lat'] as num?)?.toDouble() ??
        (map['startLat'] as num?)?.toDouble() ??
        0.0,
      startLon: (map['start_lon'] as num?)?.toDouble() ??
        (map['startLon'] as num?)?.toDouble() ??
        0.0,
      endLat: (map['end_lat'] as num?)?.toDouble() ??
        (map['endLat'] as num?)?.toDouble() ??
        0.0,
      endLon: (map['end_lon'] as num?)?.toDouble() ??
        (map['endLon'] as num?)?.toDouble() ??
        0.0,
      startAltitude: (map['start_altitude'] as num?)?.toDouble() ??
        (map['startAltitude'] as num?)?.toDouble() ??
        0.0,
      endAltitude: (map['end_altitude'] as num?)?.toDouble() ??
        (map['endAltitude'] as num?)?.toDouble() ??
        0.0,
      isValid: (map['is_valid'] as bool?) ?? (map['isValid'] as bool?) ?? true,
      nearestLandmark:
        (map['nearest_landmark'] as String?) ?? (map['nearestLandmark'] as String?) ?? '',
    );
  }

  SegmentScore _scoreFromMap(Map<String, dynamic> map, String fallbackId) {
    return SegmentScore(
      id: int.tryParse((map['id'] ?? fallbackId).toString()),
      segmentId: (map['segmentId'] as num?)?.toInt() ?? (map['segment_id'] as num?)?.toInt() ?? 0,
      cluster0Deviation: (map['cluster0Deviation'] as num?)?.toDouble() ?? (map['cluster0_deviation'] as num?)?.toDouble() ?? 0.0,
      cluster1Deviation: (map['cluster1Deviation'] as num?)?.toDouble() ?? (map['cluster1_deviation'] as num?)?.toDouble() ?? 0.0,
      matchedCluster: (map['matchedCluster'] as num?)?.toInt() ?? (map['matched_cluster'] as num?)?.toInt() ?? 0,
      matchedClusterName: (map['matchedClusterName'] as String?) ?? (map['matched_cluster_name'] as String?) ?? '',
    );
  }

  TripSummary _benchmarkTripFromUserMirror(Map<String, dynamic> map) {
    final summary = map['summary'];
    if (summary is Map) {
      final summaryMap = Map<String, dynamic>.from(summary as Map);
      return TripSummary(
        tripId: (summaryMap['tripId'] ?? summaryMap['trip_id'] ?? map['tripId'] ?? '').toString(),
        startTime: _dateFromDynamic(summaryMap['startTime'] ?? summaryMap['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        endTime: _dateFromDynamic(summaryMap['endTime'] ?? summaryMap['end_time']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        totalSegments: (summaryMap['totalSegments'] ?? summaryMap['total_segments'] as num?)?.toInt() ?? 0,
        validSegments: (summaryMap['validSegments'] ?? summaryMap['valid_segments'] as num?)?.toInt() ?? 0,
        cluster0Matches: (summaryMap['cluster0Matches'] ?? summaryMap['cluster0_matches'] as num?)?.toInt() ?? 0,
        cluster1Matches: (summaryMap['cluster1Matches'] ?? summaryMap['cluster1_matches'] as num?)?.toInt() ?? 0,
        cluster0Percentage: _numFromDynamic(summaryMap['cluster0Percentage'] ?? summaryMap['cluster0_percentage'])?.toDouble() ?? 0.0,
        cluster1Percentage: _numFromDynamic(summaryMap['cluster1Percentage'] ?? summaryMap['cluster1_percentage'])?.toDouble() ?? 0.0,
        avgDeviationPlain: _numFromDynamic(summaryMap['avgDeviationPlain'] ?? summaryMap['avg_deviation_plain'])?.toDouble() ?? 0.0,
        avgDeviationUphill: _numFromDynamic(summaryMap['avgDeviationUphill'] ?? summaryMap['avg_deviation_uphill'])?.toDouble() ?? 0.0,
        avgDeviationDownhill: _numFromDynamic(summaryMap['avgDeviationDownhill'] ?? summaryMap['avg_deviation_downhill'])?.toDouble() ?? 0.0,
        overallAvgDeviation: _numFromDynamic(summaryMap['overallAvgDeviation'] ?? summaryMap['overall_avg_deviation'])?.toDouble() ?? 0.0,
        plainSegments: (summaryMap['plainSegments'] ?? summaryMap['plain_segments'] as num?)?.toInt() ?? 0,
        uphillSegments: (summaryMap['uphillSegments'] ?? summaryMap['uphill_segments'] as num?)?.toInt() ?? 0,
        downhillSegments: (summaryMap['downhillSegments'] ?? summaryMap['downhill_segments'] as num?)?.toInt() ?? 0,
        userId: (summaryMap['userId'] ?? summaryMap['user_id'] as num?)?.toInt() ?? 0,
        coachingReport: (summaryMap['coachingReport'] ?? summaryMap['coaching_report'] as String?) ?? '',
        score: _numFromDynamic(summaryMap['score'])?.toDouble() ?? -1,
        vehicleType: (summaryMap['vehicleType'] ?? summaryMap['vehicle_type'] as String?) ?? '',
        driverName: (summaryMap['driverName'] ?? summaryMap['driver_name'] as String?) ?? '',
        busNumber: (summaryMap['busNumber'] ?? summaryMap['bus_number'] as String?) ?? '',
      );
    }

    return _benchmarkTripFromMap(map);
  }

  DataCollectionTrip _collectionTripFromMap(Map<String, dynamic> map) {
    return DataCollectionTrip(
      id: (map['id'] as num?)?.toInt(),
      tripId: (map['trip_id'] as String?) ?? '',
      driverId: (map['driver_id'] as num?)?.toInt() ?? 0,
      mode: (map['mode'] as String?) ?? 'collection',
      segmentDistanceM: (map['segment_distance_m'] as num?)?.toDouble() ?? 100.0,
      startTime: DateTime.fromMillisecondsSinceEpoch((map['start_time'] as num?)?.toInt() ?? 0),
      endTime: (map['end_time'] as num?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((map['end_time'] as num).toInt()),
      totalSegments: (map['total_segments'] as num?)?.toInt() ?? 0,
      notes: (map['notes'] as String?) ?? '',
      createdAt: (map['created_at'] as String?) ?? '',
      driverUsername: (map['driverUsername'] as String?) ?? (map['username'] as String?) ?? '',
      driverName: (map['full_name'] as String?)?.trim().isNotEmpty == true
          ? (map['full_name'] as String).trim()
          : ((map['driverName'] as String?) ?? ''),
      busNumber: (map['busNumber'] as String?) ?? (map['bus_number'] as String?) ?? '',
      routeDescription: (map['routeDescription'] as String?) ?? '',
      vehicleType: (map['vehicle_type'] as String?) ?? '',
    );
  }

  DataCollectionTrip _collectionTripFromUserMirror(Map<String, dynamic> map) {
    final trip = map['trip'];
    if (trip is Map) {
      return DataCollectionTrip.fromMap(Map<String, dynamic>.from(trip as Map));
    }

    return _collectionTripFromMap(map);
  }

  DateTime? _dateFromDynamic(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  num? _numFromDynamic(dynamic value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value);
    }
    return null;
  }
}
