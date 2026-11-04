/// Skill model: an editable, site-agnostic task template.
///
/// A skill is either an `instruction` (the agent decides every action) or a
/// `flow` (a validated sequence of atomic tool calls). Both share the same
/// inputs, policy and run record so the UI and safety layer stay uniform.
library;

import '../utils/url_utils.dart';

enum SkillKind {
  instruction('指令型'),
  flow('流程型');

  final String label;

  const SkillKind(this.label);
}

enum SkillOrigin {
  builtin('内置'),
  user('用户'),
  migrated('迁移'),
  recorded('录制');

  final String label;

  const SkillOrigin(this.label);
}

enum SkillInputType {
  text('单行文本'),
  multiline('多行文本'),
  number('数字'),
  select('单选'),
  toggle('开关'),
  secret('密钥');

  final String label;

  const SkillInputType(this.label);
}

enum SkillHostScope {
  any('任意站点'),
  currentHost('仅当前站点'),
  list('指定站点');

  final String label;

  const SkillHostScope(this.label);
}

class SkillInput {
  final String key;
  final String label;
  final SkillInputType type;
  final String defaultValue;
  final List<String> options;
  final bool required;
  final String? hint;
  final int? maxLength;

  const SkillInput({
    required this.key,
    required this.label,
    this.type = SkillInputType.text,
    this.defaultValue = '',
    this.options = const [],
    this.required = false,
    this.hint,
    this.maxLength,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.name,
        'defaultValue': defaultValue,
        'options': options,
        'required': required,
        if (hint != null) 'hint': hint,
        if (maxLength != null) 'maxLength': maxLength,
      };

  factory SkillInput.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? '';
    final type = SkillInputType.values.firstWhere(
      (item) => item.name == typeName,
      orElse: () => SkillInputType.text,
    );
    return SkillInput(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: type,
      defaultValue: json['defaultValue']?.toString() ?? '',
      options: (json['options'] is List)
          ? (json['options'] as List).map((e) => e.toString()).toList()
          : const [],
      required: json['required'] == true,
      hint: json['hint']?.toString(),
      maxLength: (json['maxLength'] as num?)?.toInt(),
    );
  }

  SkillInput copyWith({
    String? key,
    String? label,
    SkillInputType? type,
    String? defaultValue,
    List<String>? options,
    bool? required,
    String? hint,
    int? maxLength,
  }) {
    return SkillInput(
      key: key ?? this.key,
      label: label ?? this.label,
      type: type ?? this.type,
      defaultValue: defaultValue ?? this.defaultValue,
      options: options ?? this.options,
      required: required ?? this.required,
      hint: hint ?? this.hint,
      maxLength: maxLength ?? this.maxLength,
    );
  }
}

enum StepFailureAction {
  stop,
  skip,
  retry,
  fallbackAgent;

  String get label {
    switch (this) {
      case StepFailureAction.stop:
        return '停止';
      case StepFailureAction.skip:
        return '跳过';
      case StepFailureAction.retry:
        return '重试';
      case StepFailureAction.fallbackAgent:
        return '交给 Agent';
    }
  }
}

class StepFailurePolicy {
  final StepFailureAction action;
  final int retryCount;
  final int retryDelayMs;
  final String fallbackGoal;
  final int fallbackMaxSteps;
  final List<String> fallbackTools;

  const StepFailurePolicy({
    this.action = StepFailureAction.stop,
    this.retryCount = 1,
    this.retryDelayMs = 800,
    this.fallbackGoal = '',
    this.fallbackMaxSteps = 6,
    this.fallbackTools = const [],
  });

  Map<String, dynamic> toJson() => {
        'action': action.name,
        if (action == StepFailureAction.retry) ...{
          'retryCount': retryCount,
          'retryDelayMs': retryDelayMs,
        },
        if (action == StepFailureAction.fallbackAgent) ...{
          'fallbackGoal': fallbackGoal,
          'fallbackMaxSteps': fallbackMaxSteps,
          'fallbackTools': fallbackTools,
        },
      };

  factory StepFailurePolicy.fromJson(Map<String, dynamic> json) {
    final actionName = json['action']?.toString() ?? '';
    final action = StepFailureAction.values.firstWhere(
      (item) => item.name == actionName,
      orElse: () => StepFailureAction.stop,
    );
    return StepFailurePolicy(
      action: action,
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 1,
      retryDelayMs: (json['retryDelayMs'] as num?)?.toInt() ?? 800,
      fallbackGoal: json['fallbackGoal']?.toString() ?? '',
      fallbackMaxSteps: (json['fallbackMaxSteps'] as num?)?.toInt() ?? 6,
      fallbackTools: (json['fallbackTools'] is List)
          ? (json['fallbackTools'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }

  StepFailurePolicy copyWith({
    StepFailureAction? action,
    int? retryCount,
    int? retryDelayMs,
    String? fallbackGoal,
    int? fallbackMaxSteps,
    List<String>? fallbackTools,
  }) {
    return StepFailurePolicy(
      action: action ?? this.action,
      retryCount: retryCount ?? this.retryCount,
      retryDelayMs: retryDelayMs ?? this.retryDelayMs,
      fallbackGoal: fallbackGoal ?? this.fallbackGoal,
      fallbackMaxSteps: fallbackMaxSteps ?? this.fallbackMaxSteps,
      fallbackTools: fallbackTools ?? this.fallbackTools,
    );
  }
}

enum ExpectationType {
  dataNotEmpty,
  pageChanged,
  urlContains,
  elementExists,
  textContains,
}

class StepExpectation {
  final ExpectationType type;
  final String? path;
  final String? value;
  final int timeoutMs;

  const StepExpectation({
    required this.type,
    this.path,
    this.value,
    this.timeoutMs = 3000,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (path != null) 'path': path,
        if (value != null) 'value': value,
        'timeoutMs': timeoutMs,
      };

  factory StepExpectation.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? '';
    final type = ExpectationType.values.firstWhere(
      (item) => item.name == typeName,
      orElse: () => ExpectationType.dataNotEmpty,
    );
    return StepExpectation(
      type: type,
      path: json['path']?.toString(),
      value: json['value']?.toString(),
      timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 3000,
    );
  }
}

class SkillStep {
  final String id;
  final String name;
  final String tool;
  final Map<String, dynamic> params;
  final String? saveAs;
  final StepFailurePolicy onError;
  final StepExpectation? expect;
  final bool enabled;

  const SkillStep({
    required this.id,
    required this.name,
    required this.tool,
    this.params = const {},
    this.saveAs,
    this.onError = const StepFailurePolicy(),
    this.expect,
    this.enabled = true,
  });

  /// Key used by later steps. `saveAs` is the friendly alias, falling back to
  /// the step id. The runtime stores both so either reference works.
  String get contextKey {
    final alias = saveAs?.trim();
    return (alias == null || alias.isEmpty) ? id : alias;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tool': tool,
        'params': params,
        if (saveAs != null && saveAs!.isNotEmpty) 'saveAs': saveAs,
        'onError': onError.toJson(),
        if (expect != null) 'expect': expect!.toJson(),
        'enabled': enabled,
      };

  factory SkillStep.fromJson(Map<String, dynamic> json) {
    final rawParams = json['params'];
    final rawError = json['onError'];
    final rawExpect = json['expect'];
    return SkillStep(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      tool: json['tool']?.toString() ?? '',
      params:
          rawParams is Map ? Map<String, dynamic>.from(rawParams) : const {},
      saveAs: json['saveAs']?.toString(),
      onError: rawError is Map
          ? StepFailurePolicy.fromJson(Map<String, dynamic>.from(rawError))
          : const StepFailurePolicy(),
      expect: rawExpect is Map
          ? StepExpectation.fromJson(Map<String, dynamic>.from(rawExpect))
          : null,
      enabled: json['enabled'] != false,
    );
  }

  SkillStep copyWith({
    String? id,
    String? name,
    String? tool,
    Map<String, dynamic>? params,
    String? saveAs,
    StepFailurePolicy? onError,
    StepExpectation? expect,
    bool? enabled,
    bool clearExpect = false,
  }) {
    return SkillStep(
      id: id ?? this.id,
      name: name ?? this.name,
      tool: tool ?? this.tool,
      params: params ?? this.params,
      saveAs: saveAs ?? this.saveAs,
      onError: onError ?? this.onError,
      expect: clearExpect ? null : (expect ?? this.expect),
      enabled: enabled ?? this.enabled,
    );
  }
}

class SkillPolicy {
  final int maxSteps;
  final int maxSideEffects;
  final int maxItems;
  final int maxDurationMs;
  final int pacingMs;
  final bool uniqueTarget;
  final bool uniqueContent;
  final bool confirmWrites;
  final bool confirmDestructive;
  final List<String> stopOn;
  final SkillHostScope hostScope;
  final List<String> allowedHosts;

  const SkillPolicy({
    this.maxSteps = 40,
    this.maxSideEffects = 10,
    this.maxItems = 1,
    // A single model call may take up to 3 minutes and may be retried once,
    // so a shorter budget could fail right after a slow successful call.
    this.maxDurationMs = 600000,
    this.pacingMs = 0,
    this.uniqueTarget = false,
    this.uniqueContent = false,
    this.confirmWrites = true,
    this.confirmDestructive = true,
    this.stopOn = const ['captcha', 'rateLimit', 'error'],
    this.hostScope = SkillHostScope.any,
    this.allowedHosts = const [],
  });

  Map<String, dynamic> toJson() => {
        'maxSteps': maxSteps,
        'maxSideEffects': maxSideEffects,
        'maxItems': maxItems,
        'maxDurationMs': maxDurationMs,
        'pacingMs': pacingMs,
        'uniqueTarget': uniqueTarget,
        'uniqueContent': uniqueContent,
        'confirmWrites': confirmWrites,
        'confirmDestructive': confirmDestructive,
        'stopOn': stopOn,
        'hostScope': hostScope.name,
        'allowedHosts': allowedHosts,
      };

  factory SkillPolicy.fromJson(Map<String, dynamic> json) {
    final scopeName = json['hostScope']?.toString() ?? '';
    final scope = SkillHostScope.values.firstWhere(
      (item) => item.name == scopeName,
      orElse: () => SkillHostScope.any,
    );
    final rawStopOn = json['stopOn'];
    final rawHosts = json['allowedHosts'];
    return SkillPolicy(
      maxSteps: (json['maxSteps'] as num?)?.toInt() ?? 40,
      maxSideEffects: (json['maxSideEffects'] as num?)?.toInt() ?? 10,
      maxItems: (json['maxItems'] as num?)?.toInt() ?? 1,
      maxDurationMs: (json['maxDurationMs'] as num?)?.toInt() ?? 600000,
      pacingMs: (json['pacingMs'] as num?)?.toInt() ?? 0,
      uniqueTarget: json['uniqueTarget'] == true,
      uniqueContent: json['uniqueContent'] == true,
      confirmWrites: json['confirmWrites'] != false,
      confirmDestructive: json['confirmDestructive'] != false,
      stopOn: rawStopOn is List
          ? rawStopOn.map((e) => e.toString()).toList()
          : const ['captcha', 'rateLimit', 'error'],
      hostScope: scope,
      allowedHosts: rawHosts is List
          ? rawHosts.map((e) => e.toString()).toList()
          : const [],
    );
  }

  /// True when this policy declares a site restriction.
  bool get isSiteScoped =>
      hostScope != SkillHostScope.any && allowedHosts.isNotEmpty;

  /// Whether this policy allows [host].
  ///
  /// `any` and a scope without recorded hosts are not restrictions: there is
  /// nothing to compare against, so the skill runs anywhere. This is the only
  /// host check in the app; the agent, the flow runner and the skill list all
  /// defer to it.
  bool allowsHost(String? host) {
    if (!isSiteScoped) return true;
    final current = normalizeHostInput(host ?? '');
    if (current.isEmpty) return false;
    return allowedHosts.any((item) => hostMatches(item, current));
  }

  /// Whether this policy allows [host] given the site the run started on.
  ///
  /// Recorded hosts always win: they are a hard list. `currentHost` with no
  /// recorded hosts means "stay on the page the run started from", which only
  /// the runners can evaluate. Anything else allows every host.
  bool allowsHostAt(String? host, {String? startHost}) {
    if (isSiteScoped) return allowsHost(host);
    if (hostScope != SkillHostScope.currentHost) return true;
    final start = normalizeHostInput(startHost ?? '');
    // No start page recorded yet: there is no rule to apply.
    if (start.isEmpty) return true;
    final current = normalizeHostInput(host ?? '');
    return current.isEmpty || current == start;
  }

  /// Exact match, or a `*.domain` suffix that also covers the bare domain.
  static bool hostMatches(String pattern, String host) {
    final value = normalizeHostInput(pattern);
    if (value.isEmpty) return false;
    if (value.startsWith('*.')) {
      final suffix = value.substring(2);
      return host == suffix || host.endsWith('.$suffix');
    }
    return value == host;
  }

  SkillPolicy copyWith({
    int? maxSteps,
    int? maxSideEffects,
    int? maxItems,
    int? maxDurationMs,
    int? pacingMs,
    bool? uniqueTarget,
    bool? uniqueContent,
    bool? confirmWrites,
    bool? confirmDestructive,
    List<String>? stopOn,
    SkillHostScope? hostScope,
    List<String>? allowedHosts,
  }) {
    return SkillPolicy(
      maxSteps: maxSteps ?? this.maxSteps,
      maxSideEffects: maxSideEffects ?? this.maxSideEffects,
      maxItems: maxItems ?? this.maxItems,
      maxDurationMs: maxDurationMs ?? this.maxDurationMs,
      pacingMs: pacingMs ?? this.pacingMs,
      uniqueTarget: uniqueTarget ?? this.uniqueTarget,
      uniqueContent: uniqueContent ?? this.uniqueContent,
      confirmWrites: confirmWrites ?? this.confirmWrites,
      confirmDestructive: confirmDestructive ?? this.confirmDestructive,
      stopOn: stopOn ?? this.stopOn,
      hostScope: hostScope ?? this.hostScope,
      allowedHosts: allowedHosts ?? this.allowedHosts,
    );
  }
}

class Skill {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String id;
  final String name;
  final String description;
  final SkillKind kind;
  final SkillOrigin origin;
  final int version;
  final List<SkillInput> inputs;
  final String instructions;
  final List<SkillStep> steps;
  final Map<String, String> output;
  final SkillPolicy policy;
  final bool builtin;
  final int sortOrder;
  final DateTime? updatedAt;

  const Skill({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.name,
    this.description = '',
    this.kind = SkillKind.instruction,
    this.origin = SkillOrigin.user,
    this.version = 1,
    this.inputs = const [],
    this.instructions = '',
    this.steps = const [],
    this.output = const {},
    this.policy = const SkillPolicy(),
    this.builtin = false,
    this.sortOrder = 0,
    this.updatedAt,
  });

  bool get isFlow => kind == SkillKind.flow;

  bool get isInstruction => kind == SkillKind.instruction;

  /// Whether this skill may run on [host]. Delegates to the policy so the
  /// agent, the flow runner and the skill list share one rule.
  bool allowsHost(String? host) => policy.allowsHost(host);

  /// Run-time variant of [allowsHost] for `currentHost` skills.
  bool allowsHostAt(String? host, {String? startHost}) =>
      policy.allowsHostAt(host, startHost: startHost);

  /// Whether this skill is specifically meant for [host]. General skills
  /// return false; callers show them after site-specific skills.
  bool matchesHost(String? host) => policy.isSiteScoped && policy.allowsHost(host);

  bool get hasWriteSteps => steps.any((step) {
        // Imported lazily to avoid a model cycle: tool metadata is optional
        // here, but the validator checks the real catalog.
        return step.tool == 'page.click' ||
            step.tool == 'page.type' ||
            step.tool == 'page.press_key' ||
            step.tool == 'page.select' ||
            step.tool == 'page.hover' ||
            step.tool == 'macro.run' ||
            step.tool == 'agent.task';
      });

  SkillStep? stepById(String id) {
    for (final step in steps) {
      if (step.id == id) return step;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'description': description,
        'kind': kind.name,
        'origin': origin.name,
        'version': version,
        'inputs': inputs.map((item) => item.toJson()).toList(),
        'instructions': instructions,
        'steps': steps.map((item) => item.toJson()).toList(),
        'output': output,
        'policy': policy.toJson(),
        'builtin': builtin,
        'sortOrder': sortOrder,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  factory Skill.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind']?.toString() ?? '';
    final kind = SkillKind.values.firstWhere(
      (item) => item.name == kindName,
      orElse: () => SkillKind.instruction,
    );
    final originName = json['origin']?.toString() ?? '';
    final origin = SkillOrigin.values.firstWhere(
      (item) => item.name == originName,
      orElse: () => SkillOrigin.user,
    );
    final rawInputs = json['inputs'];
    final rawSteps = json['steps'];
    final rawOutput = json['output'];
    final rawPolicy = json['policy'];
    return Skill(
      schemaVersion:
          (json['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion,
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名技能',
      description: json['description']?.toString() ?? '',
      kind: kind,
      origin: origin,
      version: (json['version'] as num?)?.toInt() ?? 1,
      inputs: rawInputs is List
          ? rawInputs
              .whereType<Map>()
              .map((item) => SkillInput.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
      instructions: json['instructions']?.toString() ?? '',
      steps: rawSteps is List
          ? rawSteps
              .whereType<Map>()
              .map((item) => SkillStep.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
      output: rawOutput is Map
          ? rawOutput.map((key, value) => MapEntry(key.toString(), '$value'))
          : const {},
      policy: rawPolicy is Map
          ? SkillPolicy.fromJson(Map<String, dynamic>.from(rawPolicy))
          : const SkillPolicy(),
      builtin: json['builtin'] == true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  Skill copyWith({
    int? schemaVersion,
    String? id,
    String? name,
    String? description,
    SkillKind? kind,
    SkillOrigin? origin,
    int? version,
    List<SkillInput>? inputs,
    String? instructions,
    List<SkillStep>? steps,
    Map<String, String>? output,
    SkillPolicy? policy,
    bool? builtin,
    int? sortOrder,
    DateTime? updatedAt,
  }) {
    return Skill(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      kind: kind ?? this.kind,
      origin: origin ?? this.origin,
      version: version ?? this.version,
      inputs: inputs ?? this.inputs,
      instructions: instructions ?? this.instructions,
      steps: steps ?? this.steps,
      output: output ?? this.output,
      policy: policy ?? this.policy,
      builtin: builtin ?? this.builtin,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  SkillDraft toDraft() {
    return SkillDraft(
      name: name,
      description: description,
      kind: kind,
      inputs: inputs,
      instructions: instructions,
      steps: steps,
      policy: policy,
    );
  }
}

/// An AI-authored, not-yet-saved skill. Kept separate from [Skill] so drafts
/// can never be mistaken for persisted data.
class SkillDraft {
  final String name;
  final String description;
  final SkillKind kind;
  final List<SkillInput> inputs;
  final String instructions;
  final List<SkillStep> steps;
  final SkillPolicy policy;
  final String notes;

  const SkillDraft({
    required this.name,
    this.description = '',
    this.kind = SkillKind.instruction,
    this.inputs = const [],
    this.instructions = '',
    this.steps = const [],
    this.policy = const SkillPolicy(),
    this.notes = '',
  });

  Skill toSkill({
    required String id,
    SkillOrigin origin = SkillOrigin.user,
    bool builtin = false,
    int sortOrder = 0,
  }) {
    return Skill(
      id: id,
      name: name,
      description: description,
      kind: kind,
      origin: origin,
      inputs: inputs,
      instructions: instructions,
      steps: steps,
      policy: policy,
      builtin: builtin,
      sortOrder: sortOrder,
      updatedAt: DateTime.now(),
    );
  }

  SkillDraft copyWith({
    String? name,
    String? description,
    SkillKind? kind,
    List<SkillInput>? inputs,
    String? instructions,
    List<SkillStep>? steps,
    SkillPolicy? policy,
    String? notes,
  }) {
    return SkillDraft(
      name: name ?? this.name,
      description: description ?? this.description,
      kind: kind ?? this.kind,
      inputs: inputs ?? this.inputs,
      instructions: instructions ?? this.instructions,
      steps: steps ?? this.steps,
      policy: policy ?? this.policy,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'kind': kind.name,
        'inputs': inputs.map((item) => item.toJson()).toList(),
        'instructions': instructions,
        'steps': steps.map((item) => item.toJson()).toList(),
        'policy': policy.toJson(),
        if (notes.isNotEmpty) 'notes': notes,
      };

  factory SkillDraft.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind']?.toString() ?? '';
    final kind = SkillKind.values.firstWhere(
      (item) => item.name == kindName,
      orElse: () => SkillKind.instruction,
    );
    final rawInputs = json['inputs'];
    final rawSteps = json['steps'];
    final rawPolicy = json['policy'];
    return SkillDraft(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      kind: kind,
      inputs: rawInputs is List
          ? rawInputs
              .whereType<Map>()
              .map((item) => SkillInput.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
      instructions: json['instructions']?.toString() ?? '',
      steps: rawSteps is List
          ? rawSteps
              .whereType<Map>()
              .map((item) => SkillStep.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
      policy: rawPolicy is Map
          ? SkillPolicy.fromJson(Map<String, dynamic>.from(rawPolicy))
          : const SkillPolicy(),
      notes: json['notes']?.toString() ?? '',
    );
  }
}
