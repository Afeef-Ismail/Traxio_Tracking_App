import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/trip_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/terrain_badge.dart';
import 'segment_detail_screen.dart';

/// Screen showing all segments for a given trip.
/// Tapping a segment navigates to SegmentDetailScreen.
class SegmentListScreen extends StatefulWidget {
  final String tripId;

  const SegmentListScreen({super.key, required this.tripId});

  @override
  State<SegmentListScreen> createState() => _SegmentListScreenState();
}

class _SegmentListScreenState extends State<SegmentListScreen> {
  List<SegmentDetail> _segments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSegments();
  }

  Future<void> _loadSegments() async {
    final provider = context.read<TripProvider>();
    final segments =
        await provider.getSegmentDetailsForTrip(widget.tripId);
    if (mounted) {
      setState(() {
        _segments = segments;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Segment Analysis'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _segments.isEmpty
                ? _buildEmptyState(isDark)
                : _buildSegmentList(isDark),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.grid_view_rounded,
            size: 64,
            color: isDark
                ? AppColors.textOnDarkSecondary
                : AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'No valid segments found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _segments.length,
      itemBuilder: (context, index) {
        final seg = _segments[index];
        final matchedDev = seg.matchedCluster == 0
            ? seg.cluster0Deviation
            : seg.cluster1Deviation;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SegmentDetailScreen(
                      terrain: seg.terrain,
                      features: seg.features,
                      cluster0Deviation: seg.cluster0Deviation,
                      cluster1Deviation: seg.cluster1Deviation,
                      matchedCluster: seg.matchedCluster,
                      segmentIndex: seg.segmentIndex,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Segment number
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '${seg.segmentIndex + 1}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Terrain + Cluster info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              TerrainBadge(terrain: seg.terrain),
                              const SizedBox(width: 8),
                              Text(
                                'Cluster ${seg.matchedCluster}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? AppColors.textOnDarkSecondary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Deviation: ${matchedDev.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: matchedDev < 5.0
                                  ? AppColors.success
                                  : (matchedDev < 15.0
                                      ? AppColors.warning
                                      : AppColors.alert),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Arrow
                    Icon(
                      Icons.chevron_right_rounded,
                      color: isDark
                          ? AppColors.textOnDarkSecondary
                          : AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
