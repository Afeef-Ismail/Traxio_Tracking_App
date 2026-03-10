import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/trip_model.dart';
import '../providers/trip_provider.dart';
import '../database/db_helper.dart';

/// Service that calls Google Gemini (gemini-2.5-flash) to generate
/// a concise AI coaching report for a completed trip.
///
/// Uses the REST API directly for maximum compatibility.
///
/// Behaviour:
///   - Builds a structured prompt from TripSummary + segment details.
///   - Calls the model with a 30-second timeout; returns null on failure.
///   - Caches the response in the DB `coaching_report` column.
///   - On revisit, returns the cached report instantly.
class GeminiCoachingService {
  static final DbHelper _db = DbHelper();

  /// Get the AI coaching report for a trip.
  /// Returns cached report if available, else generates a new one.
  static Future<String?> getCoachingReport(
    TripSummary summary,
    List<SegmentDetail> segments,
  ) async {
    // Check cache first
    if (summary.coachingReport.isNotEmpty) {
      return summary.coachingReport;
    }

    // Also check DB in case the in-memory model is stale
    final dbSummary = await _db.getTripSummary(summary.tripId);
    if (dbSummary != null && dbSummary.coachingReport.isNotEmpty) {
      return dbSummary.coachingReport;
    }

    // Generate new report
    return await _generateReport(summary, segments);
  }

  /// Build the prompt and call Gemini via REST API.
  static Future<String?> _generateReport(
    TripSummary summary,
    List<SegmentDetail> segments,
  ) async {
    try {
      final prompt = _buildPrompt(summary, segments);
      final apiKey = AppConstants.geminiApiKey;
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
      );

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 2048,
        },
      });

      print('[GeminiCoaching] Sending request...');
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('[GeminiCoaching] HTTP ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        print('[GeminiCoaching] No candidates in response');
        return null;
      }

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        print('[GeminiCoaching] No parts in response');
        return null;
      }

      final text = parts[0]['text'] as String?;
      if (text == null || text.isEmpty) {
        return null;
      }

      // Cache in DB
      await _db.updateCoachingReport(summary.tripId, text);

      return text;
    } catch (e, st) {
      print('[GeminiCoaching] ERROR: $e');
      print('[GeminiCoaching] Stack: ${st.toString().split('\n').take(3).join('\n')}');
      return null;
    }
  }

  /// Build a structured prompt for the AI model.
  static String _buildPrompt(
    TripSummary summary,
    List<SegmentDetail> segments,
  ) {
    // Find worst segment
    String worstTerrain = 'N/A';
    double worstDev = -1;
    String worstLandmark = '';
    int worstIdx = -1;

    for (final seg in segments) {
      final dev = seg.matchedCluster == 0
          ? seg.cluster0Deviation
          : seg.cluster1Deviation;
      if (dev > worstDev) {
        worstDev = dev;
        worstTerrain = seg.terrain;
        worstLandmark = seg.nearestLandmark;
        worstIdx = seg.segmentIndex;
      }
    }

    final score =
        (100.0 - (summary.overallAvgDeviation / AppConstants.maxExpectedDeviation) * 100.0)
            .clamp(0, 100)
            .round();

    return '''
You are an expert bus driving coach for KSRTC (Kerala State Road Transport Corporation).
Analyze this trip data from a bus on the NH-766 (Kozhikode–Sulthan Bathery ghat route)
and provide a brief coaching report.

TRIP DATA:
- Trip Score: $score / 100
- Overall Average Deviation: ${summary.overallAvgDeviation.toStringAsFixed(2)}
- Valid Segments: ${summary.validSegments} / ${summary.totalSegments}
- Plain segments: ${summary.plainSegments} (avg dev: ${summary.avgDeviationPlain.toStringAsFixed(2)})
- Uphill segments: ${summary.uphillSegments} (avg dev: ${summary.avgDeviationUphill.toStringAsFixed(2)})
- Downhill segments: ${summary.downhillSegments} (avg dev: ${summary.avgDeviationDownhill.toStringAsFixed(2)})
- Cluster 0 matches: ${summary.cluster0Matches} (${summary.cluster0Percentage.toStringAsFixed(1)}%)
- Cluster 1 matches: ${summary.cluster1Matches} (${summary.cluster1Percentage.toStringAsFixed(1)}%)
- Worst segment: #${worstIdx + 1}, terrain: $worstTerrain, deviation: ${worstDev.toStringAsFixed(2)}, near: $worstLandmark

RESPOND IN EXACTLY THIS FORMAT (3 short sections, no markdown, plain text only):

SUMMARY: One sentence overall assessment of this trip.

STRENGTHS: 2-3 bullet points starting with "•" highlighting what was done well.

IMPROVEMENTS: 2-3 bullet points starting with "•" with specific, actionable advice referencing terrain types or landmarks where relevant.
''';
  }
}
