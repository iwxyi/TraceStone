class DiaryAttachment {
  const DiaryAttachment({
    required this.id,
    required this.entryId,
    required this.type,
    required this.fileName,
    required this.mimeType,
    required this.relativePath,
    required this.createdAt,
    this.sizeBytes,
    this.width,
    this.height,
    this.caption,
  });

  final String id;
  final String entryId;
  final DiaryAttachmentType type;
  final String fileName;
  final String mimeType;
  final String relativePath;
  final DateTime createdAt;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final String? caption;

  Map<String, dynamic> toJson() => {
        'id': id,
        'entryId': entryId,
        'type': type.name,
        'fileName': fileName,
        'mimeType': mimeType,
        'relativePath': relativePath,
        'createdAt': createdAt.toIso8601String(),
        'sizeBytes': sizeBytes,
        'width': width,
        'height': height,
        'caption': caption,
      };

  static DiaryAttachment fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'image';
    return DiaryAttachment(
      id: json['id'] as String? ?? '',
      entryId: json['entryId'] as String? ?? '',
      type: DiaryAttachmentType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => DiaryAttachmentType.image,
      ),
      fileName: json['fileName'] as String? ?? 'image',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      relativePath: json['relativePath'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      sizeBytes: json['sizeBytes'] as int?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      caption: json['caption'] as String?,
    );
  }
}

enum DiaryAttachmentType { image }
