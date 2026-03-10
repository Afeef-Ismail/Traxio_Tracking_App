import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../config/constants.dart';

/// Table displaying the 10 benchmark features for a segment.
///
/// Columns: Feature Name | Value | Range | Status
/// Clean, readable layout with no clutter.
class SegmentFeatureTable extends StatelessWidget {
  /// Map of feature key → computed value.
  final Map<String, double> features;

  /// Map of feature key → (clusterMin, clusterMax) for the matched cluster.
  final Map<String, (double, double)>? benchmarkRanges;

  /// The matched cluster index (0 or 1).
  final int? matchedCluster;

  const SegmentFeatureTable({
    super.key,
    required this.features,
    this.benchmarkRanges,
    this.matchedCluster,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final entries = features.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Header ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(isDark ? 0.2 : 0.08),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Feature',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Value',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                  ),
                ),
              ),
              if (benchmarkRanges != null)
                Expanded(
                  flex: 2,
                  child: Text(
                    'Range',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textOnDark
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              const SizedBox(width: 32), // Status column
            ],
          ),
        ),

        // ─── Rows ────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(12),
            ),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            ),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final key = entry.key;
              final value = entry.value;
              final range = benchmarkRanges?[key];
              final bool inRange = range != null
                  ? (value >= range.$1 && value <= range.$2)
                  : true;
              final unit = AppConstants.getFeatureUnit(key);

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    // Feature name
                    Expanded(
                      flex: 3,
                      child: Text(
                        _formatKey(key),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.textOnDark
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // Value with unit
                    Expanded(
                      flex: 2,
                      child: RichText(
                        textAlign: TextAlign.right,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: _formatValue(value),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.textOnDark
                                    : AppColors.textPrimary,
                              ),
                            ),
                            if (unit.isNotEmpty)
                              TextSpan(
                                text: ' $unit',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: isDark
                                      ? AppColors.textOnDarkSecondary
                                      : AppColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Range
                    if (benchmarkRanges != null)
                      Expanded(
                        flex: 2,
                        child: Text(
                          range != null
                              ? '${_formatValue(range.$1)}–${_formatValue(range.$2)}'
                              : '—',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textOnDarkSecondary
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    // Status icon
                    SizedBox(
                      width: 32,
                      child: Icon(
                        inRange
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        size: 18,
                        color: inRange ? AppColors.success : AppColors.alert,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Format feature key from "Speed_Max" → "Speed Max"
  String _formatKey(String key) {
    return key.replaceAll('_', ' ');
  }

  /// Format numeric value to readable string.
  String _formatValue(double v) {
    if (v.abs() >= 100) return v.toStringAsFixed(1);
    if (v.abs() >= 1) return v.toStringAsFixed(2);
    if (v.abs() >= 0.01) return v.toStringAsFixed(3);
    return v.toStringAsFixed(4);
  }
}
