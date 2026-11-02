import 'agent_action.dart';

enum AgentStatus {
  idle,
  observing,
  thinking,
  executing,
  waitingConfirmation,
  paused,
  completed,
  error,
}

class AgentLogItem {
  final DateTime timestamp;
  final int step;
  final String title;
  final String? detail;
  final bool isError;

  AgentLogItem({
    required this.step,
    required this.title,
    this.detail,
    this.isError = false,
  }) : timestamp = DateTime.now();
}

class AgentState {
  final AgentStatus status;
  final String goal;
  final int currentStep;
  final int maxSteps;
  final String currentThought;
  final AgentAction? currentAction;
  final dynamic extractedData; // Structured data scraped from the web
  final String? errorMessage;
  final List<AgentLogItem> logs;

  const AgentState({
    this.status = AgentStatus.idle,
    this.goal = '',
    this.currentStep = 0,
    this.maxSteps = 15,
    this.currentThought = '',
    this.currentAction,
    this.extractedData,
    this.errorMessage,
    this.logs = const [],
  });

  bool get isRunning =>
      status == AgentStatus.observing ||
      status == AgentStatus.thinking ||
      status == AgentStatus.executing ||
      status == AgentStatus.waitingConfirmation;

  AgentState copyWith({
    AgentStatus? status,
    String? goal,
    int? currentStep,
    int? maxSteps,
    String? currentThought,
    AgentAction? currentAction,
    dynamic extractedData,
    String? errorMessage,
    List<AgentLogItem>? logs,
  }) {
    return AgentState(
      status: status ?? this.status,
      goal: goal ?? this.goal,
      currentStep: currentStep ?? this.currentStep,
      maxSteps: maxSteps ?? this.maxSteps,
      currentThought: currentThought ?? this.currentThought,
      currentAction: currentAction ?? this.currentAction,
      extractedData: extractedData ?? this.extractedData,
      errorMessage: errorMessage ?? this.errorMessage,
      logs: logs ?? this.logs,
    );
  }
}
