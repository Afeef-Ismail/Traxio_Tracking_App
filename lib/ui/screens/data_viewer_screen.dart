import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../../database/db_helper.dart';
import '../../services/csv_export_service.dart';
import '../theme/app_colors.dart';

/// In-app data viewer for a collection trip.
///
/// Loads all segments and their key feature means for the trip,
/// then shows them in a scrollable DataTable with:
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

// One row of data shown in the table.
class _SegmentRow {
  final int index;
  final String terrain;
  final bool isValid;
  final double distance;
  final double speedMean;
  final double ayMean;
  final double axMean;
  final double yrMean;
  final double jxMean;
  final double jyMean;
  final double vvMean;

  const _SegmentRow({
    required this.index,
    required this.terrain,
    required this.isValid,
    required this.distance,
    required this.speedMean,
    required this.ayMean,
    required this.axMean,
    required this.yrMean,
    required this.jxMean,
    required this.jyMean,
    required this.vvMean,
  });
}

class _DataViewerScreenState extends State<DataViewerScreen> {
  bool _loading = true;
  bool _exporting = false;
  List<_SegmentRow> _allRows = [];
  String _terrainFilter = 'All';
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  final CsvExportService _csvExportService = CsvExportService();

  static const List<String> _terrainOptions = ['All', 'Plain', 'Uphill', 'Downhill'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DbHelper();
    final segments = await db.getSegmentsForTrip(widget.tripId);

    final rows = <_SegmentRow>[];
    for (final seg in segments) {
      if (seg.id == null) continue;
      final features = await db.getFeaturesForSegment(seg.id!);

      rows.add(_SegmentRow(
        index: seg.segmentIndex,
        terrain: seg.terrain,
        isValid: seg.isValid,
        distance: seg.distance,
        speedMean: features['Speed_Mean'] ?? 0.0,
        ayMean: features['ay_Mean'] ?? 0.0,
        axMean: features['ax_Mean'] ?? 0.0,
        yrMean: features['YR_Mean'] ?? 0.0,
        jxMean: features['Jx_Mean'] ?? 0.0,
        jyMean: features['Jy_Mean'] ?? 0.0,
        vvMean: features['VV_Mean'] ?? 0.0,
      ));
    }

    if (mounted) {
      setState(() {
        _allRows = rows;
        _loading = false;
      });
    }
  }

  List<_SegmentRow> get _filteredRows {
    final filtered = _terrainFilter == 'All'
        ? List<_SegmentRow>.from(_allRows)
        : _allRows.where((r) => r.terrain == _terrainFilter).toList();

    filtered.sort((a, b) {
      final cmp = _compareByColumn(a, b, _sortColumnIndex);
      return _sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  int _compareByColumn(_SegmentRow a, _SegmentRow b, int col) {
    switch (col) {
      case 0: return a.index.compareTo(b.index);
      case 1: return a.terrain.compareTo(b.terrain);
      case 2: return a.distance.compareTo(b.distance);
      case 3: return a.speedMean.compareTo(b.speedMean);
      case 4: return a.ayMean.compareTo(b.ayMean);
      case 5: return a.axMean.compareTo(b.axMean);
      case 6: return a.yrMean.compareTo(b.yrMean);
      case 7: return a.jxMean.compareTo(b.jxMean);
      case 8: return a.jyMean.compareTo(b.jyMean);
      case 9: return a.vvMean.compareTo(b.vvMean);
      default: return 0;
    }
  }

  void _onSort(int col, bool asc) {
    setState(() {
      _sortColumnIndex = col;
      _sortAscending = asc;
    });
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final path = await _csvExportService.exportTripCSV(widget.tripId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV saved: ${path.split('/').last}'),
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
          content: Text('Export failed: $e'),
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
      final path = await _csvExportService.exportTripCSV(widget.tripId);
      if (!mounted) return;
      await OpenFile.open(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open file: $e'),
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
                      Expanded(
                        child: _buildTable(isDark),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            'Terrain:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
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
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
          const Spacer(),
          Text(
            '${_filteredRows.length} rows',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textOnDarkSecondary : AppColors.textMuted,
            ),
          ),
        ],
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
            color: isDark ? AppColors.textOnDarkSecondary : AppColors.textSecondary,
          ),
        ),
      );
    }

    final dataRows = rows.map((r) => _buildDataRow(r, isDark)).toList();
    dataRows.add(_buildMeanRow(rows, isDark));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          sortColumnIndex: _sortColumnIndex,
          sortAscending: _sortAscending,
          headingRowHeight: 44,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columnSpacing: 16,
          headingTextStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
          ),
          columns: [
            _col('#', 0),
            _col('Terrain', 1),
            _col('Dist (m)', 2),
            _col('Speed\n(km/h)', 3),
            _col('ay\n(g)', 4),
            _col('ax\n(g)', 5),
            _col('YR\n(°/s)', 6),
            _col('Jx\n(g/s)', 7),
            _col('Jy\n(g/s)', 8),
            _col('VV\n(km/h)', 9),
          ],
          rows: dataRows,
        ),
      ),
    );
  }

  DataColumn _col(String label, int index) {
    return DataColumn(
      label: Text(label, textAlign: TextAlign.center),
      numeric: index >= 2,
      onSort: _onSort,
    );
  }

  DataRow _buildDataRow(_SegmentRow r, bool isDark) {
    final terrainColor = AppColors.terrainColor(r.terrain);
    final textStyle = TextStyle(
      fontSize: 12,
      color: r.isValid
          ? (isDark ? AppColors.textOnDark : AppColors.textPrimary)
          : AppColors.textMuted,
    );

    return DataRow(
      color: WidgetStateProperty.all(
        r.isValid
            ? Colors.transparent
            : (isDark ? Colors.white10 : Colors.black.withOpacity(0.03)),
      ),
      cells: [
        DataCell(Text('${r.index + 1}', style: textStyle)),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: terrainColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              r.terrain,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: terrainColor,
              ),
            ),
          ),
        ),
        DataCell(Text(r.distance.toStringAsFixed(1), style: textStyle)),
        DataCell(Text(r.speedMean.toStringAsFixed(2), style: textStyle)),
        DataCell(Text(r.ayMean.toStringAsFixed(3), style: textStyle)),
        DataCell(Text(r.axMean.toStringAsFixed(3), style: textStyle)),
        DataCell(Text(r.yrMean.toStringAsFixed(3), style: textStyle)),
        DataCell(Text(r.jxMean.toStringAsFixed(3), style: textStyle)),
        DataCell(Text(r.jyMean.toStringAsFixed(3), style: textStyle)),
        DataCell(Text(r.vvMean.toStringAsFixed(3), style: textStyle)),
      ],
    );
  }

  DataRow _buildMeanRow(List<_SegmentRow> rows, bool isDark) {
    double mean(double Function(_SegmentRow) f) {
      if (rows.isEmpty) return 0.0;
      return rows.map(f).reduce((a, b) => a + b) / rows.length;
    }

    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.primary,
    );

    return DataRow(
      color: WidgetStateProperty.all(
        AppColors.primary.withOpacity(0.07),
      ),
      cells: [
        DataCell(Text('AVG', style: labelStyle)),
        DataCell(Text('—', style: labelStyle)),
        DataCell(Text(mean((r) => r.distance).toStringAsFixed(1), style: labelStyle)),
        DataCell(Text(mean((r) => r.speedMean).toStringAsFixed(2), style: labelStyle)),
        DataCell(Text(mean((r) => r.ayMean).toStringAsFixed(3), style: labelStyle)),
        DataCell(Text(mean((r) => r.axMean).toStringAsFixed(3), style: labelStyle)),
        DataCell(Text(mean((r) => r.yrMean).toStringAsFixed(3), style: labelStyle)),
        DataCell(Text(mean((r) => r.jxMean).toStringAsFixed(3), style: labelStyle)),
        DataCell(Text(mean((r) => r.jyMean).toStringAsFixed(3), style: labelStyle)),
        DataCell(Text(mean((r) => r.vvMean).toStringAsFixed(3), style: labelStyle)),
      ],
    );
  }
}
