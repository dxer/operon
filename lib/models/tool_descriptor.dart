/// Atomic capability contract shared by agents, skills and macros.
///
/// A tool describes *what* can be done, not *how* it is implemented. The
/// implementation lives behind [ToolRegistry] so new capabilities do not
/// require touching every caller.
library;

enum ToolRisk {
  read,
  navigate,
  write,
  destructive;

  bool get isWrite => this == ToolRisk.write || this == ToolRisk.destructive;
}

enum ToolCost { free, llm }

enum ToolAvailability { page, background }

enum ToolParamType {
  text,
  multiline,
  number,
  boolean,
  select,
  locator,
  json,
  secret,
}

class ToolParam {
  final String key;
  final String label;
  final ToolParamType type;
  final bool required;
  final dynamic defaultValue;
  final List<String> options;
  final String? hint;

  const ToolParam({
    required this.key,
    required this.label,
    this.type = ToolParamType.text,
    this.required = false,
    this.defaultValue,
    this.options = const [],
    this.hint,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.name,
        'required': required,
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (options.isNotEmpty) 'options': options,
        if (hint != null) 'hint': hint,
      };

  /// Compact form used in the AI authoring prompt.
  Map<String, dynamic> toPromptJson() => {
        'key': key,
        'type': type.name,
        if (required) 'required': true,
        if (options.isNotEmpty) 'options': options,
      };
}

class ToolDescriptor {
  final String id;
  final String name;
  final String description;
  final ToolRisk risk;
  final ToolCost cost;
  final bool idempotent;
  final bool requiresConfirmation;
  final ToolAvailability availability;
  final List<ToolParam> params;
  final Map<String, dynamic> outputSchema;
  final Duration timeout;

  const ToolDescriptor({
    required this.id,
    required this.name,
    required this.description,
    required this.risk,
    this.cost = ToolCost.free,
    this.idempotent = true,
    this.requiresConfirmation = false,
    this.availability = ToolAvailability.page,
    this.params = const [],
    this.outputSchema = const {},
    this.timeout = const Duration(seconds: 20),
  });

  bool get isWrite => risk.isWrite;

  bool get usesLlm => cost == ToolCost.llm;

  ToolParam? param(String key) {
    for (final item in params) {
      if (item.key == key) return item;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'risk': risk.name,
        'cost': cost.name,
        'idempotent': idempotent,
        'requiresConfirmation': requiresConfirmation,
        'availability': availability.name,
        'params': params.map((item) => item.toJson()).toList(),
        'outputSchema': outputSchema,
        'timeoutMs': timeout.inMilliseconds,
      };

  /// Compact form used in the AI authoring prompt.
  Map<String, dynamic> toPromptJson() => {
        'id': id,
        'risk': risk.name,
        if (cost == ToolCost.llm) 'cost': 'llm',
        'params': params.map((item) => item.toPromptJson()).toList(),
      };
}

/// Uniform result envelope. Every tool returns this shape so retries, audit
/// logs and the UI do not need per-tool branches.
class ToolResult {
  final bool ok;
  final dynamic data;
  final String? errorCode;
  final String? errorMessage;
  final String? url;
  final bool pageChanged;
  final bool sideEffect;
  final int durationMs;
  final Map<String, dynamic> meta;

  const ToolResult({
    required this.ok,
    this.data,
    this.errorCode,
    this.errorMessage,
    this.url,
    this.pageChanged = false,
    this.sideEffect = false,
    this.durationMs = 0,
    this.meta = const {},
  });

  factory ToolResult.success({
    dynamic data,
    String? url,
    bool pageChanged = true,
    bool sideEffect = false,
    int durationMs = 0,
    Map<String, dynamic> meta = const {},
  }) {
    return ToolResult(
      ok: true,
      data: data,
      url: url,
      pageChanged: pageChanged,
      sideEffect: sideEffect,
      durationMs: durationMs,
      meta: meta,
    );
  }

  factory ToolResult.failure(
    String code,
    String message, {
    int durationMs = 0,
    Map<String, dynamic> meta = const {},
  }) {
    return ToolResult(
      ok: false,
      errorCode: code,
      errorMessage: message,
      durationMs: durationMs,
      meta: meta,
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        if (data != null) 'data': data,
        if (errorCode != null) 'errorCode': errorCode,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (url != null) 'url': url,
        'pageChanged': pageChanged,
        'sideEffect': sideEffect,
        'durationMs': durationMs,
        'meta': meta,
      };
}
