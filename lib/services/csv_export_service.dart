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
    'AvgAmplitude',
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
    final rows = await _db.getSegmentsWithFeaturesForTrip(tripId);
    final path = await _writeCsvFile(
      fileName: 'ksrtc_collection_$tripId.csv',
      rows: rows,
      includeDriverColumns: false,
    );
    return path;
  }

  Future<String> exportAllCollectionCSV() async {
    final trips = await _db.getAllDataCollectionTrips();
    final allRows = <Map<String, dynamic>>[];

    for (final trip in trips) {
      final rows = await _db.getSegmentsWithFeaturesForTrip(trip.tripId);
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
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt < 33) {
        final permissionStatus = await Permission.storage.request();
        if (!permissionStatus.isGranted) {
          throw Exception('Storage permission denied: $permissionStatus');
        }
      }
    }

    final headers = <String>[
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
      ...featureColumns,
    ];

    final buffer = StringBuffer();
    buffer.writeln(headers.join(','));

    for (final row in rows) {
      final values = <String>[];
      for (final header in headers) {
        values.add(_csvEscape(_extractValue(header, row)));
      }
      buffer.writeln(values.join(','));
    }

    final downloadsDir = await _resolveDownloadsDirectory();
    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }

    final file = File(p.join(downloadsDir.path, fileName));
    await file.writeAsString(buffer.toString());
    if (!file.existsSync()) {
      throw Exception('CSV write failed: file not found at ${file.path}');
    }
    return file.path;
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
