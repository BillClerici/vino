class PalateProfile {
  final String id;
  final Map<String, dynamic> preferences;
  final String? lastAnalyzedAt;
  final int analysisVersion;

  const PalateProfile({
    required this.id,
    this.preferences = const {},
    this.lastAnalyzedAt,
    this.analysisVersion = 0,
  });

  factory PalateProfile.fromJson(Map<String, dynamic> json) {
    return PalateProfile(
      id: json['id'] as String,
      preferences: json['preferences'] as Map<String, dynamic>? ?? {},
      lastAnalyzedAt: json['last_analyzed_at'] as String?,
      analysisVersion: json['analysis_version'] as int? ?? 0,
    );
  }
}

class PalateData {
  final PalateProfile profile;
  final Map<String, dynamic> visitStats;
  final List<Map<String, dynamic>> topVarietals;

  const PalateData({
    required this.profile,
    required this.visitStats,
    required this.topVarietals,
  });

  factory PalateData.fromJson(Map<String, dynamic> json) {
    return PalateData(
      profile:
          PalateProfile.fromJson(json['profile'] as Map<String, dynamic>),
      visitStats: json['visit_stats'] as Map<String, dynamic>? ?? {},
      topVarietals: (json['top_varietals'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
    );
  }
}
