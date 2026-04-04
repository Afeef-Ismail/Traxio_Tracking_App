import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import '../config/constants.dart';
import '../config/benchmark_tables.dart';
import '../models/raw_model.dart';
import '../models/segment_model.dart';
import '../models/feature_result.dart';
import '../models/trip_model.dart';
import '../models/cluster_model.dart';

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
      onUpgrade: _onUpgrade,
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
        mode TEXT NOT NULL DEFAULT 'benchmark',
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
        is_valid INTEGER NOT NULL DEFAULT 1,
        nearest_landmark TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_seg_trip ON segments(trip_id)');

    // ─── data_collection_trips ────────────────────────────────────
    await _createDataCollectionTripsTable(db);

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
        matched_cluster_name TEXT NOT NULL DEFAULT '',
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
        downhill_segments INTEGER NOT NULL,
        user_id INTEGER NOT NULL DEFAULT 0,
        coaching_report TEXT NOT NULL DEFAULT '',
        score REAL NOT NULL DEFAULT -1,
        vehicle_type TEXT NOT NULL DEFAULT ''
      )
    ''');

    // ─── users ─────────────────────────────────────────────────────
    await _createUsersTable(db);

    // ─── config ────────────────────────────────────────────────────
    await _createConfigTable(db);

    // ─── benchmark_config ──────────────────────────────────────────
    await _createBenchmarkConfigTable(db);

    // ─── clusters ──────────────────────────────────────────────────
    await _createClustersTable(db);

    // ─── cluster_features ──────────────────────────────────────────
    await _createClusterFeaturesTable(db);

    // ─── Seed default data ─────────────────────────────────────────
    await _seedDefaults(db);

    // ─── Seed default clusters ─────────────────────────────────────
    await _seedDefaultClusters(db);
  }

  /// Upgrade handler for existing installations.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createUsersTable(db);
      await _createConfigTable(db);
      await _seedDefaults(db);
    }
    if (oldVersion < 3) {
      // Add bus_number column to existing users table
      await db.execute(
          "ALTER TABLE users ADD COLUMN bus_number TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 4) {
      // Add user_id column to trip_summaries to track which driver recorded the trip
      await db.execute(
          "ALTER TABLE trip_summaries ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0");
    }
    if (oldVersion < 5) {
      // Add benchmark_config table for editable benchmark ranges
      await _createBenchmarkConfigTable(db);
      await _seedBenchmarkDefaults(db);
    }
    if (oldVersion < 6) {
      await db.execute(
          "ALTER TABLE segments ADD COLUMN nearest_landmark TEXT NOT NULL DEFAULT ''");
      await db.execute(
          "ALTER TABLE trip_summaries ADD COLUMN coaching_report TEXT NOT NULL DEFAULT ''");
      await db.execute(
          "ALTER TABLE trip_summaries ADD COLUMN score REAL NOT NULL DEFAULT -1");
    }
    if (oldVersion < 7) {
      await db.execute(
          "ALTER TABLE segments ADD COLUMN mode TEXT NOT NULL DEFAULT 'benchmark'");
      await _createDataCollectionTripsTable(db);
      await db.insert('config', {
        'key': 'collection_segment_distance_m',
        'value': '100.0',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (oldVersion < 8) {
      // Add matched_cluster_name to segment_scores
      await db.execute(
          "ALTER TABLE segment_scores ADD COLUMN matched_cluster_name TEXT NOT NULL DEFAULT ''");
      // Add vehicle_type to trip_summaries
      await db.execute(
          "ALTER TABLE trip_summaries ADD COLUMN vehicle_type TEXT NOT NULL DEFAULT ''");
      // Create clusters and cluster_features tables
      await _createClustersTable(db);
      await _createClusterFeaturesTable(db);
      // Seed default clusters from existing benchmark_config
      await _seedDefaultClusters(db);
    }
  }

  /// Create the users table.
  Future<void> _createUsersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('admin', 'driver')),
        created_at INTEGER NOT NULL,
        bus_number TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_users_username ON users(username)');
  }

  /// Create the config table.
  Future<void> _createConfigTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS config (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL UNIQUE,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_config_key ON config(key)');
  }

  /// Create the benchmark_config table for editable benchmark ranges.
  Future<void> _createBenchmarkConfigTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS benchmark_config (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        terrain TEXT NOT NULL,
        feature_key TEXT NOT NULL,
        cluster0_min REAL NOT NULL,
        cluster0_max REAL NOT NULL,
        cluster1_min REAL NOT NULL,
        cluster1_max REAL NOT NULL,
        display_order INTEGER NOT NULL DEFAULT 0,
        UNIQUE(terrain, feature_key)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_bench_terrain ON benchmark_config(terrain)');
  }

  /// Create the clusters table.
  Future<void> _createClustersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clusters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        route TEXT NOT NULL DEFAULT '',
        vehicle_type TEXT NOT NULL DEFAULT 'Bus',
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clusters_active ON clusters(is_active)');
  }

  /// Create the cluster_features table.
  Future<void> _createClusterFeaturesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cluster_features (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cluster_id INTEGER NOT NULL,
        terrain TEXT NOT NULL,
        feature_name TEXT NOT NULL,
        min_value REAL NOT NULL,
        max_value REAL NOT NULL,
        updated_at TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (cluster_id) REFERENCES clusters(id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cf_cluster ON cluster_features(cluster_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cf_terrain ON cluster_features(cluster_id, terrain)');
  }

  /// Seed two default clusters from existing benchmark_config data.
  Future<void> _seedDefaultClusters(Database db) async {
    // Only seed if no clusters exist yet
    final existing = await db.query('clusters', limit: 1);
    if (existing.isNotEmpty) return;

    final now = DateTime.now().toIso8601String();

    final clusterAId = await db.insert('clusters', {
      'name': 'Master Driver A',
      'description': 'Benchmark cluster based on CEB master driver behavior',
      'route': 'Kozhikode Bus Stand → Sulthan Bathery',
      'vehicle_type': 'Bus',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    });

    final clusterBId = await db.insert('clusters', {
      'name': 'Master Driver B',
      'description': 'Benchmark cluster based on DEB master driver behavior',
      'route': 'Kozhikode Bus Stand → Sulthan Bathery',
      'vehicle_type': 'Bus',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    });

    // Read benchmark_config and convert to cluster_features
    final terrains = [
      AppConstants.terrainPlain,
      AppConstants.terrainUphill,
      AppConstants.terrainDownhill,
    ];

    for (final terrain in terrains) {
      List<Map<String, dynamic>> rows = [];
      try {
        rows = await db.query(
          'benchmark_config',
          where: 'terrain = ?',
          whereArgs: [terrain],
        );
      } catch (_) {
        // benchmark_config may not exist yet in fresh installs — use hardcoded
        rows = [];
      }

      // Use hardcoded tables if DB is empty
      if (rows.isEmpty) {
        final features = BenchmarkTables.getFeaturesForTerrain(terrain);
        for (final f in features) {
          await db.insert('cluster_features', {
            'cluster_id': clusterAId,
            'terrain': terrain,
            'feature_name': f.featureKey,
            'min_value': f.cluster0.min,
            'max_value': f.cluster0.max,
            'updated_at': now,
          });
          await db.insert('cluster_features', {
            'cluster_id': clusterBId,
            'terrain': terrain,
            'feature_name': f.featureKey,
            'min_value': f.cluster1.min,
            'max_value': f.cluster1.max,
            'updated_at': now,
          });
        }
      } else {
        for (final row in rows) {
          await db.insert('cluster_features', {
            'cluster_id': clusterAId,
            'terrain': terrain,
            'feature_name': row['feature_key'],
            'min_value': row['cluster0_min'],
            'max_value': row['cluster0_max'],
            'updated_at': now,
          });
          await db.insert('cluster_features', {
            'cluster_id': clusterBId,
            'terrain': terrain,
            'feature_name': row['feature_key'],
            'min_value': row['cluster1_min'],
            'max_value': row['cluster1_max'],
            'updated_at': now,
          });
        }
      }
    }
  }

  Future<void> _createDataCollectionTripsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_collection_trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT NOT NULL UNIQUE,
        driver_id INTEGER NOT NULL,
        mode TEXT NOT NULL DEFAULT 'collection',
        segment_distance_m REAL NOT NULL DEFAULT 100.0,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        total_segments INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (driver_id) REFERENCES users(id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_collection_driver ON data_collection_trips(driver_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_collection_trip ON data_collection_trips(trip_id)');
  }

  /// Seed benchmark_config from hardcoded BenchmarkTables defaults.
  Future<void> _seedBenchmarkDefaults(Database db) async {
    final terrains = [
      AppConstants.terrainPlain,
      AppConstants.terrainUphill,
      AppConstants.terrainDownhill,
    ];

    for (final terrain in terrains) {
      final features = BenchmarkTables.getFeaturesForTerrain(terrain);
      for (int i = 0; i < features.length; i++) {
        final f = features[i];
        await db.insert('benchmark_config', {
          'terrain': terrain,
          'feature_key': f.featureKey,
          'cluster0_min': f.cluster0.min,
          'cluster0_max': f.cluster0.max,
          'cluster1_min': f.cluster1.min,
          'cluster1_max': f.cluster1.max,
          'display_order': i,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  /// Hash a password string with SHA-256.
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Seed default admin/driver users and config values.
  Future<void> _seedDefaults(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Seed users (skip if already exist)
    final existingUsers = await db.query('users');
    if (existingUsers.isEmpty) {
      await db.insert('users', {
        'username': 'admin',
        'password_hash': hashPassword('admin123'),
        'role': 'admin',
        'created_at': now,
        'bus_number': '',
      });
      await db.insert('users', {
        'username': 'driver',
        'password_hash': hashPassword('driver123'),
        'role': 'driver',
        'created_at': now,
        'bus_number': 'KL-11-A-1234',
      });
    }

    // Seed config (skip if already exist)
    final existingConfig = await db.query('config');
    if (existingConfig.isEmpty) {
      final defaults = {
        'terrain_slope_uphill_threshold': '0.02',
        'terrain_slope_downhill_threshold': '-0.02',
        'segment_length_meters': '100',
        'collection_segment_distance_m': '100.0',
        'deviation_score_max': '1000',
        'cluster0_label': 'Master Style A',
        'cluster1_label': 'Master Style B',
      };
      for (final entry in defaults.entries) {
        await db.insert('config', {
          'key': entry.key,
          'value': entry.value,
          'updated_at': now,
        });
      }
    }

    // Seed benchmark defaults
    await _seedBenchmarkDefaults(db);
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
  // BENCHMARK CONFIG OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Get all benchmark features for a terrain, ordered by display_order.
  /// Returns BenchmarkFeature objects ready for deviation engine use.
  Future<List<BenchmarkFeature>> getBenchmarkFeatures(String terrain) async {
    final db = await database;
    final maps = await db.query(
      'benchmark_config',
      where: 'terrain = ?',
      whereArgs: [terrain],
      orderBy: 'display_order ASC',
    );

    if (maps.isEmpty) {
      // Fallback to hardcoded if DB is empty for this terrain
      return BenchmarkTables.getFeaturesForTerrain(terrain);
    }

    return maps.map((m) => BenchmarkFeature(
      featureKey: m['feature_key'] as String,
      cluster0: BenchmarkRange(
        (m['cluster0_min'] as num).toDouble(),
        (m['cluster0_max'] as num).toDouble(),
      ),
      cluster1: BenchmarkRange(
        (m['cluster1_min'] as num).toDouble(),
        (m['cluster1_max'] as num).toDouble(),
      ),
    )).toList();
  }

  /// Get all benchmark config rows for a terrain (raw maps for editor UI).
  Future<List<Map<String, dynamic>>> getBenchmarkConfigRaw(
      String terrain) async {
    final db = await database;
    return await db.query(
      'benchmark_config',
      where: 'terrain = ?',
      whereArgs: [terrain],
      orderBy: 'display_order ASC',
    );
  }

  /// Update a single benchmark feature's cluster ranges.
  Future<void> updateBenchmarkRange({
    required String terrain,
    required String featureKey,
    required double cluster0Min,
    required double cluster0Max,
    required double cluster1Min,
    required double cluster1Max,
  }) async {
    final db = await database;
    await db.update(
      'benchmark_config',
      {
        'cluster0_min': cluster0Min,
        'cluster0_max': cluster0Max,
        'cluster1_min': cluster1Min,
        'cluster1_max': cluster1Max,
      },
      where: 'terrain = ? AND feature_key = ?',
      whereArgs: [terrain, featureKey],
    );
  }

  /// Reset benchmark ranges for a terrain to hardcoded defaults.
  Future<void> resetBenchmarkDefaults(String terrain) async {
    final db = await database;
    await db.delete('benchmark_config',
        where: 'terrain = ?', whereArgs: [terrain]);
    final features = BenchmarkTables.getFeaturesForTerrain(terrain);
    for (int i = 0; i < features.length; i++) {
      final f = features[i];
      await db.insert('benchmark_config', {
        'terrain': terrain,
        'feature_key': f.featureKey,
        'cluster0_min': f.cluster0.min,
        'cluster0_max': f.cluster0.max,
        'cluster1_min': f.cluster1.min,
        'cluster1_max': f.cluster1.max,
        'display_order': i,
      });
    }
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

  /// Get trip summaries for a specific user, most recent first.
  Future<List<TripSummary>> getTripSummariesForUser(int userId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.*, u.username AS driver_name, u.bus_number
      FROM trip_summaries t
      LEFT JOIN users u ON t.user_id = u.id
      WHERE t.user_id = ?
      ORDER BY t.start_time DESC
    ''', [userId]);
    return maps.map((m) => TripSummary.fromMap(m)).toList();
  }

  /// Get all trip summaries, most recent first, with driver info.
  Future<List<TripSummary>> getAllTripSummaries() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.*, u.username AS driver_name, u.bus_number
      FROM trip_summaries t
      LEFT JOIN users u ON t.user_id = u.id
      ORDER BY t.start_time DESC
    ''');
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

  /// Update coaching report text for a trip.
  Future<void> updateCoachingReport(String tripId, String report) async {
    final db = await database;
    await db.update(
      'trip_summaries',
      {'coaching_report': report},
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
  }

  /// Update score for a trip.
  Future<void> updateTripScore(String tripId, double score) async {
    final db = await database;
    await db.update(
      'trip_summaries',
      {'score': score},
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
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
        await txn.delete('data_collection_trips',
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
    await db.delete('data_collection_trips');
  }

  // ═══════════════════════════════════════════════════════════════════
  // DATA COLLECTION TRIP OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  Future<void> insertDataCollectionTrip(
    String tripId,
    int driverId,
    double segmentDistanceM,
  ) async {
    final db = await database;
    await db.insert(
      'data_collection_trips',
      {
        'trip_id': tripId,
        'driver_id': driverId,
        'mode': 'collection',
        'segment_distance_m': segmentDistanceM,
        'start_time': DateTime.now().millisecondsSinceEpoch,
        'end_time': null,
        'total_segments': 0,
        'notes': '',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateDataCollectionTripEnd(
    String tripId,
    int endTime,
    int totalSegments,
  ) async {
    final db = await database;
    await db.update(
      'data_collection_trips',
      {
        'end_time': endTime,
        'total_segments': totalSegments,
      },
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
  }

  Future<List<DataCollectionTrip>> getDataCollectionTripsForUser(int userId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.*, u.username, u.bus_number,
        (SELECT s.nearest_landmark FROM segments s
          WHERE s.trip_id = t.trip_id AND s.mode = 'collection'
          ORDER BY s.segment_index ASC LIMIT 1) AS start_landmark,
        (SELECT s.nearest_landmark FROM segments s
          WHERE s.trip_id = t.trip_id AND s.mode = 'collection'
          ORDER BY s.segment_index DESC LIMIT 1) AS end_landmark
      FROM data_collection_trips t
      LEFT JOIN users u ON t.driver_id = u.id
      WHERE t.driver_id = ?
      ORDER BY t.start_time DESC
    ''', [userId]);
    return maps.map((m) => DataCollectionTrip.fromMap(m)).toList();
  }

  Future<List<DataCollectionTrip>> getAllDataCollectionTrips() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.*, u.username, u.bus_number,
        (SELECT s.nearest_landmark FROM segments s
          WHERE s.trip_id = t.trip_id AND s.mode = 'collection'
          ORDER BY s.segment_index ASC LIMIT 1) AS start_landmark,
        (SELECT s.nearest_landmark FROM segments s
          WHERE s.trip_id = t.trip_id AND s.mode = 'collection'
          ORDER BY s.segment_index DESC LIMIT 1) AS end_landmark
      FROM data_collection_trips t
      LEFT JOIN users u ON t.driver_id = u.id
      ORDER BY t.start_time DESC
    ''');
    return maps.map((m) => DataCollectionTrip.fromMap(m)).toList();
  }

  Future<List<Map<String, dynamic>>> getSegmentsWithFeaturesForTrip(
    String tripId, {
    String? mode,
  }) async {
    final db = await database;
    final whereMode = mode == null ? '' : ' AND s.mode = ?';
    final args = <Object?>[tripId, if (mode != null) mode];
    final segments = await db.rawQuery('''
      SELECT
        s.id AS segment_id,
        s.trip_id,
        s.mode,
        s.is_valid,
        s.segment_index,
        s.start_time,
        s.end_time,
        (s.end_time - s.start_time) / 1000.0 AS duration_seconds,
        s.terrain,
        s.distance AS distance_m,
        s.start_lat,
        s.start_lon,
        s.end_lat,
        s.end_lon,
        s.nearest_landmark,
        (
          SELECT COUNT(1)
          FROM raw_data r
          WHERE r.trip_id = s.trip_id
            AND r.timestamp >= s.start_time
            AND r.timestamp <= s.end_time
        ) AS sample_count
      FROM segments s
      -- Return all segments for the trip (valid and invalid)
      WHERE s.trip_id = ?$whereMode
      ORDER BY s.segment_index ASC
    ''', args);

    if (segments.isEmpty) return [];

    final segmentIds = segments
        .map((s) => s['segment_id'] as int)
        .toList();
    final placeholders = List.filled(segmentIds.length, '?').join(',');

    final featureRows = await db.rawQuery('''
      SELECT segment_id, feature_name, value
      FROM features
      WHERE segment_id IN ($placeholders)
    ''', segmentIds);

    final featureMapBySegment = <int, Map<String, double>>{};
    for (final row in featureRows) {
      final segmentId = row['segment_id'] as int;
      final map = featureMapBySegment.putIfAbsent(segmentId, () => <String, double>{});
      map[row['feature_name'] as String] = (row['value'] as num).toDouble();
    }

    final result = <Map<String, dynamic>>[];
    for (final seg in segments) {
      final segmentId = seg['segment_id'] as int;
      result.add({
        ...seg,
        ...?featureMapBySegment[segmentId],
      });
    }

    return result;
  }

  Future<Map<int, Map<String, dynamic>>> getSegmentScoresMapForTrip(
    String tripId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        s.id AS segment_id,
        ss.matched_cluster,
        ss.matched_cluster_name,
        ss.cluster0_deviation,
        ss.cluster1_deviation
      FROM segments s
      LEFT JOIN segment_scores ss ON ss.segment_id = s.id
      WHERE s.trip_id = ?
      ORDER BY s.segment_index ASC
    ''', [tripId]);

    final map = <int, Map<String, dynamic>>{};
    for (final row in rows) {
      final segmentId = row['segment_id'] as int;
      map[segmentId] = {
        'matched_cluster': row['matched_cluster'],
        'matched_cluster_name': row['matched_cluster_name'] ?? '',
        'cluster0_deviation': row['cluster0_deviation'],
        'cluster1_deviation': row['cluster1_deviation'],
      };
    }
    return map;
  }

  // ═══════════════════════════════════════════════════════════════════
  // CLUSTER OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Create a new cluster. Returns the inserted row ID.
  Future<int> createCluster(ClusterDefinition cluster) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('clusters', {
      ...cluster.toMap(),
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Update an existing cluster's metadata.
  Future<void> updateCluster(ClusterDefinition cluster) async {
    final db = await database;
    await db.update(
      'clusters',
      {
        'name': cluster.name,
        'description': cluster.description,
        'route': cluster.route,
        'vehicle_type': cluster.vehicleType,
        'is_active': cluster.isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [cluster.id],
    );
  }

  /// Soft-delete a cluster (sets is_active=0 and deleted_at).
  Future<void> deleteCluster(int id) async {
    final db = await database;
    await db.update(
      'clusters',
      {
        'is_active': 0,
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get all clusters (including inactive, excluding hard-deleted).
  Future<List<ClusterDefinition>> getAllClusters() async {
    final db = await database;
    final maps = await db.query(
      'clusters',
      where: 'deleted_at IS NULL',
      orderBy: 'id ASC',
    );
    return maps.map((m) => ClusterDefinition.fromMap(m)).toList();
  }

  /// Get only active clusters (is_active=1).
  Future<List<ClusterDefinition>> getActiveClusters() async {
    final db = await database;
    final maps = await db.query(
      'clusters',
      where: 'is_active = 1 AND deleted_at IS NULL',
      orderBy: 'id ASC',
    );
    return maps.map((m) => ClusterDefinition.fromMap(m)).toList();
  }

  /// Get all feature ranges for a specific cluster and terrain.
  Future<List<ClusterFeatureRange>> getClusterFeatures(
      int clusterId, String terrain) async {
    final db = await database;
    final maps = await db.query(
      'cluster_features',
      where: 'cluster_id = ? AND terrain = ?',
      whereArgs: [clusterId, terrain],
      orderBy: 'id ASC',
    );
    return maps.map((m) => ClusterFeatureRange.fromMap(m)).toList();
  }

  /// Get all feature ranges for a cluster (all terrains).
  Future<List<ClusterFeatureRange>> getAllClusterFeatures(int clusterId) async {
    final db = await database;
    final maps = await db.query(
      'cluster_features',
      where: 'cluster_id = ?',
      whereArgs: [clusterId],
      orderBy: 'terrain ASC, id ASC',
    );
    return maps.map((m) => ClusterFeatureRange.fromMap(m)).toList();
  }

  /// Update a cluster feature's min/max range.
  Future<void> updateClusterFeature(ClusterFeatureRange feature) async {
    final db = await database;
    await db.update(
      'cluster_features',
      {
        'min_value': feature.minValue,
        'max_value': feature.maxValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [feature.id],
    );
  }

  /// Add a new feature to a cluster. Returns the inserted row ID.
  Future<int> addClusterFeature(ClusterFeatureRange feature) async {
    final db = await database;
    return await db.insert('cluster_features', {
      ...feature.toMap(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Remove a feature from a cluster.
  Future<void> removeClusterFeature(int featureId) async {
    final db = await database;
    await db.delete(
      'cluster_features',
      where: 'id = ?',
      whereArgs: [featureId],
    );
  }

  /// Remove all features for a cluster (used when replacing all features).
  Future<void> removeAllClusterFeatures(int clusterId) async {
    final db = await database;
    await db.delete(
      'cluster_features',
      where: 'cluster_id = ?',
      whereArgs: [clusterId],
    );
  }

  /// Get unique vehicle types across all active clusters.
  Future<List<String>> getActiveVehicleTypes() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT DISTINCT vehicle_type FROM clusters
      WHERE is_active = 1 AND deleted_at IS NULL
      ORDER BY vehicle_type ASC
    ''');
    return maps
        .map((m) => (m['vehicle_type'] as String?) ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
  }

  /// Close the database.
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // ═══════════════════════════════════════════════════════════════════
  // USER OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Get a user by username. Returns null if not found.
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  /// Create a new user. Returns the inserted row ID.
  Future<int> createUser(String username, String passwordHash, String role,
      {String busNumber = ''}) async {
    final db = await database;
    return await db.insert('users', {
      'username': username,
      'password_hash': passwordHash,
      'role': role,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'bus_number': busNumber,
    });
  }

  /// Update the bus number for a user.
  Future<int> updateBusNumber(int userId, String busNumber) async {
    final db = await database;
    return await db.update(
      'users',
      {'bus_number': busNumber},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Delete a user by ID.
  Future<int> deleteUser(int id) async {
    final db = await database;
    return await db.delete(
      'users',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get all users with role 'driver'.
  Future<List<Map<String, dynamic>>> getAllDrivers() async {
    final db = await database;
    return await db.query(
      'users',
      where: 'role = ?',
      whereArgs: ['driver'],
      orderBy: 'username ASC',
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // CONFIG OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Get a single config value by key. Returns null if not found.
  Future<String?> getConfig(String key) async {
    final db = await database;
    final maps = await db.query(
      'config',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  /// Set a config value. Inserts if key doesn't exist, updates if it does.
  Future<void> setConfig(String key, String value) async {
    final db = await database;
    final existing = await db.query(
      'config',
      where: 'key = ?',
      whereArgs: [key],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (existing.isEmpty) {
      await db.insert('config', {
        'key': key,
        'value': value,
        'updated_at': now,
      });
    } else {
      await db.update(
        'config',
        {'value': value, 'updated_at': now},
        where: 'key = ?',
        whereArgs: [key],
      );
    }
  }

  /// Get all config entries as a list of maps.
  Future<List<Map<String, dynamic>>> getAllConfig() async {
    final db = await database;
    return await db.query('config', orderBy: 'key ASC');
  }
}
