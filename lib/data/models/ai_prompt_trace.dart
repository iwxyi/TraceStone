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
    this.rawResponsePreview = '',
    this.rawResponseLength = 0,
    this.systemPrompt,
    this.userPrompt,
    this.rawResponse,
  });

  final String id;
  final String scenario;
  final DateTime createdAt;
  final String contextSummary;
  final String systemPromptPreview;
  final String userPromptPreview;
  final int systemPromptLength;
  final int userPromptLength;
  final String rawResponsePreview;
  final int rawResponseLength;
  final String? systemPrompt;
  final String? userPrompt;
  final String? rawResponse;

  Map<String, dynamic> toJson() => {
        'id': id,
        'scenario': scenario,
        'createdAt': createdAt.toIso8601String(),
        'contextSummary': contextSummary,
        'systemPromptPreview': systemPromptPreview,
        'userPromptPreview': userPromptPreview,
        'systemPromptLength': systemPromptLength,
        'userPromptLength': userPromptLength,
        'rawResponsePreview': rawResponsePreview,
        'rawResponseLength': rawResponseLength,
        'systemPrompt': systemPrompt,
        'userPrompt': userPrompt,
        'rawResponse': rawResponse,
      };

  static AiPromptTrace fromJson(Map<String, dynamic> json) {
    return AiPromptTrace(
      id: _stringValue(json['id']),
      scenario: _stringValue(json['scenario']),
      createdAt:
          DateTime.tryParse(_stringValue(json['createdAt'])) ?? DateTime.now(),
      contextSummary: _stringValue(json['contextSummary']),
      systemPromptPreview: _stringValue(json['systemPromptPreview']),
      userPromptPreview: _stringValue(json['userPromptPreview']),
      systemPromptLength: _intValue(json['systemPromptLength']),
      userPromptLength: _intValue(json['userPromptLength']),
      rawResponsePreview: _stringValue(json['rawResponsePreview']),
      rawResponseLength: _intValue(json['rawResponseLength']),
      systemPrompt: _nullableString(json['systemPrompt']),
      userPrompt: _nullableString(json['userPrompt']),
      rawResponse: _nullableString(json['rawResponse']),
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value : value?.toString() ?? '';

  static String? _nullableString(Object? value) =>
      value is String ? value : null;

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
