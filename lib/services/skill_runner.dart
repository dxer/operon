import 'dart:async';
import 'dart:convert';

import '../models/llm_config.dart';
import '../models/skill.dart';
import '../models/skill_run.dart';
import '../models/tool_descriptor.dart';
import '../utils/cancellation.dart';
import '../utils/skill_template.dart';
import '../utils/url_utils.dart';
import 'execution_guard.dart';
import 'llm_service.dart';
import 'skill_inputs.dart';
import 'skill_validator.dart';
import 'tool_registry.dart';
import 'webview_controller_wrapper.dart';

/// Executes a flow skill linearly.
///
/// Instruction skills stay on AgentRunner; this runner never asks a model to
/// choose the next step. AI work is an explicit `ai.generate` tool call.
class SkillRunner {
  final ToolRegistry registry;
  final LlmService llmService;
  final SkillValidator validator;

  SkillRunner({
    ToolRegistry? registry,
    LlmService? llmService,
    SkillValidator? validator,
  })  : registry = registry ?? ToolRegistry(),
        llmService = llmService ?? LlmService(),
        validator = validator ?? SkillValidator();

  Future<SkillRunRecord> run({
    required Skill skill,
    required Map<String, String> inputs,
    required WebViewControllerWrapper webView,
    required LlmConfig config,
    required ExecutionGuard guard,
    Future<void> Function(String title, String markdown)? onShow,
    void Function(SkillRunState state)? onState,
    CancellationToken? token,
    bool dryRun = false,
  }) async {
    final runId = DateTime.now().millisecondsSinceEpoch.toString();
    final startedAt = DateTime.now();
    final cancellation = token ?? CancellationToken();
    guard.confirmDestructive = skill.policy.confirmDestructive;

    if (skill.kind != SkillKind.flow) {
      return _finish(
        id: runId,
        skill: skill,
        startedAt: startedAt,
        status: SkillRunStatus.failed,
        error: '指令型技能应交给 Agent 执行，当前运行器只执行流程型技能。',
        inputs: inputs,
        onState: onState,
      );
    }

    final validation = validator.validate(skill);
    if (validation.hasErrors) {
      return _finish(
        id: runId,
        skill: skill,
        startedAt: startedAt,
        status: SkillRunStatus.failed,
        error: '技能配置不合法：${validation.errors.map((e) => e.message).join('；')}',
        inputs: inputs,
        onState: onState,
      );
    }

    final inputResult = _validateInputs(skill, inputs);
    if (inputResult.error != null) {
      return _finish(
        id: runId,
        skill: skill,
        startedAt: startedAt,
        status: SkillRunStatus.failed,
        error: inputResult.error,
        inputs: inputResult.values,
        onState: onState,
      );
    }

    final values = inputResult.values;
    final startUrl = await _safeUrl(webView);
    final startHost = hostOf(startUrl);
    if (!skill.allowsHostAt(startHost, startHost: startHost)) {
      return _finish(
        id: runId,
        skill: skill,
        startedAt: startedAt,
        status: SkillRunStatus.failed,
        error: '当前站点不在技能允许的范围内：$startHost',
        inputs: values,
        onState: onState,
      );
    }
    final enabledSteps = skill.steps.where((step) => step.enabled).toList();
    final results = <SkillStepResult>[];
    final context = <String, dynamic>{
      'inputs': values,
      'steps': <String, dynamic>{},
      'env': <String, dynamic>{
        'url': startUrl,
        'title': await _safeTitle(webView),
        'now': DateTime.now().toIso8601String(),
      },
      'run': <String, dynamic>{'id': runId},
    };

    var llmCalls = 0;
    var sideEffects = 0;
    var executedCalls = 0;
    DateTime? lastWriteAt;
    // Human confirmation time must not consume the duration budget.
    var waitedMs = 0;
    var waitStartedAt = DateTime.now();
    guard.onWaitStart = () => waitStartedAt = DateTime.now();
    guard.onWaitEnd = () {
      waitedMs += DateTime.now().difference(waitStartedAt).inMilliseconds;
    };

    void emit({
      required SkillRunStatus status,
      required int currentStep,
      String? currentStepName,
      String? error,
      Map<String, String> output = const {},
    }) {
      onState?.call(SkillRunState(
        runId: runId,
        skillId: skill.id,
        skillName: skill.name,
        status: status,
        currentStep: currentStep,
        totalSteps: enabledSteps.length,
        currentStepName: currentStepName,
        results: List.unmodifiable(results),
        output: output,
        error: error,
        url: context['env']?['url']?.toString(),
        llmCalls: llmCalls,
        sideEffects: sideEffects,
      ));
    }

    emit(status: SkillRunStatus.running, currentStep: 0);

    for (var index = 0; index < enabledSteps.length; index++) {
      final step = enabledSteps[index];
      if (cancellation.isCancelled) {
        return _finish(
          id: runId,
          skill: skill,
          startedAt: startedAt,
          status: SkillRunStatus.cancelled,
          inputs: values,
          steps: results,
          llmCalls: llmCalls,
          sideEffects: sideEffects,
          error: '任务已取消',
          onState: onState,
        );
      }
      if (DateTime.now().difference(startedAt).inMilliseconds - waitedMs >
          skill.policy.maxDurationMs) {
        return _finish(
          id: runId,
          skill: skill,
          startedAt: startedAt,
          status: SkillRunStatus.failed,
          inputs: values,
          steps: results,
          llmCalls: llmCalls,
          sideEffects: sideEffects,
          error: '超过本次运行的最长时长',
          onState: onState,
        );
      }

      final tool = registry.descriptor(step.tool);
      if (tool == null) {
        return _finish(
          id: runId,
          skill: skill,
          startedAt: startedAt,
          status: SkillRunStatus.failed,
          inputs: values,
          steps: results,
          llmCalls: llmCalls,
          sideEffects: sideEffects,
          error: '未知工具：${step.tool}',
          onState: onState,
        );
      }

      if (dryRun && tool.isWrite) {
        results.add(SkillStepResult(
          stepId: step.id,
          name: '只读试运行已停止：${step.name}',
          tool: step.tool,
          status: SkillStepStatus.skipped,
          errorMessage: '下一步是写入操作，试运行不会执行',
          startedAt: DateTime.now(),
          endedAt: DateTime.now(),
        ));
        return _finish(
          id: runId,
          skill: skill,
          startedAt: startedAt,
          status: SkillRunStatus.completed,
          inputs: values,
          steps: results,
          llmCalls: llmCalls,
          sideEffects: sideEffects,
          onState: onState,
        );
      }
      if (executedCalls >= skill.policy.maxSteps) {
        return _finish(
          id: runId,
          skill: skill,
          startedAt: startedAt,
          status: SkillRunStatus.failed,
          inputs: values,
          steps: results,
          llmCalls: llmCalls,
          sideEffects: sideEffects,
          error: '已达到本次运行的最大工具调用次数',
          onState: onState,
        );
      }
      if (tool.isWrite && sideEffects >= skill.policy.maxSideEffects) {
        return _finish(
          id: runId,
          skill: skill,
          startedAt: startedAt,
          status: SkillRunStatus.failed,
          inputs: values,
          steps: results,
          llmCalls: llmCalls,
          sideEffects: sideEffects,
          error: '已达到本次运行的写入次数上限',
          onState: onState,
        );
      }

      if (tool.isWrite && skill.policy.pacingMs > 0 && lastWriteAt != null) {
        final elapsed = DateTime.now().difference(lastWriteAt).inMilliseconds;
        final remaining = skill.policy.pacingMs - elapsed;
        if (remaining > 0) {
          await Future.delayed(Duration(milliseconds: remaining));
        }
      }

      Map<String, dynamic> params;
      try {
        params = SkillTemplate.renderParams(step.params, context);
      } catch (e) {
        return _finish(
          id: runId,
          skill: skill,
          startedAt: startedAt,
          status: SkillRunStatus.failed,
          inputs: values,
          steps: results,
          llmCalls: llmCalls,
          sideEffects: sideEffects,
          error: '步骤「${step.name}」参数渲染失败：$e',
          onState: onState,
        );
      }

      if (step.tool == 'page.open') {
        final targetUrl = params['url']?.toString() ?? '';
        final targetHost = hostOf(targetUrl);
        if (targetHost.isNotEmpty &&
            !skill.allowsHostAt(targetHost, startHost: startHost)) {
          return _finish(
            id: runId,
            skill: skill,
            startedAt: startedAt,
            status: SkillRunStatus.failed,
            inputs: values,
            steps: results,
            llmCalls: llmCalls,
            sideEffects: sideEffects,
            error: '步骤「${step.name}」要打开不允许的站点：$targetHost',
            onState: onState,
          );
        }
      }

      emit(
        status: SkillRunStatus.running,
        currentStep: index + 1,
        currentStepName: step.name,
      );

      final stepStarted = DateTime.now();
      final maxAttempts = _maxAttempts(step, tool);
      ToolResult? lastToolResult;
      String? lastError;
      var succeeded = false;
      var attempt = 0;

      while (attempt < maxAttempts) {
        if (cancellation.isCancelled) break;
        if (executedCalls >= skill.policy.maxSteps) {
          lastError = '已达到本次运行的最大工具调用次数';
          break;
        }
        executedCalls++;
        final toolResult = await registry.execute(
          step.tool,
          ToolContext(
            webView: webView,
            llmConfig: config,
            llmService: llmService,
            guard: guard,
            token: cancellation,
            confirmWrites: skill.policy.confirmWrites,
            uniqueTarget: skill.policy.uniqueTarget,
            uniqueContent: skill.policy.uniqueContent,
            onShow: onShow,
            onLog: (message, {bool isError = false}) {},
          ),
          params,
        );
        lastToolResult = toolResult;
        if (toolResult.url != null && toolResult.url!.isNotEmpty) {
          context['env']['url'] = toolResult.url;
          final resultHost = hostOf(toolResult.url!);
          if (!skill.allowsHostAt(resultHost, startHost: startHost)) {
            lastError = '页面跳转到了不允许的站点：$resultHost';
            break;
          }
        }

        if (toolResult.ok) {
          final expectationError = await _checkExpectation(
            step.expect,
            toolResult,
            webView,
          );
          if (expectationError == null) {
            succeeded = true;
            break;
          }
          lastError = expectationError;
        } else {
          lastError = toolResult.errorMessage ?? toolResult.errorCode ?? '未知错误';
        }

        attempt++;
        if (attempt < maxAttempts) {
          await Future.delayed(
              Duration(milliseconds: step.onError.retryDelayMs));
        }
      }

      var result = lastToolResult;
      var finalSucceeded = succeeded;
      if (!succeeded &&
          step.onError.action == StepFailureAction.fallbackAgent) {
        if (executedCalls >= skill.policy.maxSteps) {
          lastError = '已达到本次运行的最大工具调用次数';
        } else {
          executedCalls++;
          final fallbackResult = await registry.execute(
            'agent.task',
            ToolContext(
              webView: webView,
              llmConfig: config,
              llmService: llmService,
              guard: guard,
              token: cancellation,
              confirmWrites: skill.policy.confirmWrites,
              uniqueTarget: skill.policy.uniqueTarget,
              uniqueContent: skill.policy.uniqueContent,
              onShow: onShow,
            ),
            {
              'goal': step.onError.fallbackGoal,
              'tools': step.onError.fallbackTools,
              'maxSteps': step.onError.fallbackMaxSteps,
            },
          );
          result = fallbackResult;
          finalSucceeded = fallbackResult.ok;
          if (!fallbackResult.ok) {
            lastError = fallbackResult.errorMessage ??
                fallbackResult.errorCode ??
                lastError;
          } else {
            lastError = null;
          }
        }
      }
      final stepEnded = DateTime.now();
      final durationMs = stepEnded.difference(stepStarted).inMilliseconds;

      if (tool.usesLlm ||
          step.onError.action == StepFailureAction.fallbackAgent) {
        llmCalls++;
      }
      if (result?.sideEffect == true) sideEffects++;
      if (result != null && result.ok && tool.isWrite) {
        lastWriteAt = stepEnded;
      }

      SkillStepResult stepResult;
      if (finalSucceeded && result != null) {
        final value = <String, dynamic>{
          'ok': true,
          'data': result.data,
          'meta': result.meta,
          'tool': step.tool,
        };
        (context['steps'] as Map<String, dynamic>)[step.id] = value;
        final alias = step.saveAs?.trim();
        if (alias != null && alias.isNotEmpty && alias != step.id) {
          (context['steps'] as Map<String, dynamic>)[alias] = value;
        }
        stepResult = SkillStepResult(
          stepId: step.id,
          name: step.name,
          tool: step.tool,
          status: SkillStepStatus.succeeded,
          data: result.data,
          durationMs: durationMs,
          meta: result.meta,
          startedAt: stepStarted,
          endedAt: stepEnded,
        );
      } else if (step.onError.action == StepFailureAction.skip) {
        stepResult = SkillStepResult(
          stepId: step.id,
          name: step.name,
          tool: step.tool,
          status: SkillStepStatus.skipped,
          errorCode: result?.errorCode,
          errorMessage: lastError,
          durationMs: durationMs,
          meta: result?.meta ?? const {},
          startedAt: stepStarted,
          endedAt: stepEnded,
        );
      } else {
        stepResult = SkillStepResult(
          stepId: step.id,
          name: step.name,
          tool: step.tool,
          status: SkillStepStatus.failed,
          errorCode: result?.errorCode ?? 'EXPECTATION_FAILED',
          errorMessage: lastError,
          durationMs: durationMs,
          meta: result?.meta ?? const {},
          startedAt: stepStarted,
          endedAt: stepEnded,
        );
        results.add(stepResult);
        final cancelled = cancellation.isCancelled;
        return _finish(
          id: runId,
          skill: skill,
          startedAt: startedAt,
          status: cancelled ? SkillRunStatus.cancelled : SkillRunStatus.failed,
          inputs: values,
          steps: results,
          llmCalls: llmCalls,
          sideEffects: sideEffects,
          error: lastError ?? '步骤「${step.name}」执行失败',
          onState: onState,
        );
      }

      results.add(stepResult);
      emit(
        status: SkillRunStatus.running,
        currentStep: index + 1,
        currentStepName: step.name,
      );

      if (cancellation.isCancelled) {
        return _finish(
          id: runId,
          skill: skill,
          startedAt: startedAt,
          status: SkillRunStatus.cancelled,
          inputs: values,
          steps: results,
          llmCalls: llmCalls,
          sideEffects: sideEffects,
          error: '任务已取消',
          onState: onState,
        );
      }
    }

    final output = <String, String>{};
    for (final entry in skill.output.entries) {
      try {
        output[entry.key] = SkillTemplate.renderString(
          entry.value,
          context,
          strict: false,
        );
      } catch (_) {
        output[entry.key] = '';
      }
    }

    final record = SkillRunRecord(
      id: runId,
      skillId: skill.id,
      skillName: skill.name,
      status: SkillRunStatus.completed,
      inputs: _redactInputs(skill, values),
      steps: List.unmodifiable(results),
      output: output,
      url: context['env']?['url']?.toString(),
      startedAt: startedAt,
      endedAt: DateTime.now(),
      llmCalls: llmCalls,
      sideEffects: sideEffects,
    );
    onState?.call(SkillRunState(
      runId: record.id,
      skillId: record.skillId,
      skillName: record.skillName,
      status: record.status,
      currentStep: enabledSteps.length,
      totalSteps: enabledSteps.length,
      results: record.steps,
      output: record.output,
      url: record.url,
      llmCalls: record.llmCalls,
      sideEffects: record.sideEffects,
    ));
    return record;
  }

  int _maxAttempts(SkillStep step, ToolDescriptor tool) {
    if (step.onError.action != StepFailureAction.retry) return 1;
    // Never retry a non-idempotent write: a dispatch after an uncertain failure
    // can duplicate a post/payment.
    if (tool.isWrite && !tool.idempotent) return 1;
    return 1 + step.onError.retryCount.clamp(0, 5);
  }

  Future<String?> _checkExpectation(
    StepExpectation? expectation,
    ToolResult result,
    WebViewControllerWrapper webView,
  ) async {
    if (expectation == null) return null;
    switch (expectation.type) {
      case ExpectationType.dataNotEmpty:
        final value = _readPath(result.data, expectation.path);
        if (!_hasMeaningfulData(value)) return '步骤没有返回预期数据';
        return null;
      case ExpectationType.pageChanged:
        if (!result.pageChanged) return '页面没有发生预期变化';
        return null;
      case ExpectationType.urlContains:
        final expected = expectation.value ?? '';
        final url = result.url ?? '';
        if (!url.contains(expected)) return '当前网址不包含「$expected」';
        return null;
      case ExpectationType.elementExists:
        final raw = expectation.value ?? '';
        if (raw.trim().isEmpty) return '后置条件缺少目标元素';
        try {
          final locator = jsonDecode(raw);
          if (locator is! Map) return '后置条件的元素定位器不合法';
          final resolved = await webView.resolveLocator(
            Map<String, dynamic>.from(locator),
          );
          if (resolved['found'] != true) return '后置条件中的元素不存在';
          return null;
        } catch (_) {
          return '后置条件的元素定位器不合法';
        }
      case ExpectationType.textContains:
        final expected = expectation.value ?? '';
        if (!_stringify(result.data).contains(expected)) {
          return '结果中不包含「$expected」';
        }
        return null;
    }
  }

  dynamic _readPath(dynamic data, String? path) {
    if (path == null || path.trim().isEmpty) return data;
    dynamic current = data;
    for (final segment in path.split('.')) {
      if (current is Map) {
        current = current[segment];
      } else if (current is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= current.length) return null;
        current = current[index];
      } else {
        return null;
      }
    }
    return current;
  }

  bool _hasMeaningfulData(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) {
      for (final key in ['text', 'content', 'summary']) {
        final item = value[key];
        if (item is String && item.trim().isNotEmpty) return true;
      }
      for (final key in ['items', 'links']) {
        final item = value[key];
        if (item is Iterable && item.isNotEmpty) return true;
      }
      if (value['json'] != null) return true;
      return value.isNotEmpty;
    }
    return true;
  }

  String _stringify(dynamic value) {
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }

  _InputResult _validateInputs(Skill skill, Map<String, String> provided) {
    // Start from what the caller supplied so a placeholder-derived value is
    // never dropped, then apply the declared defaults and rules on top.
    final values = <String, String>{
      for (final entry in provided.entries)
        if (entry.key.trim().isNotEmpty) entry.key.trim(): entry.value,
    };
    for (final input in SkillInputs.effective(skill)) {
      final raw = (provided[input.key] ?? '').trim();
      final value = raw.isEmpty ? input.defaultValue.trim() : raw;
      if (input.required && value.isEmpty) {
        return _InputResult(
          values: values,
          error: '请填写「${input.label}」',
        );
      }
      if (input.type == SkillInputType.number && value.isNotEmpty) {
        final parsed = int.tryParse(value);
        if (parsed == null || parsed <= 0) {
          return _InputResult(
            values: values,
            error: '「${input.label}」需要大于 0 的数字',
          );
        }
      }
      if (input.type == SkillInputType.select &&
          input.options.isNotEmpty &&
          value.isNotEmpty &&
          !input.options.contains(value)) {
        return _InputResult(
          values: values,
          error: '「${input.label}」不在可选范围内',
        );
      }
      values[input.key] = value;
    }
    return _InputResult(values: values);
  }

  Map<String, String> _redactInputs(Skill skill, Map<String, String> values) {
    final secretKeys = {
      for (final input in SkillInputs.effective(skill))
        if (input.type == SkillInputType.secret) input.key,
    };
    return {
      for (final entry in values.entries)
        entry.key: secretKeys.contains(entry.key) ? '••••••' : entry.value,
    };
  }

  SkillRunRecord _finish({
    required String id,
    required Skill skill,
    required DateTime startedAt,
    required SkillRunStatus status,
    required Map<String, String> inputs,
    List<SkillStepResult> steps = const [],
    Map<String, String> output = const {},
    String? error,
    int llmCalls = 0,
    int sideEffects = 0,
    void Function(SkillRunState state)? onState,
  }) {
    final record = SkillRunRecord(
      id: id,
      skillId: skill.id,
      skillName: skill.name,
      status: status,
      inputs: _redactInputs(skill, inputs),
      steps: List.unmodifiable(steps),
      output: output,
      error: error,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      llmCalls: llmCalls,
      sideEffects: sideEffects,
    );
    onState?.call(SkillRunState(
      runId: record.id,
      skillId: record.skillId,
      skillName: record.skillName,
      status: record.status,
      currentStep: steps.length,
      totalSteps: skill.steps.where((step) => step.enabled).length,
      results: record.steps,
      output: record.output,
      error: record.error,
      llmCalls: record.llmCalls,
      sideEffects: record.sideEffects,
    ));
    return record;
  }

  Future<String> _safeUrl(WebViewControllerWrapper webView) async {
    try {
      return await webView.getUrl();
    } catch (_) {
      return '';
    }
  }

  Future<String> _safeTitle(WebViewControllerWrapper webView) async {
    try {
      return await webView.getTitle();
    } catch (_) {
      return '';
    }
  }
}

class _InputResult {
  final Map<String, String> values;
  final String? error;

  const _InputResult({required this.values, this.error});
}
