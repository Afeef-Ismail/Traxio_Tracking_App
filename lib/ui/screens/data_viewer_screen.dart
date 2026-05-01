import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../../database/db_helper.dart';
import '../../services/csv_export_service.dart';
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
    final rows = await db.getSegmentsWithFeaturesForTrip(widget.tripId);

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
          'No segments match the selected filter.',
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
    dataRows.add(_buildMeanRow(rows, isDark));

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
    if (col == 'terrain' || col == 'nearest_landmark' ||
        col == 'trip_id' || col == 'mode') return false;
    return true;
  }

  DataRow _buildDataRow(Map<String, dynamic> r, bool isDark) {
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
