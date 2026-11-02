/// A persisted record of one agent task, used for the audit history page.
class AgentTaskRecord {
  final String id;
  final String goal;
  final String status;
  final DateTime startedAt;
  final DateTime endedAt;
  final int steps;
  final int maxSteps;
  final bool safeMode;
  final String? errorMessage;
  final String? targetUrl;
  final List<String> logs;
  final List<String> sensitiveActions;

  const AgentTaskRecord({
    required this.id,
    required this.goal,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.steps,
    required this.maxSteps,
    required this.safeMode,
    this.errorMessage,
    this.targetUrl,
    this.logs = const [],
    this.sensitiveActions = const [],
  });

  Duration get duration => endedAt.difference(startedAt);

  bool get hasSensitiveActions => sensitiveActions.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'goal': goal,
        'status': status,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'steps': steps,
        'maxSteps': maxSteps,
        'safeMode': safeMode,
        'errorMessage': errorMessage,
        'targetUrl': targetUrl,
        'logs': logs,
        'sensitiveActions': sensitiveActions,
      };

  factory AgentTaskRecord.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? value) {
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    List<String> parseList(Object? value) {
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      return const [];
    }

    return AgentTaskRecord(
      id: json['id']?.toString() ?? '',
      goal: json['goal']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      startedAt: parseTime(json['startedAt']),
      endedAt: parseTime(json['endedAt']),
      steps: (json['steps'] as num?)?.toInt() ?? 0,
      maxSteps: (json['maxSteps'] as num?)?.toInt() ?? 0,
      safeMode: json['safeMode'] == true,
      errorMessage: json['errorMessage']?.toString(),
      targetUrl: json['targetUrl']?.toString(),
      logs: parseList(json['logs']),
      sensitiveActions: parseList(json['sensitiveActions']),
    );
  }
}
