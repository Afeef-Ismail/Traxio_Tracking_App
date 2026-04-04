import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../config/constants.dart';
import '../models/trip_model.dart';
import '../providers/trip_provider.dart';
import '../database/db_helper.dart';

/// Service that calls the xAI Grok API to generate a concise AI coaching
/// report for a completed trip.
///
/// Uses the OpenAI-compatible REST API directly.
///
/// Behaviour:
///   - Builds a structured prompt from TripSummary + segment details.
///   - Calls the model with a 30-second timeout; returns null on failure.
///   - Caches the response in the DB `coaching_report` column.
///   - On revisit, returns the cached report instantly.
class GrokCoachingService {
  static final DbHelper _db = DbHelper();

  static String get _apiKey => dotenv.env['GROK_API_KEY'] ?? '';

  /// Get the AI coaching report for a trip.
  /// Returns cached report if available, else generates a new one.
  static Future<String?> getCoachingReport(
    TripSummary summary,
    List<SegmentDetail> segments,
  ) async {
    if (summary.coachingReport.isNotEmpty) {
      return summary.coachingReport;
    }

    final dbSummary = await _db.getTripSummary(summary.tripId);
    if (dbSummary != null && dbSummary.coachingReport.isNotEmpty) {
      return dbSummary.coachingReport;
    }

    return await _generateReport(summary, segments);
  }

  static Future<String?> _generateReport(
    TripSummary summary,
    List<SegmentDetail> segments,
  ) async {
    try {
      final key = _apiKey;
      if (key.isEmpty) {
        print('[GrokCoaching] No API key configured');
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('language_code') ?? 'en';
      final languageInstruction = switch (code) {
        'ml' =>
          'Respond entirely in Malayalam (മലയാളം). Use simple everyday Malayalam that a bus driver can easily understand.',
        'hi' =>
          'Respond entirely in Hindi (हिन्दी). Use simple everyday Hindi that a bus driver can easily understand.',
        _ => 'Respond in English.',
      };
      final prompt =
          '$languageInstruction\n\n${_buildPrompt(summary, segments)}';

      final url = Uri.parse('https://api.x.ai/v1/chat/completions');
      final body = jsonEncode({
        'model': 'grok-3-mini',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.7,
        'max_tokens': 2048,
      });

      print('[GrokCoaching] Sending request...');
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $key',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('[GrokCoaching] HTTP ${response.statusCode}: ${response.body}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;

      final message = choices[0]['message'] as Map<String, dynamic>?;
      final text = message?['content'] as String?;
      if (text == null || text.isEmpty) return null;

      await _db.updateCoachingReport(summary.tripId, text);
      return text;
    } catch (e, st) {
      print('[GrokCoaching] ERROR: $e');
      print(
          '[GrokCoaching] Stack: ${st.toString().split('\n').take(3).join('\n')}');
      return null;
    }
  }

  static String _buildPrompt(
    TripSummary summary,
    List<SegmentDetail> segments,
  ) {
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
