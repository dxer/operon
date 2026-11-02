enum SkillRunStatus {
  idle,
  running,
  completed,
  failed,
  cancelled;

  String get label {
    switch (this) {
      case SkillRunStatus.idle:
        return '待命';
      case SkillRunStatus.running:
        return '执行中';
      case SkillRunStatus.completed:
        return '已完成';
      case SkillRunStatus.failed:
        return '失败';
      case SkillRunStatus.cancelled:
        return '已取消';
    }
  }
}

enum SkillStepStatus {
  pending,
  running,
  succeeded,
  failed,
  skipped,
  cancelled;

  String get label {
    switch (this) {
      case SkillStepStatus.pending:
        return '等待';
      case SkillStepStatus.running:
        return '执行中';
      case SkillStepStatus.succeeded:
        return '成功';
      case SkillStepStatus.failed:
        return '失败';
      case SkillStepStatus.skipped:
        return '跳过';
      case SkillStepStatus.cancelled:
        return '已取消';
    }
  }
}

class SkillStepResult {
  final String stepId;
  final String name;
  final String tool;
  final SkillStepStatus status;
  final dynamic data;
  final String? errorCode;
  final String? errorMessage;
  final int durationMs;
  final Map<String, dynamic> meta;
  final DateTime? startedAt;
  final DateTime? endedAt;

  const SkillStepResult({
    required this.stepId,
    required this.name,
    required this.tool,
    this.status = SkillStepStatus.pending,
    this.data,
    this.errorCode,
    this.errorMessage,
    this.durationMs = 0,
    this.meta = const {},
    this.startedAt,
    this.endedAt,
  });

  bool get isSuccess => status == SkillStepStatus.succeeded;

  SkillStepResult copyWith({
    String? stepId,
    String? name,
    String? tool,
    SkillStepStatus? status,
    dynamic data,
    String? errorCode,
    String? errorMessage,
    int? durationMs,
    Map<String, dynamic>? meta,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return SkillStepResult(
      stepId: stepId ?? this.stepId,
      name: name ?? this.name,
      tool: tool ?? this.tool,
      status: status ?? this.status,
      data: data ?? this.data,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      durationMs: durationMs ?? this.durationMs,
      meta: meta ?? this.meta,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'stepId': stepId,
        'name': name,
        'tool': tool,
        'status': status.name,
        if (data != null) 'data': data,
        if (errorCode != null) 'errorCode': errorCode,
        if (errorMessage != null) 'errorMessage': errorMessage,
        'durationMs': durationMs,
        'meta': meta,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
      };

  factory SkillStepResult.fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString() ?? '';
    final status = SkillStepStatus.values.firstWhere(
      (item) => item.name == statusName,
      orElse: () => SkillStepStatus.pending,
    );
    return SkillStepResult(
      stepId: json['stepId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      tool: json['tool']?.toString() ?? '',
      status: status,
      data: json['data'],
      errorCode: json['errorCode']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : const {},
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
      endedAt: DateTime.tryParse(json['endedAt']?.toString() ?? ''),
    );
  }
}

class SkillRunRecord {
  final String id;
  final String skillId;
  final String skillName;
  final SkillRunStatus status;
  final Map<String, String> inputs;
  final List<SkillStepResult> steps;
  final Map<String, String> output;
  final String? error;
  final String? url;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int llmCalls;
  final int sideEffects;

  const SkillRunRecord({
    required this.id,
    required this.skillId,
    required this.skillName,
    required this.status,
    this.inputs = const {},
    this.steps = const [],
    this.output = const {},
    this.error,
    this.url,
    required this.startedAt,
    this.endedAt,
    this.llmCalls = 0,
    this.sideEffects = 0,
  });

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  SkillRunRecord copyWith({
    String? id,
    String? skillId,
    String? skillName,
    SkillRunStatus? status,
    Map<String, String>? inputs,
    List<SkillStepResult>? steps,
    Map<String, String>? output,
    String? error,
    String? url,
    DateTime? startedAt,
    DateTime? endedAt,
    int? llmCalls,
    int? sideEffects,
  }) {
    return SkillRunRecord(
      id: id ?? this.id,
      skillId: skillId ?? this.skillId,
      skillName: skillName ?? this.skillName,
      status: status ?? this.status,
      inputs: inputs ?? this.inputs,
      steps: steps ?? this.steps,
      output: output ?? this.output,
      error: error ?? this.error,
      url: url ?? this.url,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      llmCalls: llmCalls ?? this.llmCalls,
      sideEffects: sideEffects ?? this.sideEffects,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'skillId': skillId,
        'skillName': skillName,
        'status': status.name,
        'inputs': inputs,
        'steps': steps.map((item) => item.toJson()).toList(),
        'output': output,
        if (error != null) 'error': error,
        if (url != null) 'url': url,
        'startedAt': startedAt.toIso8601String(),
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
        'llmCalls': llmCalls,
        'sideEffects': sideEffects,
      };

  factory SkillRunRecord.fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString() ?? '';
    final status = SkillRunStatus.values.firstWhere(
      (item) => item.name == statusName,
      orElse: () => SkillRunStatus.idle,
    );
    return SkillRunRecord(
      id: json['id']?.toString() ?? '',
      skillId: json['skillId']?.toString() ?? '',
      skillName: json['skillName']?.toString() ?? '',
      status: status,
      inputs: json['inputs'] is Map
          ? Map<String, dynamic>.from(json['inputs'] as Map)
              .map((key, value) => MapEntry(key, '$value'))
          : const {},
      steps: json['steps'] is List
          ? (json['steps'] as List)
              .whereType<Map>()
              .map((item) => SkillStepResult.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const [],
      output: json['output'] is Map
          ? Map<String, dynamic>.from(json['output'] as Map)
              .map((key, value) => MapEntry(key, '$value'))
          : const {},
      error: json['error']?.toString(),
      url: json['url']?.toString(),
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
          DateTime.now(),
      endedAt: DateTime.tryParse(json['endedAt']?.toString() ?? ''),
      llmCalls: (json['llmCalls'] as num?)?.toInt() ?? 0,
      sideEffects: (json['sideEffects'] as num?)?.toInt() ?? 0,
    );
  }
}

class SkillRunState {
  final String runId;
  final String skillId;
  final String skillName;
  final SkillRunStatus status;
  final int currentStep;
  final int totalSteps;
  final String? currentStepName;
  final List<SkillStepResult> results;
  final Map<String, String> output;
  final String? error;
  final String? url;
  final int llmCalls;
  final int sideEffects;

  const SkillRunState({
    required this.runId,
    required this.skillId,
    required this.skillName,
    this.status = SkillRunStatus.idle,
    this.currentStep = 0,
    this.totalSteps = 0,
    this.currentStepName,
    this.results = const [],
    this.output = const {},
    this.error,
    this.url,
    this.llmCalls = 0,
    this.sideEffects = 0,
  });

  bool get isRunning => status == SkillRunStatus.running;

  SkillRunState copyWith({
    String? runId,
    String? skillId,
    String? skillName,
    SkillRunStatus? status,
    int? currentStep,
    int? totalSteps,
    String? currentStepName,
    List<SkillStepResult>? results,
    Map<String, String>? output,
    String? error,
    String? url,
    int? llmCalls,
    int? sideEffects,
  }) {
    return SkillRunState(
      runId: runId ?? this.runId,
      skillId: skillId ?? this.skillId,
      skillName: skillName ?? this.skillName,
      status: status ?? this.status,
      currentStep: currentStep ?? this.currentStep,
      totalSteps: totalSteps ?? this.totalSteps,
      currentStepName: currentStepName ?? this.currentStepName,
      results: results ?? this.results,
      output: output ?? this.output,
      error: error ?? this.error,
      url: url ?? this.url,
      llmCalls: llmCalls ?? this.llmCalls,
      sideEffects: sideEffects ?? this.sideEffects,
    );
  }
}
