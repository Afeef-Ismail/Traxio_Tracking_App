/// Represents a named master-driver cluster used for deviation scoring.
class ClusterDefinition {
  final int? id;
  final String name;
  final String description;
  final String route;
  final String vehicleType;
  final bool isActive;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  ClusterDefinition({
    this.id,
    required this.name,
    this.description = '',
    this.route = '',
    this.vehicleType = 'Bus',
    this.isActive = true,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'route': route,
      'vehicle_type': vehicleType,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }

  factory ClusterDefinition.fromMap(Map<String, dynamic> map) {
    return ClusterDefinition(
      id: map['id'] as int?,
      name: ((map['name'] as String?) ?? '').trim(),
      description: (map['description'] as String?) ?? '',
      route: (map['route'] as String?) ?? '',
      vehicleType: (map['vehicle_type'] as String?) ?? 'Bus',
      isActive: ((map['is_active'] as int?) ?? 1) == 1,
      createdAt: (map['created_at'] as String?) ?? '',
      updatedAt: (map['updated_at'] as String?) ?? '',
      deletedAt: map['deleted_at'] as String?,
    );
  }

  ClusterDefinition copyWith({
    int? id,
    String? name,
    String? description,
    String? route,
    String? vehicleType,
    bool? isActive,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
  }) {
    return ClusterDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      route: route ?? this.route,
      vehicleType: vehicleType ?? this.vehicleType,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// A single feature range for a cluster on a specific terrain.
class ClusterFeatureRange {
  final int? id;
  final int clusterId;
  final String terrain;
  final String featureName;
  final double minValue;
  final double maxValue;
  final String updatedAt;

  ClusterFeatureRange({
    this.id,
    required this.clusterId,
    required this.terrain,
    required this.featureName,
    required this.minValue,
    required this.maxValue,
    this.updatedAt = '',
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'cluster_id': clusterId,
      'terrain': terrain,
      'feature_name': featureName,
      'min_value': minValue,
      'max_value': maxValue,
      'updated_at': updatedAt,
    };
  }

  factory ClusterFeatureRange.fromMap(Map<String, dynamic> map) {
    return ClusterFeatureRange(
      id: map['id'] as int?,
      clusterId: map['cluster_id'] as int,
      terrain: (map['terrain'] as String?) ?? '',
      featureName: (map['feature_name'] as String?) ?? '',
      minValue: (map['min_value'] as num?)?.toDouble() ?? 0.0,
      maxValue: (map['max_value'] as num?)?.toDouble() ?? 0.0,
      updatedAt: (map['updated_at'] as String?) ?? '',
    );
  }

  ClusterFeatureRange copyWith({
    int? id,
    int? clusterId,
    String? terrain,
    String? featureName,
    double? minValue,
    double? maxValue,
    String? updatedAt,
  }) {
    return ClusterFeatureRange(
      id: id ?? this.id,
      clusterId: clusterId ?? this.clusterId,
      terrain: terrain ?? this.terrain,
      featureName: featureName ?? this.featureName,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
