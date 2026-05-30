import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../../database/db_helper.dart';
import '../../models/raw_model.dart';
import '../../services/csv_export_service.dart';
import '../../services/firebase_sync_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/feature_display_utils.dart';
import '../theme/app_colors.dart';

/// In-app data viewer for a collection trip.
///
/// Loads all segments with ALL 120+ feature columns dynamically and shows
/// them in a bi-directionally scrollable DataTable with:
///   - Terrain colour-coding
///   - Terrain filter chips
///   - Column sort (tap header)
///   - Mean summary row
///   - Export CSV + Open in App buttons
class DataViewerScreen extends StatefulWidget {
  final String tripId;
  final String title;

  const DataViewerScreen({
    super.key,
    required this.tripId,
    required this.title,
  });

  @override
  State<DataViewerScreen> createState() => _DataViewerScreenState();
}

class _DataViewerScreenState extends State<DataViewerScreen> {
  bool _loading = true;
  bool _exporting = false;
  bool _rawMode = false;

  /// All rows, each is a flat map of columnKey → value.
  List<Map<String, dynamic>> _allRows = [];

  /// Ordered column keys derived from the first row.
  List<String> _columns = [];

  String _terrainFilter = 'All';
  String _sortColumnKey = 'segment_index';
  bool _sortAscending = true;

  final CsvExportService _csvExportService = CsvExportService();

  static const List<String> _terrainOptions = [
    'All', 'Plain', 'Uphill', 'Downhill'
  ];

  /// Structural columns shown before the 120 feature columns.
  static const List<String> _metaFirst = [
    'segment_index',
    'sample_index',
    'timestamp',
    'terrain',
    'is_valid',
    'distance_m',
    'nearest_landmark',
    'sample_count',
    'duration_seconds',
  ];

  /// Human-readable label for structural / metadata columns.
  static const Map<String, String> _metaLabels = {
    'segment_index':   '#',
    'terrain':         'Terrain',
    'is_valid':        'Valid',
    'distance_m':      'Dist (m)',
    'nearest_landmark':'Landmark',
    'sample_count':    'Samples',
    'duration_seconds':'Duration (s)',
    'sample_index':    '#',
    'timestamp':       'Timestamp',
    'segment_id':      'Seg ID',
    'trip_id':         'Trip ID',
    'mode':            'Mode',
    'start_lat':       'Lat Start',
    'start_lon':       'Lon Start',
    'end_lat':         'Lat End',
    'end_lon':         'Lon End',
    'start_time':      'Start ms',
    'end_time':        'End ms',
  };

  String _displayName(String key) =>
      _metaLabels[key] ?? FeatureDisplayUtils.getDisplayName(key);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DbHelper();
    // getSegmentsWithFeaturesForTrip returns all segments with all feature
    // columns merged into one flat map per row.
    var rows = await db.getSegmentsWithFeaturesForTrip(widget.tripId);

    if (rows.isEmpty) {
      final rawSamples = await db.getRawSamplesForTrip(widget.tripId);
      if (rawSamples.isNotEmpty) {
        final rawRows = <Map<String, dynamic>>[];
        for (var index = 0; index < rawSamples.length; index++) {
          final sample = rawSamples[index];
          rawRows.add({
            'sample_index': index + 1,
            'timestamp': sample.timestamp,
            'lat': sample.lat,
            'lon': sample.lon,
            'speed': sample.speed,
            'ax': sample.ax,
            'ay': sample.ay,
            'yaw_rate': sample.yawRate,
            'altitude': sample.altitude,
          });
        }

        if (mounted) {
          setState(() {
            _rawMode = true;
            _allRows = rawRows;
            _columns = const [
              'sample_index',
              'timestamp',
              'lat',
              'lon',
              'speed',
              'ax',
              'ay',
              'yaw_rate',
              'altitude',
            ];
            _sortColumnKey = 'timestamp';
            _loading = false;
          });
        }
        return;
      }

      // If there are no segments locally, avoid fetching remote rows unless
      // the trip metadata indicates it actually has segments. This prevents
      // showing placeholder/fake rows that may exist on Firestore for empty
      // trips. Check local trip metadata first, then remote doc as fallback.
      final localTrip = await db.getDataCollectionTripById(widget.tripId);
      var allowRemoteRows = true;
      if (localTrip != null) {
        final localTotal = (localTrip['total_segments'] as int?) ?? 0;
        if (localTotal == 0) allowRemoteRows = false;
      } else {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('collectionTrips')
              .doc(widget.tripId)
              .get();
          if (doc.exists) {
            final data = doc.data();
            final remoteTotal = (data?['total_segments'] as num?)?.toInt() ??
                (data?['totalSegments'] as num?)?.toInt() ?? 0;
            if (remoteTotal == 0) allowRemoteRows = false;
          }
        } catch (_) {
          // Ignore remote errors; fall back to not showing rows.
          allowRemoteRows = false;
        }
      }

      if (allowRemoteRows) {
        try {
          rows = await FirebaseSyncService.instance.getPublishedCollectionTripRows(widget.tripId);
        } catch (_) {
          // Firestore failed, keep rows empty
        }
      }
    }

    if (rows.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Build an ordered column list: meta columns first, then the 120 feature
    // keys in attribute order, then any remaining columns.
    final rowKeys = rows.first.keys.toSet();
    final featureKeys = FeatureDisplayUtils.allFeatureKeys
        .where(rowKeys.contains)
        .toList();
    final usedKeys = {..._metaFirst, ...featureKeys};
    final remaining = rowKeys
        .where((k) => !usedKeys.contains(k))
        .toList()
      ..sort();

    final columns = [
      ..._metaFirst.where(rowKeys.contains),
      ...featureKeys,
      ...remaining,
    ];

    if (mounted) {
      setState(() {
        _rawMode = false;
        _allRows = rows;
        _columns = columns;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredRows {
    final filtered = _terrainFilter == 'All'
        ? List<Map<String, dynamic>>.from(_allRows)
        : _allRows
            .where((r) => r['terrain']?.toString() == _terrainFilter)
            .toList();

    filtered.sort((a, b) {
      final cmp = _compareValues(a[_sortColumnKey], b[_sortColumnKey]);
      return _sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    if (a is num && b is num) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  void _onSort(String key, bool ascending) {
    setState(() {
      _sortColumnKey = key;
      _sortAscending = ascending;
    });
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final path = await _csvExportService.exportCollectionTripCSV(widget.tripId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV saved to: $path'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Share',
            onPressed: () => Share.shareXFiles([XFile(path)]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openInApp() async {
    setState(() => _exporting = true);
    try {
      final path = await _csvExportService.exportCollectionTripCSV(widget.tripId);
      if (!mounted) return;
      await OpenFile.open(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Open in App',
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: _openInApp,
            ),
            IconButton(
              tooltip: 'Export CSV',
              icon: const Icon(Icons.download_rounded),
              onPressed: _exportCsv,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _allRows.isEmpty
                ? Center(
                    child: Text(
                      'No segment data found for this trip.',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textOnDarkSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      _buildFilterBar(isDark),
                      _buildColumnNote(isDark),
                      Expanded(child: _buildTable(isDark)),
                    ],
                  ),
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    if (_rawMode) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(
              'Raw samples:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.textOnDarkSecondary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_filteredRows.length} rows',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.textOnDarkSecondary
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              'Terrain:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.textOnDarkSecondary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            ..._terrainOptions.map((t) {
              final selected = _terrainFilter == t;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(t, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => setState(() => _terrainFilter = t),
                  selectedColor: AppColors.primary.withOpacity(0.18),
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: selected ? AppColors.primary : null,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }),
            const SizedBox(width: 10),
            Text(
              '${_filteredRows.length} rows',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.textOnDarkSecondary
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnNote(bool isDark) {
    if (_rawMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Showing raw samples — scroll horizontally to see all sensor values',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textMuted,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Showing all ${_columns.length} columns — scroll horizontally to see all features',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildTable(bool isDark) {
    final rows = _filteredRows;
    if (rows.isEmpty) {
      return Center(
        child: Text(
          _rawMode ? 'No raw samples found for this trip.' : 'No segments match the selected filter.',
          style: TextStyle(
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textSecondary,
          ),
        ),
      );
    }

    // Find current sort column index (for DataTable's sortColumnIndex)
    final sortIdx = _columns.indexOf(_sortColumnKey);

    final dataRows = rows.map((r) => _buildDataRow(r, isDark)).toList();
    if (!_rawMode) {
      dataRows.add(_buildMeanRow(rows, isDark));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: sortIdx >= 0 ? sortIdx : null,
          sortAscending: _sortAscending,
          headingRowHeight: 44,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columnSpacing: 16,
          headingTextStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
          ),
          columns: _columns.map((col) {
            return DataColumn(
              label: Text(
                _displayName(col),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
              numeric: _isNumericColumn(col),
              onSort: (_, asc) => _onSort(col, asc),
            );
          }).toList(),
          rows: dataRows,
        ),
      ),
    );
  }

  bool _isNumericColumn(String col) {
    if (_rawMode) {
      return col != 'timestamp';
    }
    if (col == 'terrain' || col == 'nearest_landmark' ||
        col == 'trip_id' || col == 'mode') return false;
    return true;
  }

  DataRow _buildDataRow(Map<String, dynamic> r, bool isDark) {
    if (_rawMode) {
      final textStyle = TextStyle(
        fontSize: 11,
        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
      );

      return DataRow(
        cells: _columns.map((col) {
          final v = r[col];
          if (col == 'timestamp' && v is int) {
            final dt = DateTime.fromMillisecondsSinceEpoch(v);
            return DataCell(Text(
              '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}',
              style: textStyle,
            ));
          }
          if (v == null) {
            return DataCell(Text('', style: textStyle));
          }
          if (v is double) {
            final precision = (col == 'lat' || col == 'lon') ? 6 : 3;
            return DataCell(Text(v.toStringAsFixed(precision), style: textStyle));
          }
          return DataCell(Text(v.toString(), style: textStyle));
        }).toList(),
      );
    }

    final terrain = r['terrain']?.toString() ?? '';
    final terrainColor = AppColors.terrainColor(terrain);
    final isValid = (r['is_valid'] as int? ?? 1) == 1;

    final textStyle = TextStyle(
      fontSize: 11,
      color: isValid
          ? (isDark ? AppColors.textOnDark : AppColors.textPrimary)
          : AppColors.textMuted,
    );

    return DataRow(
      color: WidgetStateProperty.all(
        isValid
            ? Colors.transparent
            : (isDark
                ? Colors.white10
                : Colors.black.withOpacity(0.03)),
      ),
      cells: _columns.map((col) {
        if (col == 'terrain') {
          return DataCell(
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: terrainColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                terrain,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: terrainColor,
                ),
              ),
            ),
          );
        }

        final v = r[col];
        String display;
        if (v == null) {
          display = '';
        } else if (v is double) {
          display = v.toStringAsFixed(3);
        } else {
          display = v.toString();
        }
        return DataCell(Text(display, style: textStyle));
      }).toList(),
    );
  }

  DataRow _buildMeanRow(List<Map<String, dynamic>> rows, bool isDark) {
    if (_rawMode) {
      return DataRow(cells: _columns.map((_) => const DataCell(Text(''))).toList());
    }

    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.primary,
    );

    return DataRow(
      color: WidgetStateProperty.all(AppColors.primary.withOpacity(0.07)),
      cells: _columns.map((col) {
        if (col == 'segment_index') {
          return DataCell(Text('AVG', style: labelStyle));
        }
        if (col == 'terrain' || col == 'nearest_landmark' ||
            col == 'trip_id' || col == 'mode' || col == 'is_valid') {
          return DataCell(Text('—', style: labelStyle));
        }
        // Compute mean for numeric columns
        final nums = rows.map((r) => r[col]).whereType<num>().toList();
        if (nums.isEmpty) {
          return DataCell(Text('—', style: labelStyle));
        }
        final mean = nums.fold(0.0, (a, b) => a + b.toDouble()) / nums.length;
        return DataCell(Text(mean.toStringAsFixed(3), style: labelStyle));
      }).toList(),
    );
  }
}
