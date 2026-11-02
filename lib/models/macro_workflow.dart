class MacroStep {
  final String action;
  final String? selector;
  final String? text;
  final String? key;
  final String? direction;
  final String? selectValue;
  final String? url;
  final String description;

  /// Human-readable target label captured during recording.
  final String? targetText;

  /// True for reply/post/pay/delete style steps. Replay must be at-most-once:
  /// never blindly retry them when the outcome is uncertain.
  final bool nonIdempotent;

  const MacroStep({
    required this.action,
    this.selector,
    this.text,
    this.key,
    this.direction,
    this.selectValue,
    this.url,
    required this.description,
    this.targetText,
    this.nonIdempotent = false,
  });

  Map<String, dynamic> toJson() => {
        'action': action,
        if (selector != null) 'selector': selector,
        if (text != null) 'text': text,
        if (key != null) 'key': key,
        if (direction != null) 'direction': direction,
        if (selectValue != null) 'selectValue': selectValue,
        if (url != null) 'url': url,
        'description': description,
        if (targetText != null) 'targetText': targetText,
        'nonIdempotent': nonIdempotent,
      };

  factory MacroStep.fromJson(Map<String, dynamic> json) => MacroStep(
        action: json['action'] ?? 'click',
        selector: json['selector'],
        text: json['text'],
        key: json['key'],
        direction: json['direction'],
        selectValue: json['selectValue']?.toString(),
        url: json['url']?.toString(),
        description: json['description'] ?? '',
        targetText: json['targetText']?.toString(),
        nonIdempotent: json['nonIdempotent'] == true,
      );
}

class MacroWorkflow {
  final String id;
  final String title;
  final String initialUrl;
  final DateTime createdAt;
  final List<MacroStep> steps;

  const MacroWorkflow({
    required this.id,
    required this.title,
    required this.initialUrl,
    required this.createdAt,
    required this.steps,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'initialUrl': initialUrl,
        'createdAt': createdAt.toIso8601String(),
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory MacroWorkflow.fromJson(Map<String, dynamic> json) => MacroWorkflow(
        id: json['id'] ?? '',
        title: json['title'] ?? '未命名宏任务',
        initialUrl: json['initialUrl'] ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        steps: (json['steps'] as List<dynamic>? ?? [])
            .map((s) => MacroStep.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
      );
}
