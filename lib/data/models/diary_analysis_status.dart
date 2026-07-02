enum DiaryAnalysisState { idle, analyzing, completed, failed }

class DiaryAnalysisStatus {
  const DiaryAnalysisStatus({
    required this.entryId,
    required this.state,
    required this.updatedAt,
    this.message,
  });

  final String entryId;
  final DiaryAnalysisState state;
  final DateTime updatedAt;
  final String? message;

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'state': state.name,
        'updatedAt': updatedAt.toIso8601String(),
        'message': message,
      };

  static DiaryAnalysisStatus fromJson(Map<String, dynamic> json) {
    final stateName = json['state'] as String? ?? DiaryAnalysisState.idle.name;
    return DiaryAnalysisStatus(
      entryId: json['entryId'] as String? ?? '',
      state: DiaryAnalysisState.values.firstWhere(
        (item) => item.name == stateName,
        orElse: () => DiaryAnalysisState.idle,
      ),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      message: json['message'] as String?,
    );
  }
}
