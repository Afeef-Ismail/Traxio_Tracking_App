import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../database/db_helper.dart';
import '../config/constants.dart';

class CsvExportService {
  final DbHelper _db = DbHelper();
  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

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

  Future<String> exportTripCSV(String tripId) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      throw Exception('Invalid trip ID for export');
    }

    final rows = await _db.getSegmentsWithFeaturesForTrip(
      tripId,
      mode: 'collection',
    );
    final path = await _writeCsvFile(
      fileName: 'ksrtc_collection_${_sanitizeForFileName(normalizedTripId)}.csv',
      rows: rows,
      includeDriverColumns: false,
    );
    return path;
  }

  Future<String> exportBenchmarkTripCSV(String tripId) async {
    try {
      final normalizedTripId = tripId.trim();
      if (normalizedTripId.isEmpty) {
        throw Exception('Invalid trip ID for export');
      }

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
        'cluster0_deviation',
        'cluster1_deviation',
        ...featureColumns,
      ];

      return await _writeCsvFileWithHeaders(
        fileName: 'ksrtc_benchmark_${_sanitizeForFileName(normalizedTripId)}.csv',
        rows: enrichedRows,
        headers: headers,
      );
    } catch (e) {
      throw Exception(e.toString());
    }
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
    return _writeCsvFile(
      fileName: 'ksrtc_collection_all_$stamp.csv',
      rows: allRows,
      includeDriverColumns: true,
    );
  }

  Future<String> _writeCsvFile({
    required String fileName,
    required List<Map<String, dynamic>> rows,
    required bool includeDriverColumns,
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

    return _writeCsvFileWithHeaders(
      fileName: fileName,
      rows: rows,
      headers: headers,
    );
  }

  Future<String> _writeCsvFileWithHeaders({
    required String fileName,
    required List<Map<String, dynamic>> rows,
    required List<String> headers,
  }) async {
    await _ensureStoragePermissionIfNeeded();

    final buffer = StringBuffer();
    buffer.writeln(headers.join(','));

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

    final downloadsDir = await _resolveDownloadsDirectory();
    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }

    final file = File(p.join(downloadsDir.path, fileName));
    await file.writeAsString(buffer.toString(), flush: true);
    if (!file.existsSync()) {
      throw Exception('CSV write failed: file not found at ${file.path}');
    }
    final fileLength = await file.length();
    if (fileLength == 0) {
      throw Exception('CSV write failed: file is empty at ${file.path}');
    }
    return file.path;
  }

  String _sanitizeForFileName(String input) {
    final safe = input
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return safe.isEmpty ? 'trip' : safe;
  }

  Future<void> _ensureStoragePermissionIfNeeded() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt < 33) {
        final permissionStatus = await Permission.storage.request();
        if (!permissionStatus.isGranted) {
          throw Exception('Storage permission denied: $permissionStatus');
        }
      }
    }
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

  Future<Directory> _resolveDownloadsDirectory() async {
    final publicDownloads = Directory('/storage/emulated/0/Download');
    if (!publicDownloads.existsSync()) {
      publicDownloads.createSync(recursive: true);
    }
    if (publicDownloads.existsSync()) return publicDownloads;

    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;

    final external = await getExternalStorageDirectory();
    if (external != null) {
      final commonDownload = Directory('/storage/emulated/0/Download');
      if (await commonDownload.exists()) return commonDownload;
      return external;
    }

    return await getApplicationDocumentsDirectory();
  }
}
