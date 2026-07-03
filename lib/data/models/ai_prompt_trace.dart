class AiPromptTrace {
  const AiPromptTrace({
    required this.id,
    required this.scenario,
    required this.createdAt,
    required this.contextSummary,
    required this.systemPromptPreview,
    required this.userPromptPreview,
    required this.systemPromptLength,
    required this.userPromptLength,
    this.systemPrompt,
    this.userPrompt,
  });

  final String id;
  final String scenario;
  final DateTime createdAt;
  final String contextSummary;
  final String systemPromptPreview;
  final String userPromptPreview;
  final int systemPromptLength;
  final int userPromptLength;
  final String? systemPrompt;
  final String? userPrompt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'scenario': scenario,
        'createdAt': createdAt.toIso8601String(),
        'contextSummary': contextSummary,
        'systemPromptPreview': systemPromptPreview,
        'userPromptPreview': userPromptPreview,
        'systemPromptLength': systemPromptLength,
        'userPromptLength': userPromptLength,
        'systemPrompt': systemPrompt,
        'userPrompt': userPrompt,
      };

  static AiPromptTrace fromJson(Map<String, dynamic> json) {
    return AiPromptTrace(
      id: json['id'] as String? ?? '',
      scenario: json['scenario'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      contextSummary: json['contextSummary'] as String? ?? '',
      systemPromptPreview: json['systemPromptPreview'] as String? ?? '',
      userPromptPreview: json['userPromptPreview'] as String? ?? '',
      systemPromptLength: json['systemPromptLength'] as int? ?? 0,
      userPromptLength: json['userPromptLength'] as int? ?? 0,
      systemPrompt: json['systemPrompt'] as String?,
      userPrompt: json['userPrompt'] as String?,
    );
  }
}
