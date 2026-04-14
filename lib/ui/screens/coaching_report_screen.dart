import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../providers/trip_provider.dart';
import '../../models/trip_model.dart';
import '../../analytics/coaching_engine.dart';
import '../../analytics/score_calculator.dart';
import '../../services/csv_export_service.dart';
import '../theme/app_colors.dart';

/// Coaching Report Screen — read-only view of cached coaching data
/// for a previously completed trip. Loads everything from the local DB;
/// never makes a network call.
class CoachingReportScreen extends StatefulWidget {
  final String tripId;

  const CoachingReportScreen({super.key, required this.tripId});

  @override
  State<CoachingReportScreen> createState() => _CoachingReportScreenState();
}

class _CoachingReportScreenState extends State<CoachingReportScreen> {
  bool _loading = true;
  bool _exporting = false;
  TripSummary? _summary;
  int _tripScore = -1;
  List<CoachingInsight> _insights = [];
  List<SegmentDetail> _segments = [];
  final CsvExportService _csvExportService = CsvExportService();

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _exportTripCsv() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _exporting = true);
    try {
      final path = await _csvExportService.exportBenchmarkTripCSV(widget.tripId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.csvSaved}: ksrtc_benchmark_${widget.tripId}.csv'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l10n.shareCSV,
            onPressed: () => Share.shareXFiles([XFile(path)]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _loadReport() async {
    final provider = context.read<TripProvider>();
    // Capture l10n synchronously before any await — after an await the context
    // may be detached and AppLocalizations.of(context) can return null.
    final l10n = AppLocalizations.of(context);

    try {
      // 1. Load trip summary from DB
      final summary = await provider.loadTripSummary(widget.tripId);
      if (!mounted) return;

      if (summary == null) {
        setState(() => _loading = false);
        return;
      }

      // 2. Compute score
      final score = summary.score >= 0
          ? summary.score.round()
          : ScoreCalculator.computeScore(summary.overallAvgDeviation);

      // 3. Load segment details from DB
      final segments = await provider.getSegmentDetailsForTrip(widget.tripId);
      if (!mounted) return;

      // 4. Generate rule-based coaching insights (synchronous)
      final insights = CoachingEngine.analyze(summary, segments, l10n: l10n);

      setState(() {
        _summary = summary;
        _tripScore = score;
        _segments = segments;
        _insights = insights;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.coachingReport),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: l10n.exportCSV,
            onPressed: _loading || _exporting ? null : _exportTripCsv,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _summary == null
                ? _buildNotFound(isDark)
                : _buildReport(isDark),
      ),
    );
  }

  // ─── Not-Found State ──────────────────────────────────────────────

  Widget _buildNotFound(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color:
                isDark ? AppColors.textOnDarkSecondary : AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.tripNotFound,
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

  // ─── Report Body ──────────────────────────────────────────────────

  Widget _buildReport(bool isDark) {
    final summary = _summary!;
    final duration = summary.endTime.difference(summary.startTime);
    final dateStr =
        '${summary.startTime.day}/${summary.startTime.month}/${summary.startTime.year}';
    final timeStr =
        '${summary.startTime.hour.toString().padLeft(2, '0')}:${summary.startTime.minute.toString().padLeft(2, '0')}';

    // Find worst segment
    SegmentDetail? worstSeg;
    double worstDev = -1;
    for (final seg in _segments) {
      final d = seg.matchedCluster == 0
          ? seg.cluster0Deviation
          : seg.cluster1Deviation;
      if (d > worstDev) {
        worstDev = d;
        worstSeg = seg;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Score Badge ─────────────────────────────────────────
          if (_tripScore >= 0) ...[
            Center(child: _ScoreBadge(score: _tripScore, isDark: isDark)),
            const SizedBox(height: 20),
          ],

          // ─── Trip Metadata ───────────────────────────────────────
          _SectionTitle(AppLocalizations.of(context)!.tripInformation, isDark: isDark),
          const SizedBox(height: 10),
          _InfoRow('Date', dateStr, isDark: isDark),
          _InfoRow('Time', timeStr, isDark: isDark),
          _InfoRow(
            'Duration',
            _formatDuration(duration),
            isDark: isDark,
          ),
          _InfoRow(
            'Total Segments',
            '${summary.totalSegments}',
            isDark: isDark,
          ),
          _InfoRow(
            'Valid Segments',
            '${summary.validSegments}',
            isDark: isDark,
          ),
          _InfoRow(
            'Overall Deviation',
            summary.overallAvgDeviation.toStringAsFixed(2),
            isDark: isDark,
          ),
          if (summary.driverName.isNotEmpty)
            _InfoRow('Driver', summary.driverName, isDark: isDark),
          if (summary.busNumber.isNotEmpty)
            _InfoRow('Bus', summary.busNumber, isDark: isDark),
          const SizedBox(height: 24),

          // ─── AI Coach (cached from DB) ───────────────────────────
          _SectionTitle(AppLocalizations.of(context)!.aiCoach, isDark: isDark),
          const SizedBox(height: 10),
          if (summary.coachingReport.isNotEmpty)
            _AiCoachCard(report: summary.coachingReport, isDark: isDark)
          else
            _EmptyAiCard(isDark: isDark),
          const SizedBox(height: 20),

          // ─── Rule-Based Coaching Cards ───────────────────────────
          _SectionTitle(AppLocalizations.of(context)!.coachingReport, isDark: isDark),
          const SizedBox(height: 10),
          ..._insights.map(
              (insight) => _CoachingCard(insight: insight, isDark: isDark)),
          const SizedBox(height: 20),

          // ─── Worst Segment Card ──────────────────────────────────
          if (worstSeg != null && worstDev > 10.0) ...[
            _SectionTitle(AppLocalizations.of(context)!.worstSegment, isDark: isDark),
            const SizedBox(height: 10),
            _WorstSegmentCard(
              segment: worstSeg,
              deviation: worstDev,
              isDark: isDark,
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Helper Widgets
// ═══════════════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionTitle(this.title, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _InfoRow(this.label, this.value, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Score Badge ──────────────────────────────────────────────────────

class _ScoreBadge extends StatelessWidget {
  final int score;
  final bool isDark;

  const _ScoreBadge({required this.score, required this.isDark});

  Color get _color {
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 50) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color.withOpacity(0.12),
        border: Border.all(color: _color, width: 4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$score',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: _color,
              height: 1,
            ),
          ),
          Text(
            'SCORE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── AI Coach Card ───────────────────────────────────────────────────

class _AiCoachCard extends StatelessWidget {
  final String report;
  final bool isDark;

  const _AiCoachCard({required this.report, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final sections = _parseSections(report);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'AI Coach',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final section in sections) ...[
            if (section.title.isNotEmpty) ...[
              Text(
                section.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              section.body,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: isDark
                    ? AppColors.textOnDarkSecondary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  List<_ReportSection> _parseSections(String text) {
    final sections = <_ReportSection>[];
    final lines = text.split('\n');
    String currentTitle = '';
    final buffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('SUMMARY:') ||
          trimmed.startsWith('STRENGTHS:') ||
          trimmed.startsWith('IMPROVEMENTS:')) {
        if (currentTitle.isNotEmpty || buffer.isNotEmpty) {
          sections.add(_ReportSection(currentTitle, buffer.toString().trim()));
          buffer.clear();
        }
        final colonIdx = trimmed.indexOf(':');
        currentTitle = trimmed.substring(0, colonIdx);
        final rest = trimmed.substring(colonIdx + 1).trim();
        if (rest.isNotEmpty) buffer.writeln(rest);
      } else {
        buffer.writeln(trimmed);
      }
    }

    if (currentTitle.isNotEmpty || buffer.isNotEmpty) {
      sections.add(_ReportSection(currentTitle, buffer.toString().trim()));
    }

    if (sections.isEmpty) {
      sections.add(_ReportSection('', text));
    }

    return sections;
  }
}

class _ReportSection {
  final String title;
  final String body;
  const _ReportSection(this.title, this.body);
}

// ─── Empty AI Card ───────────────────────────────────────────────────

class _EmptyAiCard extends StatelessWidget {
  final bool isDark;
  const _EmptyAiCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 20,
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI coaching report was not generated for this trip.',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.textOnDarkSecondary
                    : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Coaching Card (rule-based) ──────────────────────────────────────

class _CoachingCard extends StatelessWidget {
  final CoachingInsight insight;
  final bool isDark;

  const _CoachingCard({required this.insight, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final accentColor = _severityColor(insight.severity);
    final icon = _insightIcon(insight.icon);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withOpacity(0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textOnDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark
                        ? AppColors.textOnDarkSecondary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(Severity severity) {
    switch (severity) {
      case Severity.positive:
        return AppColors.success;
      case Severity.neutral:
        return AppColors.primary;
      case Severity.warning:
        return AppColors.warning;
      case Severity.critical:
        return AppColors.alert;
    }
  }

  IconData _insightIcon(InsightIcon icon) {
    switch (icon) {
      case InsightIcon.trophy:
        return Icons.emoji_events_rounded;
      case InsightIcon.thumbsUp:
        return Icons.thumb_up_alt_rounded;
      case InsightIcon.warning:
        return Icons.warning_rounded;
      case InsightIcon.alert:
        return Icons.error_rounded;
      case InsightIcon.terrain:
        return Icons.terrain_rounded;
      case InsightIcon.focus:
        return Icons.center_focus_strong_rounded;
      case InsightIcon.info:
        return Icons.info_rounded;
    }
  }
}

// ─── Worst Segment Card ──────────────────────────────────────────────

class _WorstSegmentCard extends StatelessWidget {
  final SegmentDetail segment;
  final double deviation;
  final bool isDark;

  const _WorstSegmentCard({
    required this.segment,
    required this.deviation,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final terrainColor = AppColors.terrainColor(segment.terrain);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.warning.withOpacity(0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.center_focus_strong_rounded,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Segment #${segment.segmentIndex + 1}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textOnDark
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: terrainColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  segment.terrain,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: terrainColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(
            'Deviation',
            deviation.toStringAsFixed(2),
            isDark: isDark,
          ),
          _InfoRow(
            'Matched Cluster',
            '${segment.matchedCluster}',
            isDark: isDark,
          ),
          if (segment.nearestLandmark.isNotEmpty)
            _InfoRow(
              'Nearest Landmark',
              segment.nearestLandmark,
              isDark: isDark,
            ),
        ],
      ),
    );
  }
}
