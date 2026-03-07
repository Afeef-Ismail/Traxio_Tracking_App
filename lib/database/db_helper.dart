import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../config/constants.dart';
import '../models/raw_model.dart';
import '../models/segment_model.dart';
import '../models/feature_result.dart';
import '../models/trip_model.dart';

/// Singleton database helper managing all SQLite operations.
class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  factory DbHelper() => _instance;
  DbHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String dbPath = await getDatabasesPath();
    final String path = join(dbPath, AppConstants.dbName);

    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // ─── raw_data ──────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE raw_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        speed REAL NOT NULL,
        ax REAL NOT NULL,
        ay REAL NOT NULL,
        yaw_rate REAL NOT NULL,
        altitude REAL NOT NULL
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_raw_trip ON raw_data(trip_id)');
    await db.execute(
        'CREATE INDEX idx_raw_timestamp ON raw_data(timestamp)');

    // ─── segments ──────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT NOT NULL,
        segment_index INTEGER NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER NOT NULL,
        terrain TEXT NOT NULL,
        distance REAL NOT NULL,
        start_lat REAL NOT NULL,
        start_lon REAL NOT NULL,
        end_lat REAL NOT NULL,
        end_lon REAL NOT NULL,
        start_altitude REAL NOT NULL,
        end_altitude REAL NOT NULL,
        is_valid INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_seg_trip ON segments(trip_id)');

    // ─── features ──────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE features (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        segment_id INTEGER NOT NULL,
        feature_name TEXT NOT NULL,
        value REAL NOT NULL,
        FOREIGN KEY (segment_id) REFERENCES segments(id)
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_feat_seg ON features(segment_id)');

    // ─── segment_scores ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE segment_scores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        segment_id INTEGER NOT NULL,
        cluster0_deviation REAL NOT NULL,
        cluster1_deviation REAL NOT NULL,
        matched_cluster INTEGER NOT NULL,
        FOREIGN KEY (segment_id) REFERENCES segments(id)
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_score_seg ON segment_scores(segment_id)');

    // ─── trip_summaries ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE trip_summaries (
        trip_id TEXT PRIMARY KEY,
        start_time INTEGER NOT NULL,
        end_time INTEGER NOT NULL,
        total_segments INTEGER NOT NULL,
        valid_segments INTEGER NOT NULL,
        cluster0_matches INTEGER NOT NULL,
        cluster1_matches INTEGER NOT NULL,
        cluster0_percentage REAL NOT NULL,
        cluster1_percentage REAL NOT NULL,
        avg_deviation_plain REAL NOT NULL,
        avg_deviation_uphill REAL NOT NULL,
        avg_deviation_downhill REAL NOT NULL,
        overall_avg_deviation REAL NOT NULL,
        plain_segments INTEGER NOT NULL,
        uphill_segments INTEGER NOT NULL,
        downhill_segments INTEGER NOT NULL
      )
    ''');
  }

  // ═══════════════════════════════════════════════════════════════════
  // RAW DATA OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Insert a batch of raw samples efficiently.
  Future<void> insertRawBatch(List<RawSample> samples) async {
    final db = await database;
    final batch = db.batch();
    for (final sample in samples) {
      batch.insert('raw_data', sample.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Insert a single raw sample.
  Future<int> insertRaw(RawSample sample) async {
    final db = await database;
    return await db.insert('raw_data', sample.toMap());
  }

  /// Get all raw samples for a trip, ordered by timestamp.
  Future<List<RawSample>> getRawSamplesForTrip(String tripId) async {
    final db = await database;
    final maps = await db.query(
      'raw_data',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => RawSample.fromMap(m)).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  // SEGMENT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Insert a segment and return its ID.
  Future<int> insertSegment(Segment segment) async {
    final db = await database;
    return await db.insert('segments', segment.toMap());
  }

  /// Get all segments for a trip.
  Future<List<Segment>> getSegmentsForTrip(String tripId) async {
    final db = await database;
    final maps = await db.query(
      'segments',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'segment_index ASC',
    );
    return maps.map((m) => Segment.fromMap(m)).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  // FEATURE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Insert all features for a segment.
  Future<void> insertFeatures(List<FeatureResult> features) async {
    final db = await database;
    final batch = db.batch();
    for (final f in features) {
      batch.insert('features', f.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Get all features for a segment, returned as a map.
  Future<Map<String, double>> getFeaturesForSegment(int segmentId) async {
    final db = await database;
    final maps = await db.query(
      'features',
      where: 'segment_id = ?',
      whereArgs: [segmentId],
    );
    final result = <String, double>{};
    for (final m in maps) {
      result[m['feature_name'] as String] = (m['value'] as num).toDouble();
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  // SCORE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Insert a segment score.
  Future<int> insertSegmentScore(SegmentScore score) async {
    final db = await database;
    return await db.insert('segment_scores', score.toMap());
  }

  /// Get all scores for a trip's segments.
  Future<List<SegmentScore>> getScoresForTrip(String tripId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT ss.* FROM segment_scores ss
      INNER JOIN segments s ON ss.segment_id = s.id
      WHERE s.trip_id = ?
      ORDER BY s.segment_index ASC
    ''', [tripId]);
    return maps.map((m) => SegmentScore.fromMap(m)).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  // TRIP SUMMARY OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Save trip summary.
  Future<void> saveTripSummary(TripSummary summary) async {
    final db = await database;
    await db.insert(
      'trip_summaries',
      summary.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all trip summaries, most recent first.
  Future<List<TripSummary>> getAllTripSummaries() async {
    final db = await database;
    final maps = await db.query(
      'trip_summaries',
      orderBy: 'start_time DESC',
    );
    return maps.map((m) => TripSummary.fromMap(m)).toList();
  }

  /// Get a single trip summary.
  Future<TripSummary?> getTripSummary(String tripId) async {
    final db = await database;
    final maps = await db.query(
      'trip_summaries',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    if (maps.isEmpty) return null;
    return TripSummary.fromMap(maps.first);
  }

  /// Delete all data for a trip.
  Future<void> deleteTrip(String tripId) async {
    final db = await database;
    await db.transaction((txn) async {
      // Get segment IDs first
      final segments = await txn.query(
        'segments',
        columns: ['id'],
        where: 'trip_id = ?',
        whereArgs: [tripId],
      );
      final segIds = segments.map((s) => s['id'] as int).toList();

      if (segIds.isNotEmpty) {
        final placeholders = segIds.map((_) => '?').join(',');
        await txn.delete('segment_scores',
            where: 'segment_id IN ($placeholders)', whereArgs: segIds);
        await txn.delete('features',
            where: 'segment_id IN ($placeholders)', whereArgs: segIds);
      }

      await txn.delete('segments',
          where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('raw_data',
          where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('trip_summaries',
          where: 'trip_id = ?', whereArgs: [tripId]);
    });
  }

  /// Purge all data.
  Future<void> purgeAll() async {
    final db = await database;
    await db.delete('segment_scores');
    await db.delete('features');
    await db.delete('segments');
    await db.delete('raw_data');
    await db.delete('trip_summaries');
  }

  /// Close the database.
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
