import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Color-coded terrain indicator badge.
///
/// Uses strict terrain colors:
///   Plain    → Green (#16A34A)
///   Uphill   → Orange (#EA580C)
///   Downhill → Blue (#2563EB)
class TerrainBadge extends StatelessWidget {
  final String terrain;

  /// Show icon alongside text.
  final bool showIcon;

  /// Large mode for main displays.
  final bool large;

  const TerrainBadge({
    super.key,
    required this.terrain,
    this.showIcon = true,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.terrainColor(terrain);
    final bgColor = AppColors.terrainBgColor(terrain);
    final icon = _terrainIcon(terrain);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 20 : 14,
        vertical: large ? 10 : 6,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(large ? 12 : 8),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              icon,
              color: color,
              size: large ? 22 : 16,
            ),
            SizedBox(width: large ? 8 : 6),
          ],
          Text(
            terrain == 'N/A' ? 'Waiting...' : terrain,
            style: TextStyle(
              color: color,
              fontSize: large ? 18 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _terrainIcon(String terrain) {
    switch (terrain) {
      case 'Plain':
        return Icons.horizontal_rule_rounded;
      case 'Uphill':
        return Icons.trending_up_rounded;
      case 'Downhill':
        return Icons.trending_down_rounded;
      default:
        return Icons.terrain_rounded;
    }
  }
}
