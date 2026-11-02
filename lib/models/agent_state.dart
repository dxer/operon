import 'agent_action.dart';
import 'macro_workflow.dart';

enum AgentStatus {
  idle,
  observing,
  thinking,
  executing,
  waitingConfirmation,
  waitingCaptcha,
  paused,
  completed,
  maxStepsReached,
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
  final String? captchaType; // Name of detected CAPTCHA challenge
  final String? errorMessage;
  final String? confirmationReason; // Why the action needs authorization
  final String? targetUrl; // Page URL where the pending action will run
  final List<AgentLogItem> logs;
  final List<MacroStep>
      recordedMacroSteps; // Steps accumulated during execution for Macro export

  const AgentState({
    this.status = AgentStatus.idle,
    this.goal = '',
    this.currentStep = 0,
    this.maxSteps = 15,
    this.currentThought = '',
    this.currentAction,
    this.extractedData,
    this.captchaType,
    this.errorMessage,
    this.confirmationReason,
    this.targetUrl,
    this.logs = const [],
    this.recordedMacroSteps = const [],
  });

  bool get isRunning =>
      status == AgentStatus.observing ||
      status == AgentStatus.thinking ||
      status == AgentStatus.executing ||
      status == AgentStatus.waitingConfirmation ||
      status == AgentStatus.waitingCaptcha;

  AgentState copyWith({
    AgentStatus? status,
    String? goal,
    int? currentStep,
    int? maxSteps,
    String? currentThought,
    AgentAction? currentAction,
    dynamic extractedData,
    String? captchaType,
    String? errorMessage,
    String? confirmationReason,
    String? targetUrl,
    List<AgentLogItem>? logs,
    List<MacroStep>? recordedMacroSteps,
    bool clearCurrentAction = false,
    bool clearCaptchaType = false,
    bool clearErrorMessage = false,
    bool clearExtractedData = false,
    bool clearConfirmationContext = false,
  }) {
    return AgentState(
      status: status ?? this.status,
      goal: goal ?? this.goal,
      currentStep: currentStep ?? this.currentStep,
      maxSteps: maxSteps ?? this.maxSteps,
      currentThought: currentThought ?? this.currentThought,
      currentAction:
          clearCurrentAction ? null : (currentAction ?? this.currentAction),
      extractedData:
          clearExtractedData ? null : (extractedData ?? this.extractedData),
      captchaType: clearCaptchaType ? null : (captchaType ?? this.captchaType),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      confirmationReason: clearConfirmationContext
          ? null
          : (confirmationReason ?? this.confirmationReason),
      targetUrl:
          clearConfirmationContext ? null : (targetUrl ?? this.targetUrl),
      logs: logs ?? this.logs,
      recordedMacroSteps: recordedMacroSteps ?? this.recordedMacroSteps,
    );
  }
}
