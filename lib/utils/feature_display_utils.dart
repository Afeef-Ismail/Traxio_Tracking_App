/// Converts raw feature keys (e.g. 'Speed_Max', 'Jy_SpectralEntropy')
/// to human-readable display names (e.g. 'Speed — Maximum').
class FeatureDisplayUtils {
  FeatureDisplayUtils._();

  static const Map<String, String> _attributeNames = {
    'Speed': 'Speed',
    'ay': 'Longitudinal Acceleration',
    'ax': 'Lateral Acceleration',
    'YR': 'Yaw Rate',
    'Jx': 'Lateral Jerk',
    'Jy': 'Longitudinal Jerk',
    'VV': 'Vertical Velocity',
    'R': 'Radius of Turn',
  };

  static const Map<String, String> _featureNames = {
    'Max': 'Maximum',
    'Min': 'Minimum',
    'Mean': 'Mean',
    'Std': 'Standard Deviation',
    'PeakToPeak': 'Peak to Peak',
    'ARV': 'Average Rectified Value',
    'RMS': 'RMS',
    'ShapeFactor': 'Shape Factor',
    'CrestFactor': 'Crest Factor',
    'ImpulseFactor': 'Impulse Factor',
    'MarginFactor': 'Margin Factor',
    'AvgAmplitude': 'Average Amplitude',
    'FreqCentroid': 'Frequency Centroid',
    'FreqVariance': 'Frequency Variance',
    'SpectralEntropy': 'Spectral Entropy',
  };

  /// Converts a raw feature key to a human-readable display name.
  ///
  /// Examples:
  ///   'Speed_Max' → 'Speed — Maximum'
  ///   'Jy_SpectralEntropy' → 'Longitudinal Jerk — Spectral Entropy'
  ///   'ax_FreqVariance' → 'Lateral Acceleration — Frequency Variance'
  static String getDisplayName(String featureKey) {
    final underscoreIndex = featureKey.indexOf('_');
    if (underscoreIndex < 0) return featureKey;

    final attr = featureKey.substring(0, underscoreIndex);
    final feature = featureKey.substring(underscoreIndex + 1);

    final attrDisplay = _attributeNames[attr] ?? attr;
    final featureDisplay = _featureNames[feature] ?? feature;

    return '$attrDisplay — $featureDisplay';
  }

  /// Returns all 120 feature keys in a deterministic order.
  static List<String> get allFeatureKeys {
    const attributes = ['Speed', 'ay', 'ax', 'YR', 'Jx', 'Jy', 'VV', 'R'];
    const features = [
      'Max', 'Min', 'Mean', 'Std', 'PeakToPeak',
      'ARV', 'RMS', 'ShapeFactor', 'CrestFactor', 'ImpulseFactor',
      'MarginFactor', 'AvgAmplitude', 'FreqCentroid', 'FreqVariance',
      'SpectralEntropy',
    ];
    final keys = <String>[];
    for (final attr in attributes) {
      for (final feat in features) {
        keys.add('${attr}_$feat');
      }
    }
    return keys;
  }
}
