import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// Note: storage permission checks removed — use app-scoped and public directories instead
import '../database/db_helper.dart';
import '../config/constants.dart';

class CsvExportService {
  final DbHelper _db = DbHelper();
  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  static const String _storageHelpMessage =
      'Could not save file. Please check storage permissions in Settings → Apps → Traxio → Permissions → Storage.';

  static const List<String> _featureNames = [
    'ARV',
    'AvgAmplitude',
    'CrestFactor',
    'FreqCentroid',
    'FreqVariance',
    'ImpulseFactor',
    'MarginFactor',
    'Max',
    'Mean',
    'Min',
    'PeakToPeak',
    'RMS',
    'ShapeFactor',
    'SpectralEntropy',
    'Std',
  ];

  static final List<String> _attributes =
      [...AppConstants.attributeNames]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  static List<String> get featureColumns {
    final cols = <String>[];
    for (final attr in _attributes) {
      for (final feature in _featureNames) {
        cols.add('${attr}_$feature');
      }
    }
    return cols;
  }

  Future<String> exportCollectionTripCSV(String tripId) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      throw Exception('Invalid trip ID for export');
    }

    // Get trip to extract vehicle type and date
    final trip = await _db.getDataCollectionTripById(tripId);
    final vehicleType = trip?['vehicle_type'] as String? ?? 'Unknown';
    DateTime startTime;
    final rawStart = trip?['start_time'];
    if (rawStart is int) {
      startTime = DateTime.fromMillisecondsSinceEpoch(rawStart);
    } else if (rawStart is DateTime) {
      startTime = rawStart;
    } else {
      startTime = DateTime.now();
    }
    final dateStr = DateFormat('yyyyMMdd').format(startTime);
    final safeVehicleType = vehicleType.trim().isEmpty
        ? 'Unknown'
        : _sanitizeForFileName(vehicleType.trim());

    final rows = await _db.getSegmentsWithFeaturesForTrip(
      tripId,
      mode: 'collection',
    );
    final path = await _writeCsvFileWithMetadata(
      fileName: 'traxio_collection_${safeVehicleType}_$dateStr.csv',
      rows: rows,
      includeDriverColumns: false,
      vehicleType: vehicleType,
      exportDate: startTime,
      exportTitle: 'Traxio Data Collection Export',
    );
    return path;
  }

  Future<String> exportTripCSV(String tripId) async {
    return exportCollectionTripCSV(tripId);
  }

  Future<String> exportBenchmarkTripCSV(String tripId) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      throw Exception('Invalid trip ID for export');
    }

    // Get trip to extract vehicle type and date
    final trip = await _db.getBenchmarkTripById(tripId);
    final vehicleType = trip?['vehicle_type'] as String? ?? 'Unknown';
    DateTime startTime;
    final rawStart = trip?['start_time'];
    if (rawStart is int) {
      startTime = DateTime.fromMillisecondsSinceEpoch(rawStart);
    } else if (rawStart is DateTime) {
      startTime = rawStart;
    } else {
      startTime = DateTime.now();
    }
    final dateStr = DateFormat('yyyyMMdd').format(startTime);
    final safeVehicleType = vehicleType.trim().isEmpty
        ? 'Unknown'
        : _sanitizeForFileName(vehicleType.trim());

    final rows = await _db.getSegmentsWithFeaturesForTrip(
      tripId,
      mode: 'benchmark',
    );
    final scoreMap = await _db.getSegmentScoresMapForTrip(tripId);

    final enrichedRows = rows.map((row) {
      final segmentId = row['segment_id'] as int;
      final score = scoreMap[segmentId] ?? const <String, dynamic>{};
      return {
        ...row,
        'matched_cluster': score['matched_cluster'],
        'matched_cluster_name': score['matched_cluster_name'] ?? '',
        'cluster0_deviation': score['cluster0_deviation'],
        'cluster1_deviation': score['cluster1_deviation'],
      };
    }).toList();

    final headers = <String>[
      'csv_row_number',
      'trip_id',
      'segment_index',
      'start_time',
      'end_time',
      'duration_seconds',
      'terrain',
      'distance_m',
      'start_lat',
      'start_lon',
      'end_lat',
      'end_lon',
      'nearest_landmark',
      'sample_count',
      'is_valid',
      'matched_cluster',
      'matched_cluster_name',
      'cluster0_deviation',
      'cluster1_deviation',
      ...featureColumns,
    ];

    return _writeCsvFileWithHeadersAndMetadata(
      fileName: 'traxio_benchmark_${safeVehicleType}_$dateStr.csv',
      rows: enrichedRows,
      headers: headers,
      vehicleType: vehicleType,
      exportDate: startTime,
      exportTitle: 'Traxio Benchmark Export',
    );
  }

  Future<String> exportAllCollectionCSV() async {
    final trips = await _db.getAllDataCollectionTrips();
    final allRows = <Map<String, dynamic>>[];

    for (final trip in trips) {
      final rows = await _db.getSegmentsWithFeaturesForTrip(
        trip.tripId,
        mode: 'collection',
      );
      for (final row in rows) {
        allRows.add({
          'driver_username': trip.driverUsername,
          'bus_number': trip.busNumber,
          ...row,
        });
      }
    }

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return _writeCsvFileWithMetadata(
      fileName: 'traxio_collection_all_$stamp.csv',
      rows: allRows,
      includeDriverColumns: true,
      vehicleType: 'Unknown',
      exportDate: DateTime.now(),
      exportTitle: 'Traxio Data Collection Export',
    );
  }

  Future<String> _writeCsvFileWithMetadata({
    required String fileName,
    required List<Map<String, dynamic>> rows,
    required bool includeDriverColumns,
    required String vehicleType,
    required DateTime exportDate,
    required String exportTitle,
  }) async {
    final headers = <String>[
      'csv_row_number',
      if (includeDriverColumns) ...['driver_username', 'bus_number'],
      'trip_id',
      'segment_index',
      'start_time',
      'end_time',
      'duration_seconds',
      'terrain',
      'distance_m',
      'start_lat',
      'start_lon',
      'end_lat',
      'end_lon',
      'nearest_landmark',
      'sample_count',
      'is_valid',
      ...featureColumns,
    ];

    return _writeCsvFileWithHeadersAndMetadata(
      fileName: fileName,
      rows: rows,
      headers: headers,
      vehicleType: vehicleType,
      exportDate: exportDate,
      exportTitle: exportTitle,
    );
  }

  Future<String> _writeCsvFileWithHeadersAndMetadata({
    required String fileName,
    required List<Map<String, dynamic>> rows,
    required List<String> headers,
    required String vehicleType,
    required DateTime exportDate,
    required String exportTitle,
  }) async {
    final buffer = StringBuffer();
    
    // Add metadata rows at the top
    buffer.writeln('# $exportTitle');
    buffer.writeln('# Vehicle Type: $vehicleType');
    buffer.writeln('# Export Date: ${_dateFmt.format(exportDate)}');
    buffer.writeln(''); // blank row

    // Add headers
    buffer.writeln(headers.join(','));

    // Add data rows
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final values = <String>[];
      for (final header in headers) {
        if (header == 'csv_row_number') {
          values.add((index + 1).toString());
          continue;
        }
        values.add(_csvEscape(_extractValue(header, row)));
      }
      buffer.writeln(values.join(','));
    }

    final path = await _getExportPath(fileName);
    final file = File(path);
    await file.writeAsString(buffer.toString(), flush: true);
    if (!file.existsSync()) throw Exception(_storageHelpMessage);
    final fileLength = await file.length();
    if (fileLength == 0) throw Exception(_storageHelpMessage);
    return file.path;
  }

  String _sanitizeForFileName(String input) {
    final safe = input
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return safe.isEmpty ? 'trip' : safe;
  }

  // Permission checks intentionally removed; use app/public directories.

  Future<String> _getExportPath(String filename) async {
    final List<Future<Directory?>> candidates = [
      Future.value(Directory('/storage/emulated/0/Download')),
      getExternalStorageDirectory().then((d) => d != null ? Directory('${d.path}/Traxio') : null),
      getApplicationDocumentsDirectory().then((d) => Directory('${d.path}/Traxio')),
      getTemporaryDirectory().then((d) => Directory('${d.path}/Traxio')),
    ];

    for (final candidate in candidates) {
      try {
        final dir = await candidate;
        if (dir == null) continue;
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('${dir.path}/$filename');
        return file.path;
      } catch (_) {
        continue; // try next candidate
      }
    }
    throw Exception('No writable directory found on this device');
  }

  String _extractValue(String key, Map<String, dynamic> row) {
    if (key == 'start_time') {
      final start = row['start_time'] as int?;
      return start == null
          ? ''
          : _dateFmt.format(DateTime.fromMillisecondsSinceEpoch(start));
    }
    if (key == 'end_time') {
      final end = row['end_time'] as int?;
      return end == null ? '' : _dateFmt.format(DateTime.fromMillisecondsSinceEpoch(end));
    }

    final value = row[key];
    if (value == null) return '';
    if (value is double) return value.toStringAsFixed(6);
    return value.toString();
  }

  String _csvEscape(String input) {
    if (input.contains(',') || input.contains('"') || input.contains('\n')) {
      final escaped = input.replaceAll('"', '""');
      return '"$escaped"';
    }
    return input;
  }

  Future<List<Directory>> _getExportDirectories() async {
    // Kept for backward compatibility but not used by new flow.
    final directories = <Directory>[];
    final downloads = Directory('/storage/emulated/0/Download');
    if (await downloads.exists()) directories.add(downloads);
    final external = await getExternalStorageDirectory();
    if (external != null) directories.add(Directory(p.join(external.path, 'Traxio')));
    final docs = await getApplicationDocumentsDirectory();
    directories.add(Directory(p.join(docs.path, 'Traxio')));
    return directories;
  }
}
