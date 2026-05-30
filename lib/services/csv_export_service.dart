import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// Note: storage permission checks removed — use app-scoped and public directories instead
import '../database/db_helper.dart';
import '../config/constants.dart';
import '../models/raw_model.dart';

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
    final export = await _buildCollectionTripExport(tripId);
    final path = await _getExportPath(export.fileName);
    final file = File(path);
    await file.writeAsString(export.content, flush: true);
    if (!file.existsSync()) throw Exception(_storageHelpMessage);
    if (await file.length() == 0) throw Exception(_storageHelpMessage);
    return file.path;
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
      final export = await _buildCollectionTripExport(trip.tripId);
      allRows.add({
        'trip_id': trip.tripId,
        'csv_content': export.content,
      });
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

  /// Export all collection trips as individual CSV files in a ZIP archive
  Future<String> exportAllCollectionTripsAsZip() async {
    final trips = await _db.getAllDataCollectionTrips();
    if (trips.isEmpty) {
      throw Exception('No collection trips to export');
    }

    final archive = Archive();
    
    for (final trip in trips) {
      final export = await _buildCollectionTripExport(trip.tripId);
      archive.addFile(ArchiveFile(export.fileName, export.content.length, utf8.encode(export.content)));
    }

    // Create the ZIP file
    final encoder = ZipEncoder();
    final zipData = encoder.encode(archive);
    
    if (zipData == null) {
      throw Exception('Failed to create ZIP file');
    }

    // Save to file
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'traxio_collection_all_$stamp.zip';
    final filePath = await _getExportPath(fileName);
    final file = File(filePath);
    await file.writeAsBytes(zipData);
    
    return file.path;
  }

  Future<({String fileName, String content})> _buildCollectionTripExport(String tripId) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      throw Exception('Invalid trip ID for export');
    }

    final trip = await _db.getDataCollectionTripById(tripId);
    final vehicleType = trip?['vehicle_type'] as String? ?? 'Unknown';
    final rawStart = trip?['start_time'];
    final startTime = rawStart is int
        ? DateTime.fromMillisecondsSinceEpoch(rawStart)
        : rawStart is DateTime
            ? rawStart
            : DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(startTime);
    final safeVehicleType = vehicleType.trim().isEmpty
        ? 'Unknown'
        : _sanitizeForFileName(vehicleType.trim());
    final fileName = 'traxio_collection_${safeVehicleType}_${dateStr}_$normalizedTripId.csv';

    // Prefer the segment-features export (136 columns) to match the in-app
    // data viewer and the Firestore segment serialization. Only fall back to
    // the raw 10Hz sample export (9 columns) when a trip has no processed
    // segments. Previously this was inverted — raw samples were checked first,
    // so any trip with raw data (i.e. every real collection trip) exported
    // only the 9 raw columns and the 120 feature columns were never written.
    final segmentRows = await _db.getSegmentsWithFeaturesForTrip(
      tripId,
      mode: 'collection',
    );
    if (segmentRows.isNotEmpty) {
      return (
        fileName: fileName,
        content: _buildSegmentCollectionCsv(
          tripId: tripId,
          trip: trip,
          startTime: startTime,
          rows: segmentRows,
        ),
      );
    }

    final rawSamples = await _db.getRawSamplesForTrip(tripId);
    return (
      fileName: fileName,
      content: _buildRawCollectionCsv(
        tripId: tripId,
        trip: trip,
        startTime: startTime,
        rawSamples: rawSamples,
      ),
    );
  }

  String _buildRawCollectionCsv({
    required String tripId,
    required Map<String, dynamic>? trip,
    required DateTime startTime,
    required List<RawSample> rawSamples,
  }) {
    final driverUsername = trip?['username']?.toString() ?? '';
    final vehicle = (trip?['vehicle_type']?.toString().trim().isNotEmpty ?? false)
        ? trip!['vehicle_type'].toString()
        : (trip?['bus_number']?.toString() ?? '');
    final buffer = StringBuffer();
    buffer.writeln('# Traxio Data Collection Export');
    buffer.writeln('# Trip ID: $tripId');
    buffer.writeln('# Driver: $driverUsername');
    buffer.writeln('# Vehicle: $vehicle');
    buffer.writeln('# Export Date: ${_dateFmt.format(startTime)}');
    buffer.writeln('# Source: raw samples');
    buffer.writeln('');
    buffer.writeln('csv_row_number,timestamp,lat,lon,speed,ax,ay,yaw_rate,altitude');

    for (var index = 0; index < rawSamples.length; index++) {
      final sample = rawSamples[index];
      buffer.writeln([
        index + 1,
        sample.timestamp,
        sample.lat.toStringAsFixed(6),
        sample.lon.toStringAsFixed(6),
        sample.speed.toStringAsFixed(3),
        sample.ax.toStringAsFixed(6),
        sample.ay.toStringAsFixed(6),
        sample.yawRate.toStringAsFixed(6),
        sample.altitude.toStringAsFixed(3),
      ].join(','));
    }

    return buffer.toString();
  }

  String _buildSegmentCollectionCsv({
    required String tripId,
    required Map<String, dynamic>? trip,
    required DateTime startTime,
    required List<Map<String, dynamic>> rows,
  }) {
    final driverUsername = trip?['username']?.toString() ?? '';
    // The collection vehicle is stored as vehicle_type on the trip record;
    // fall back to the driver's bus_number if vehicle_type is blank.
    final vehicle = (trip?['vehicle_type']?.toString().trim().isNotEmpty ?? false)
        ? trip!['vehicle_type'].toString()
        : (trip?['bus_number']?.toString() ?? '');
    final headers = <String>[
      'csv_row_number',
      'driver_username',
      'bus_number',
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

    final buffer = StringBuffer();
    buffer.writeln('# Traxio Data Collection Export');
    buffer.writeln('# Trip ID: $tripId');
    buffer.writeln('# Driver: $driverUsername');
    buffer.writeln('# Vehicle: $vehicle');
    buffer.writeln('# Export Date: ${_dateFmt.format(startTime)}');
    buffer.writeln('# Source: segmented data');
    buffer.writeln('');
    buffer.writeln(headers.join(','));

    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final values = <String>[
        '${index + 1}',
        driverUsername,
        vehicle,
        tripId,
      ];

      for (final header in headers.sublist(4)) {
        final value = row[header] ?? '';
        final escaped = value.toString().replaceAll('"', '""');
        values.add('"$escaped"');
      }

      buffer.writeln(values.join(','));
    }

    return buffer.toString();
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
