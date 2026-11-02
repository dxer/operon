/// A reusable, site-agnostic AI task template.
///
/// Quick commands are not scripts and not macros: they only describe a goal,
/// optional inputs and an execution policy. The agent still observes the page
/// and decides every action, so the same command works on X, Weibo, Reddit or
/// any other site with a similar structure.
library;

enum QuickCommandMode {
  single('单次'),
  batch('批量'),
  paginate('分页');

  final String label;

  const QuickCommandMode(this.label);
}

enum QuickCommandInputType {
  text('单行文本'),
  multiline('多行文本'),
  number('数字'),
  select('单选'),
  toggle('开关');

  final String label;

  const QuickCommandInputType(this.label);
}

class QuickCommandInput {
  final String key;
  final String label;
  final QuickCommandInputType type;
  final String defaultValue;
  final List<String> options;
  final bool required;

  const QuickCommandInput({
    required this.key,
    required this.label,
    this.type = QuickCommandInputType.text,
    this.defaultValue = '',
    this.options = const [],
    this.required = false,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.name,
        'defaultValue': defaultValue,
        'options': options,
        'required': required,
      };

  factory QuickCommandInput.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? '';
    final type = QuickCommandInputType.values.firstWhere(
      (item) => item.name == typeName,
      orElse: () => QuickCommandInputType.text,
    );
    return QuickCommandInput(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: type,
      defaultValue: json['defaultValue']?.toString() ?? '',
      options: (json['options'] is List)
          ? (json['options'] as List).map((e) => e.toString()).toList()
          : const [],
      required: json['required'] == true,
    );
  }

  QuickCommandInput copyWith({
    String? key,
    String? label,
    QuickCommandInputType? type,
    String? defaultValue,
    List<String>? options,
    bool? required,
  }) {
    return QuickCommandInput(
      key: key ?? this.key,
      label: label ?? this.label,
      type: type ?? this.type,
      defaultValue: defaultValue ?? this.defaultValue,
      options: options ?? this.options,
      required: required ?? this.required,
    );
  }
}

class QuickCommandPolicy {
  final QuickCommandMode mode;
  final int maxItems;
  final bool uniqueTarget;
  final bool uniqueContent;
  final int pacingMs;
  final bool confirmBeforeSideEffect;
  final bool showPayloadInConfirmation;
  final int? maxSteps;
  final List<String> stopOn;

  const QuickCommandPolicy({
    this.mode = QuickCommandMode.single,
    this.maxItems = 1,
    this.uniqueTarget = false,
    this.uniqueContent = true,
    this.pacingMs = 0,
    this.confirmBeforeSideEffect = true,
    this.showPayloadInConfirmation = true,
    this.maxSteps,
    this.stopOn = const ['captcha', 'rateLimit', 'error'],
  });

  bool get isBatch => mode != QuickCommandMode.single;

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'maxItems': maxItems,
        'uniqueTarget': uniqueTarget,
        'uniqueContent': uniqueContent,
        'pacingMs': pacingMs,
        'confirmBeforeSideEffect': confirmBeforeSideEffect,
        'showPayloadInConfirmation': showPayloadInConfirmation,
        'maxSteps': maxSteps,
        'stopOn': stopOn,
      };

  factory QuickCommandPolicy.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode']?.toString() ?? '';
    final mode = QuickCommandMode.values.firstWhere(
      (item) => item.name == modeName,
      orElse: () => QuickCommandMode.single,
    );
    final rawStopOn = json['stopOn'];
    return QuickCommandPolicy(
      mode: mode,
      maxItems: (json['maxItems'] as num?)?.toInt() ?? 1,
      uniqueTarget: json['uniqueTarget'] == true,
      uniqueContent: json['uniqueContent'] != false,
      pacingMs: (json['pacingMs'] as num?)?.toInt() ?? 0,
      confirmBeforeSideEffect: json['confirmBeforeSideEffect'] != false,
      showPayloadInConfirmation: json['showPayloadInConfirmation'] != false,
      maxSteps: (json['maxSteps'] as num?)?.toInt(),
      stopOn: rawStopOn is List
          ? rawStopOn.map((e) => e.toString()).toList()
          : const ['captcha', 'rateLimit', 'error'],
    );
  }

  QuickCommandPolicy copyWith({
    QuickCommandMode? mode,
    int? maxItems,
    bool? uniqueTarget,
    bool? uniqueContent,
    int? pacingMs,
    bool? confirmBeforeSideEffect,
    bool? showPayloadInConfirmation,
    int? maxSteps,
    List<String>? stopOn,
  }) {
    return QuickCommandPolicy(
      mode: mode ?? this.mode,
      maxItems: maxItems ?? this.maxItems,
      uniqueTarget: uniqueTarget ?? this.uniqueTarget,
      uniqueContent: uniqueContent ?? this.uniqueContent,
      pacingMs: pacingMs ?? this.pacingMs,
      confirmBeforeSideEffect:
          confirmBeforeSideEffect ?? this.confirmBeforeSideEffect,
      showPayloadInConfirmation:
          showPayloadInConfirmation ?? this.showPayloadInConfirmation,
      maxSteps: maxSteps ?? this.maxSteps,
      stopOn: stopOn ?? this.stopOn,
    );
  }
}

class QuickCommand {
  final String id;
  final String title;
  final String description;
  final String promptTemplate;
  final List<QuickCommandInput> inputs;
  final QuickCommandPolicy policy;
  final bool builtin;
  final int sortOrder;

  const QuickCommand({
    required this.id,
    required this.title,
    required this.description,
    required this.promptTemplate,
    this.inputs = const [],
    this.policy = const QuickCommandPolicy(),
    this.builtin = false,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'promptTemplate': promptTemplate,
        'inputs': inputs.map((e) => e.toJson()).toList(),
        'policy': policy.toJson(),
        'builtin': builtin,
        'sortOrder': sortOrder,
      };

  factory QuickCommand.fromJson(Map<String, dynamic> json) {
    final rawInputs = json['inputs'];
    final rawPolicy = json['policy'];
    return QuickCommand(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名指令',
      description: json['description']?.toString() ?? '',
      promptTemplate: json['promptTemplate']?.toString() ?? '',
      inputs: rawInputs is List
          ? rawInputs
              .whereType<Map>()
              .map((e) => QuickCommandInput.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
      policy: rawPolicy is Map
          ? QuickCommandPolicy.fromJson(Map<String, dynamic>.from(rawPolicy))
          : const QuickCommandPolicy(),
      builtin: json['builtin'] == true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  QuickCommand copyWith({
    String? id,
    String? title,
    String? description,
    String? promptTemplate,
    List<QuickCommandInput>? inputs,
    QuickCommandPolicy? policy,
    bool? builtin,
    int? sortOrder,
  }) {
    return QuickCommand(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      promptTemplate: promptTemplate ?? this.promptTemplate,
      inputs: inputs ?? this.inputs,
      policy: policy ?? this.policy,
      builtin: builtin ?? this.builtin,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Replaces `{{key}}` placeholders with user values or defaults.
  /// Unknown placeholders are removed instead of leaking into the prompt.
  String render([Map<String, String> values = const {}]) {
    var result = promptTemplate;
    for (final input in inputs) {
      final provided = values[input.key];
      final value = (provided == null || provided.trim().isEmpty)
          ? input.defaultValue
          : provided;
      result = result.replaceAll('{{${input.key}}}', value);
    }
    result = result.replaceAll(RegExp(r'\{\{[^}]+\}\}'), '');
    return result.trim();
  }
}
