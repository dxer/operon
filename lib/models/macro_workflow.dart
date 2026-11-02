class MacroStep {
  final String action;
  final String? selector;
  final String? text;
  final String? key;
  final String? direction;
  final String description;

  const MacroStep({
    required this.action,
    this.selector,
    this.text,
    this.key,
    this.direction,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'action': action,
        if (selector != null) 'selector': selector,
        if (text != null) 'text': text,
        if (key != null) 'key': key,
        if (direction != null) 'direction': direction,
        'description': description,
      };

  factory MacroStep.fromJson(Map<String, dynamic> json) => MacroStep(
        action: json['action'] ?? 'click',
        selector: json['selector'],
        text: json['text'],
        key: json['key'],
        direction: json['direction'],
        description: json['description'] ?? '',
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
