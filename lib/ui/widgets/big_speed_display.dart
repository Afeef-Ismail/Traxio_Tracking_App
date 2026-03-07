import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Large, centered speed display — the most dominant visual element.
///
/// Shows speed in km/h with 48–64 sp font.
/// Designed for glance-based readability at arm's length.
class BigSpeedDisplay extends StatelessWidget {
  /// Speed value in m/s (will be converted to km/h for display).
  final double speedMs;

  /// Whether to show in compact mode (smaller font).
  final bool compact;

  const BigSpeedDisplay({
    super.key,
    required this.speedMs,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final double kmh = speedMs * 3.6;
    final String speedText = kmh.toStringAsFixed(0);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          speedText,
          style: TextStyle(
            fontSize: compact ? 48 : 64,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            height: 1.0,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'km/h',
          style: TextStyle(
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.textOnDarkSecondary : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
