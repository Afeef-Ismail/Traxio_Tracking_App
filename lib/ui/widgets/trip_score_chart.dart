import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/trip_model.dart';
import '../theme/app_colors.dart';

/// Line chart showing deviation trend across a driver's trips.
/// X-axis: trip index (oldest → newest, left → right)
/// Y-axis: overall average deviation
class TripScoreHistoryChart extends StatelessWidget {
  final List<TripSummary> trips;

  const TripScoreHistoryChart({super.key, required this.trips});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (trips.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          'No trip data yet',
          style: TextStyle(
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textMuted,
          ),
        ),
      );
    }

    // Reverse to chronological order (oldest first)
    final ordered = trips.reversed.toList();

    // Build data spots
    final spots = <FlSpot>[];
    double maxY = 0;
    for (int i = 0; i < ordered.length; i++) {
      final dev = ordered[i].overallAvgDeviation;
      spots.add(FlSpot(i.toDouble(), dev));
      if (dev > maxY) maxY = dev;
    }

    // Round maxY to nice ceiling
    maxY = ((maxY / 5).ceil() * 5).toDouble();
    if (maxY < 10) maxY = 10;

    return Container(
      height: 220,
      padding: const EdgeInsets.only(right: 16, top: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: isDark
                  ? AppColors.dividerDark
                  : AppColors.dividerLight,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: _bottomInterval(ordered.length),
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= ordered.length) {
                    return const SizedBox.shrink();
                  }
                  final t = ordered[idx];
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${t.startTime.day}/${t.startTime.month}',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? AppColors.textOnDarkSecondary
                            : AppColors.textMuted,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? AppColors.textOnDarkSecondary
                            : AppColors.textMuted,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: AppColors.primary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, idx) {
                  final dev = spot.y;
                  return FlDotCirclePainter(
                    radius: 4,
                    color: _spotColor(dev),
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withOpacity(0.08),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.x.toInt();
                  final trip = idx < ordered.length ? ordered[idx] : null;
                  final date = trip != null
                      ? '${trip.startTime.day}/${trip.startTime.month}'
                      : '';
                  return LineTooltipItem(
                    '$date\nDev: ${spot.y.toStringAsFixed(2)}',
                    TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  Color _spotColor(double dev) {
    if (dev < 5.0) return AppColors.success;
    if (dev < 15.0) return AppColors.warning;
    return AppColors.alert;
  }

  double _bottomInterval(int count) {
    if (count <= 5) return 1;
    if (count <= 10) return 2;
    if (count <= 20) return 4;
    return (count / 5).ceilToDouble();
  }
}
