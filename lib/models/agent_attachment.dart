/// One thing the user brought into a task: an image from the phone, or a text
/// file they wanted the model to read alongside the page.
///
/// Kept as data, never as a path: Android hands out cache files that can be
/// cleaned up while a long task is still running, and a task that reads a path
/// halfway through would fail for a reason nobody can see.
class AgentAttachment {
  const AgentAttachment.image({
    required this.name,
    required String this.base64,
    required this.sizeBytes,
  }) : text = null,
       kind = AttachmentKind.image;

  const AgentAttachment.text({
    required this.name,
    required String this.text,
    required this.sizeBytes,
  }) : base64 = null,
       kind = AttachmentKind.text;

  final String name;
  final AttachmentKind kind;

  /// PNG/JPEG bytes, base64. Only for [AttachmentKind.image].
  final String? base64;

  /// Decoded UTF-8. Only for [AttachmentKind.text].
  final String? text;

  final int sizeBytes;

  /// A phone can produce an enormous photo; a provider charges for every pixel.
  static const int maxImageBytes = 4 * 1024 * 1024;

  /// Roughly 8k tokens of Chinese, which is already a large attachment.
  static const int maxTextChars = 20000;

  bool get isImage => kind == AttachmentKind.image;

  /// The extension the data URI should claim.
  String get mimeHint {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get label => '$name · $sizeLabel';

  /// The message part a vision model expects.
  Map<String, Object?> get imagePart => {
        'type': 'image_url',
        'image_url': {'url': 'data:$mimeHint;base64,$base64'},
      };

  /// How the file is introduced to the model. It is file content, so it enters
  /// inside the page-content markers: same rule as a page, same contract.
  String get textBlock => '【附件：$name】\n$text';
}

enum AttachmentKind { image, text }
