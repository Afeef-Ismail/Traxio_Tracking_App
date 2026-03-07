/// A single computed feature value for a segment.
class FeatureResult {
  final int? id;
  final int segmentId;
  final String featureName; // e.g. "Speed_Mean", "ay_RMS"
  final double value;

  FeatureResult({
    this.id,
    required this.segmentId,
    required this.featureName,
    required this.value,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'segment_id': segmentId,
      'feature_name': featureName,
      'value': value,
    };
  }

  factory FeatureResult.fromMap(Map<String, dynamic> map) {
    return FeatureResult(
      id: map['id'] as int?,
      segmentId: map['segment_id'] as int,
      featureName: map['feature_name'] as String,
      value: (map['value'] as num).toDouble(),
    );
  }
}

/// Holds all 120 features for a segment, keyed by "Attribute_FeatureName".
class SegmentFeatures {
  final int segmentId;
  final Map<String, double> features;

  SegmentFeatures({
    required this.segmentId,
    required this.features,
  });

  double? get(String key) => features[key];

  List<FeatureResult> toFeatureResults() {
    return features.entries
        .map((e) => FeatureResult(
              segmentId: segmentId,
              featureName: e.key,
              value: e.value,
            ))
        .toList();
  }
}
