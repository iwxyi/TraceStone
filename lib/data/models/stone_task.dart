enum StoneTaskStatus { active, completed, archived }

class StoneTask {
  const StoneTask({
    required this.id,
    required this.sourceEntryId,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    this.dueDate,
    this.completedAt,
    this.status = StoneTaskStatus.active,
    this.tags = const [],
    this.checkIns = const [],
  });

  final String id;
  final String sourceEntryId;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final StoneTaskStatus status;
  final List<String> tags;
  final List<StoneTaskCheckIn> checkIns;

  bool get isCompleted => status == StoneTaskStatus.completed;

  StoneTask copyWith({
    String? sourceEntryId,
    String? title,
    String? description,
    DateTime? updatedAt,
    DateTime? dueDate,
    DateTime? completedAt,
    StoneTaskStatus? status,
    List<String>? tags,
    List<StoneTaskCheckIn>? checkIns,
    bool clearDueDate = false,
    bool clearCompletedAt = false,
  }) {
    return StoneTask(
      id: id,
      sourceEntryId: sourceEntryId ?? this.sourceEntryId,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      checkIns: checkIns ?? this.checkIns,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceEntryId': sourceEntryId,
        'title': title,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'status': status.name,
        'tags': tags,
        'checkIns': checkIns.map((item) => item.toJson()).toList(),
      };

  static StoneTask fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final statusName = json['status'] as String? ?? StoneTaskStatus.active.name;
    return StoneTask(
      id: json['id'] as String? ?? '',
      sourceEntryId: json['sourceEntryId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      status: StoneTaskStatus.values.firstWhere(
        (item) => item.name == statusName,
        orElse: () => StoneTaskStatus.active,
      ),
      tags: _stringList(json['tags']),
      checkIns: _checkIns(json['checkIns']),
    );
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();

  static List<StoneTaskCheckIn> _checkIns(Object? value) {
    final items = (value as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(StoneTaskCheckIn.fromJson)
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }
}

class StoneTaskCheckIn {
  const StoneTaskCheckIn({
    required this.id,
    required this.createdAt,
    required this.note,
    this.sourceEntryId,
  });

  final String id;
  final DateTime createdAt;
  final String note;
  final String? sourceEntryId;

  StoneTaskCheckIn copyWith({
    String? sourceEntryId,
    bool clearSourceEntryId = false,
  }) {
    return StoneTaskCheckIn(
      id: id,
      createdAt: createdAt,
      note: note,
      sourceEntryId:
          clearSourceEntryId ? null : sourceEntryId ?? this.sourceEntryId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'note': note,
        'sourceEntryId': sourceEntryId,
      };

  static StoneTaskCheckIn fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return StoneTaskCheckIn(
      id: json['id'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      note: json['note'] as String? ?? '',
      sourceEntryId: json['sourceEntryId'] as String?,
    );
  }
}
