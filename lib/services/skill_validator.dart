import 'dart:convert';

import '../config/tool_catalog.dart';
import '../models/skill.dart';
import '../models/tool_descriptor.dart';
import '../utils/skill_template.dart';
import '../utils/url_utils.dart';
import 'skill_inputs.dart';

enum SkillIssueSeverity { error, warning }

class SkillIssueCode {
  static const nameEmpty = 'NAME_EMPTY';
  static const nameTooLong = 'NAME_TOO_LONG';
  static const descriptionTooLong = 'DESCRIPTION_TOO_LONG';
  static const instructionEmpty = 'INSTRUCTION_EMPTY';
  static const instructionHasSteps = 'INSTRUCTION_HAS_STEPS';
  static const flowEmpty = 'FLOW_EMPTY';
  static const flowTooManySteps = 'FLOW_TOO_MANY_STEPS';
  static const stepIdEmpty = 'STEP_ID_EMPTY';
  static const stepIdDuplicate = 'STEP_ID_DUPLICATE';
  static const stepAliasDuplicate = 'STEP_ALIAS_DUPLICATE';
  static const stepNameEmpty = 'STEP_NAME_EMPTY';
  static const toolMissing = 'TOOL_MISSING';
  static const toolUnknown = 'TOOL_UNKNOWN';
  static const toolNotAvailable = 'TOOL_NOT_AVAILABLE';
  static const paramMissing = 'PARAM_MISSING';
  static const paramType = 'PARAM_TYPE';
  static const paramUnknown = 'PARAM_UNKNOWN';
  static const inputKeyEmpty = 'INPUT_KEY_EMPTY';
  static const inputKeyInvalid = 'INPUT_KEY_INVALID';
  static const inputKeyDuplicate = 'INPUT_KEY_DUPLICATE';
  static const inputSelectEmpty = 'INPUT_SELECT_EMPTY';
  static const inputDefaultNotInOptions = 'INPUT_DEFAULT_NOT_IN_OPTIONS';
  static const secretDefault = 'SECRET_DEFAULT';
  static const variableUnknown = 'VARIABLE_UNKNOWN';
  static const variableStepUnknown = 'VARIABLE_STEP_UNKNOWN';
  static const variableForwardReference = 'VARIABLE_FORWARD_REFERENCE';
  static const variableControlFlow = 'VARIABLE_CONTROL_FLOW';
  static const locatorInvalid = 'LOCATOR_INVALID';
  static const locatorSemanticOnly = 'LOCATOR_SEMANTIC_ONLY';
  static const locatorNotUnique = 'LOCATOR_NOT_UNIQUE';
  static const urlInvalid = 'URL_INVALID';
  static const urlPageData = 'URL_PAGE_DATA';
  static const urlOutsideScope = 'URL_OUTSIDE_SCOPE';
  static const pageDataSubmit = 'PAGE_DATA_SUBMIT';
  static const promptPageData = 'PROMPT_PAGE_DATA';
  static const secretLiteral = 'SECRET_LITERAL';
  static const writesNotAllowed = 'WRITES_NOT_ALLOWED';
  static const writeScopeNotRestricted = 'WRITE_SCOPE_NOT_RESTRICTED';
  static const policySteps = 'POLICY_STEPS';
  static const policySideEffects = 'POLICY_SIDE_EFFECTS';
  static const policyItems = 'POLICY_ITEMS';
  static const policyDuration = 'POLICY_DURATION';
  static const policyPacing = 'POLICY_PACING';
  static const policyHostScope = 'POLICY_HOST_SCOPE';
  static const policyHostInvalid = 'POLICY_HOST_INVALID';
  static const writesAnyHost = 'WRITES_ANY_HOST';
  static const confirmWritesOff = 'CONFIRM_WRITES_OFF';
  static const confirmDestructiveOff = 'CONFIRM_DESTRUCTIVE_OFF';
  static const outputKeyInvalid = 'OUTPUT_KEY_INVALID';
  static const expectMissingValue = 'EXPECT_MISSING_VALUE';
  static const fallbackGoalEmpty = 'FALLBACK_GOAL_EMPTY';
  static const fallbackTool = 'FALLBACK_TOOL';
  static const fallbackSteps = 'FALLBACK_STEPS';
}

class SkillValidationIssue {
  final String code;
  final String message;
  final SkillIssueSeverity severity;
  final String? stepId;
  final String? field;

  const SkillValidationIssue({
    required this.code,
    required this.message,
    this.severity = SkillIssueSeverity.error,
    this.stepId,
    this.field,
  });

  bool get isError => severity == SkillIssueSeverity.error;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'severity': severity.name,
        if (stepId != null) 'stepId': stepId,
        if (field != null) 'field': field,
      };
}

class SkillValidationResult {
  final List<SkillValidationIssue> issues;

  const SkillValidationResult(this.issues);

  bool get hasErrors => issues.any((item) => item.isError);

  List<SkillValidationIssue> get errors =>
      issues.where((item) => item.isError).toList();

  List<SkillValidationIssue> get warnings =>
      issues.where((item) => !item.isError).toList();

  bool get isClean => issues.isEmpty;

  /// Compact text suitable for feeding validation failures back to the model.
  String get repairHint {
    if (issues.isEmpty) return '无问题';
    return issues
        .map((item) =>
            '${item.severity == SkillIssueSeverity.error ? '错误' : '警告'}'
            '${item.stepId == null ? '' : '[${item.stepId}]'}'
            ': ${item.message} (${item.code})')
        .join('\n');
  }
}

/// Validates a skill before it is saved or run.
///
/// Validation is intentionally local and deterministic: the AI is never the
/// authority on whether a generated skill is safe.
class SkillValidator {
  final Map<String, ToolDescriptor> catalog;
  final Set<String>? allowedToolIds;

  SkillValidator({
    Map<String, ToolDescriptor>? catalog,
    this.allowedToolIds,
  }) : catalog = catalog ?? ToolCatalog.byId;

  SkillValidationResult validate(Skill skill) {
    return _validate(
      skill,
      allowWrites: true,
      currentHost: null,
      restrictToCurrentHost: false,
      allowedToolIds: null,
    );
  }

  SkillValidationResult validateDraft(
    SkillDraft draft, {
    bool allowWrites = false,
    String? currentHost,
    bool restrictToCurrentHost = false,
    Set<String>? allowedToolIds,
  }) {
    final skill = draft.toSkill(id: 'draft');
    return _validate(
      skill,
      allowWrites: allowWrites,
      currentHost: currentHost,
      restrictToCurrentHost: restrictToCurrentHost,
      allowedToolIds:
          allowedToolIds ?? this.allowedToolIds ?? ToolCatalog.availableIds,
    );
  }

  SkillValidationResult _validate(
    Skill skill, {
    required bool allowWrites,
    required String? currentHost,
    required bool restrictToCurrentHost,
    required Set<String>? allowedToolIds,
  }) {
    final issues = <SkillValidationIssue>[];
    void error(
      String code,
      String message, {
      String? stepId,
      String? field,
    }) {
      issues.add(SkillValidationIssue(
        code: code,
        message: message,
        severity: SkillIssueSeverity.error,
        stepId: stepId,
        field: field,
      ));
    }

    void warning(
      String code,
      String message, {
      String? stepId,
      String? field,
    }) {
      issues.add(SkillValidationIssue(
        code: code,
        message: message,
        severity: SkillIssueSeverity.warning,
        stepId: stepId,
        field: field,
      ));
    }

    final name = skill.name.trim();
    if (name.isEmpty) {
      error(SkillIssueCode.nameEmpty, '技能名称不能为空。', field: 'name');
    } else if (name.length > 80) {
      error(SkillIssueCode.nameTooLong, '技能名称不能超过 80 个字符。', field: 'name');
    }
    if (skill.description.length > 500) {
      error(SkillIssueCode.descriptionTooLong, '技能描述不能超过 500 个字符。',
          field: 'description');
    }

    // Input *declarations* are validated as written: a secret with a default
    // must be rejected even if no placeholder happens to reference it.
    final inputKeys = <String>{};
    final declaredKeys = <String>{};
    for (final input in skill.inputs) {
      final key = input.key.trim();
      if (key.isEmpty) {
        error(SkillIssueCode.inputKeyEmpty, '输入参数缺少 key。', field: 'inputs');
        continue;
      }
      if (!RegExp(r'^[A-Za-z0-9_\u4e00-\u9fa5-]+$').hasMatch(key)) {
        error(
          SkillIssueCode.inputKeyInvalid,
          '输入参数 key「$key」只能包含字母、数字、下划线、短横线或中文。',
          field: 'inputs.$key',
        );
      }
      if (!declaredKeys.add(key)) {
        error(
          SkillIssueCode.inputKeyDuplicate,
          '输入参数 key「$key」重复。',
          field: 'inputs.$key',
        );
      }
      if (input.type == SkillInputType.secret &&
          input.defaultValue.trim().isNotEmpty) {
        error(
          SkillIssueCode.secretDefault,
          '密钥输入「$key」不能设置默认值，否则会写入技能 JSON。',
          field: 'inputs.$key',
        );
      }
      if (input.type == SkillInputType.select) {
        if (input.options.isEmpty) {
          error(
            SkillIssueCode.inputSelectEmpty,
            '单选参数「$key」至少需要一个选项。',
            field: 'inputs.$key',
          );
        } else if (input.defaultValue.isNotEmpty &&
            !input.options.contains(input.defaultValue)) {
          error(
            SkillIssueCode.inputDefaultNotInOptions,
            '参数「$key」的默认值不在选项中。',
            field: 'inputs.$key',
          );
        }
      }
    }
    // Placeholders, not declarations, decide which keys a reference may use.
    for (final input in SkillInputs.effective(skill)) {
      final key = input.key.trim();
      if (key.isNotEmpty) inputKeys.add(key);
    }

    if (skill.kind == SkillKind.instruction) {
      if (skill.instructions.trim().isEmpty) {
        error(
          SkillIssueCode.instructionEmpty,
          '指令型技能必须填写 instructions。',
          field: 'instructions',
        );
      }
      if (skill.steps.isNotEmpty) {
        error(
          SkillIssueCode.instructionHasSteps,
          '指令型技能不能包含 steps。',
          field: 'steps',
        );
      }
    } else {
      if (skill.steps.isEmpty) {
        error(
          SkillIssueCode.flowEmpty,
          '流程型技能至少需要一个步骤。',
          field: 'steps',
        );
      }
      if (skill.steps.length > 50) {
        error(
          SkillIssueCode.flowTooManySteps,
          '流程型技能最多 50 个步骤。',
          field: 'steps',
        );
      } else if (skill.steps.length > 20) {
        warning(
          SkillIssueCode.flowTooManySteps,
          '流程有 ${skill.steps.length} 个步骤，建议拆成多个技能。',
          field: 'steps',
        );
      }
    }

    // First pass: collect ids and aliases before validating references.
    final aliasIndex = <String, int>{};
    final stepIndex = <String, int>{};
    for (var i = 0; i < skill.steps.length; i++) {
      final step = skill.steps[i];
      final id = step.id.trim();
      if (id.isEmpty) {
        error(
          SkillIssueCode.stepIdEmpty,
          '第 ${i + 1} 个步骤缺少 id。',
          stepId: step.id,
        );
        continue;
      }
      if (stepIndex.containsKey(id)) {
        error(
          SkillIssueCode.stepIdDuplicate,
          '步骤 id「$id」重复。',
          stepId: id,
        );
      } else {
        stepIndex[id] = i;
        aliasIndex[id] = i;
      }
      final alias = step.saveAs?.trim();
      if (alias != null && alias.isNotEmpty) {
        if (aliasIndex.containsKey(alias) && aliasIndex[alias] != i) {
          error(
            SkillIssueCode.stepAliasDuplicate,
            '步骤别名「$alias」与其他步骤冲突。',
            stepId: id,
          );
        } else {
          aliasIndex[alias] = i;
        }
      }
    }

    var writeSteps = 0;

    for (var i = 0; i < skill.steps.length; i++) {
      final step = skill.steps[i];
      final stepId = step.id.trim();
      if (step.name.trim().isEmpty) {
        error(
          SkillIssueCode.stepNameEmpty,
          '步骤「${stepId.isEmpty ? i + 1 : stepId}」缺少名称。',
          stepId: stepId,
        );
      }
      if (step.tool.trim().isEmpty) {
        error(
          SkillIssueCode.toolMissing,
          '步骤「$stepId」没有指定工具。',
          stepId: stepId,
        );
        continue;
      }

      final tool = catalog[step.tool];
      if (tool == null) {
        error(
          SkillIssueCode.toolUnknown,
          '步骤「$stepId」使用了未知工具「${step.tool}」。',
          stepId: stepId,
        );
        continue;
      }
      if (allowedToolIds != null && !allowedToolIds.contains(tool.id)) {
        error(
          SkillIssueCode.toolNotAvailable,
          '工具「${tool.id}」当前不可用。',
          stepId: stepId,
        );
      }
      if (tool.isWrite) writeSteps++;

      if (!allowWrites && tool.isWrite) {
        error(
          SkillIssueCode.writesNotAllowed,
          '技能包含写入步骤「${step.name}」，需要显式开启“允许写入操作”。',
          stepId: stepId,
        );
      }

      final knownParams = {for (final param in tool.params) param.key};
      for (final param in tool.params) {
        final value = step.params[param.key];
        if (param.required &&
            (value == null || (value is String && value.trim().isEmpty))) {
          error(
            SkillIssueCode.paramMissing,
            '步骤「$stepId」缺少必填参数「${param.label}」(${param.key})。',
            stepId: stepId,
            field: param.key,
          );
          continue;
        }
        if (value != null) {
          _validateParamType(
            param,
            value,
            error: error,
            stepId: stepId,
          );
        }
      }
      for (final key in step.params.keys) {
        if (!knownParams.contains(key)) {
          warning(
            SkillIssueCode.paramUnknown,
            '步骤「$stepId」包含工具未声明的参数「$key」，执行时会被忽略。',
            stepId: stepId,
            field: key,
          );
        }
      }

      _validateToolSpecific(
        step: step,
        tool: tool,
        allowWrites: allowWrites,
        currentHost: currentHost,
        restrictToCurrentHost: restrictToCurrentHost,
        error: error,
        warning: warning,
      );
      _validateExpectation(
        step,
        error: error,
      );
      if (step.onError.action == StepFailureAction.fallbackAgent) {
        if (step.onError.fallbackGoal.trim().isEmpty) {
          error(
            SkillIssueCode.fallbackGoalEmpty,
            '步骤「$stepId」的 Agent 兜底缺少子目标。',
            stepId: stepId,
            field: 'onError.fallbackGoal',
          );
        }
        if (step.onError.fallbackMaxSteps <= 0) {
          error(
            SkillIssueCode.fallbackSteps,
            '步骤「$stepId」的 Agent 兜底步数必须大于 0。',
            stepId: stepId,
            field: 'onError.fallbackMaxSteps',
          );
        }
        for (final fallbackTool in step.onError.fallbackTools) {
          final descriptor = catalog[fallbackTool];
          if (descriptor == null) {
            error(
              SkillIssueCode.fallbackTool,
              '步骤「$stepId」的兜底工具「$fallbackTool」不存在。',
              stepId: stepId,
              field: 'onError.fallbackTools',
            );
          } else if (descriptor.isWrite && !allowWrites) {
            error(
              SkillIssueCode.writesNotAllowed,
              '步骤「$stepId」的兜底工具包含写入工具「$fallbackTool」。',
              stepId: stepId,
              field: 'onError.fallbackTools',
            );
          }
        }
      }

      final references = <String>{
        ...SkillTemplate.referencesIn(step.params),
        ...SkillTemplate.referencesIn(step.expect?.value ?? ''),
      };
      for (final reference in references) {
        _validateReference(
          reference,
          currentStepIndex: i,
          inputKeys: inputKeys,
          aliasIndex: aliasIndex,
          stepIndex: stepIndex,
          steps: skill.steps,
          error: error,
          warning: warning,
          stepId: stepId,
          field: 'params',
        );
      }
    }

    for (final entry in skill.output.entries) {
      final key = entry.key.trim();
      if (!RegExp(r'^[A-Za-z0-9_\u4e00-\u9fa5-]+$').hasMatch(key)) {
        error(
          SkillIssueCode.outputKeyInvalid,
          '输出字段「${entry.key}」名称不合法。',
          field: 'output',
        );
      }
      for (final reference in SkillTemplate.references(entry.value)) {
        _validateReference(
          reference,
          currentStepIndex: skill.steps.length,
          inputKeys: inputKeys,
          aliasIndex: aliasIndex,
          stepIndex: stepIndex,
          steps: skill.steps,
          error: error,
          warning: warning,
          field: 'output.${entry.key}',
        );
      }
    }

    _validatePolicy(
      skill,
      writeSteps: writeSteps,
      restrictToCurrentHost: restrictToCurrentHost,
      error: error,
      warning: warning,
    );

    // Deduplicate identical issues (a bad reference can be visited twice).
    final seen = <String>{};
    final unique = <SkillValidationIssue>[];
    for (final issue in issues) {
      final key =
          '${issue.code}|${issue.stepId}|${issue.field}|${issue.message}';
      if (seen.add(key)) unique.add(issue);
    }
    return SkillValidationResult(unique);
  }

  void _validateParamType(
    ToolParam param,
    dynamic value, {
    required void Function(String, String, {String? stepId, String? field})
        error,
    required String stepId,
  }) {
    if (value is String && value.contains('{{')) return;

    bool bad() {
      error(
        SkillIssueCode.paramType,
        '步骤「$stepId」的参数「${param.key}」类型不正确，期望 ${param.type.name}。',
        stepId: stepId,
        field: param.key,
      );
      return true;
    }

    switch (param.type) {
      case ToolParamType.text:
      case ToolParamType.multiline:
      case ToolParamType.secret:
        if (value is! String) bad();
        break;
      case ToolParamType.number:
        if (value is num) break;
        if (value is String && num.tryParse(value.trim()) != null) break;
        bad();
        break;
      case ToolParamType.boolean:
        if (value is! bool) bad();
        break;
      case ToolParamType.select:
        if (value is! String) {
          bad();
          break;
        }
        if (param.options.isNotEmpty && !param.options.contains(value)) {
          error(
            SkillIssueCode.paramType,
            '步骤「$stepId」的参数「${param.key}」必须是 ${param.options.join(' / ')} 之一。',
            stepId: stepId,
            field: param.key,
          );
        }
        break;
      case ToolParamType.locator:
        if (value is! Map) {
          error(
            SkillIssueCode.locatorInvalid,
            '步骤「$stepId」的参数「${param.key}」必须是定位器对象。',
            stepId: stepId,
            field: param.key,
          );
        }
        break;
      case ToolParamType.json:
        if (value is Map || value is List) break;
        if (value is String) {
          try {
            final decoded = jsonDecode(value);
            if (decoded is Map || decoded is List) break;
          } catch (_) {}
        }
        error(
          SkillIssueCode.paramType,
          '步骤「$stepId」的参数「${param.key}」必须是对象或数组。',
          stepId: stepId,
          field: param.key,
        );
        break;
    }
  }

  void _validateToolSpecific({
    required SkillStep step,
    required ToolDescriptor tool,
    required bool allowWrites,
    required String? currentHost,
    required bool restrictToCurrentHost,
    required void Function(String, String, {String? stepId, String? field})
        error,
    required void Function(String, String, {String? stepId, String? field})
        warning,
  }) {
    final stepId = step.id.trim();

    if (tool.id == 'page.open') {
      final rawUrl = step.params['url'];
      if (rawUrl is String && rawUrl.trim().isNotEmpty) {
        final url = rawUrl.trim();
        if (url.contains('{{steps.')) {
          error(
            SkillIssueCode.urlPageData,
            '步骤「$stepId」的网址不能直接包含页面数据，避免把内容外发。',
            stepId: stepId,
            field: 'url',
          );
        } else if (!url.contains('{{')) {
          final uri = Uri.tryParse(url);
          if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
            error(
              SkillIssueCode.urlInvalid,
              '步骤「$stepId」的网址必须是 http 或 https。',
              stepId: stepId,
              field: 'url',
            );
          } else if (restrictToCurrentHost) {
            final targetHost = normalizeHost(uri.host);
            final allowed = currentHost != null &&
                currentHost.isNotEmpty &&
                targetHost == normalizeHost(currentHost);
            if (!allowed) {
              error(
                SkillIssueCode.urlOutsideScope,
                '步骤「$stepId」硬编码了外部网址（${uri.host}），请改成用户输入。',
                stepId: stepId,
                field: 'url',
              );
            }
          }
        }
      }
    }

    if (tool.id == 'page.type') {
      final submit = step.params['submit'] == true;
      final text = step.params['text'];
      final secret = step.params['secret'] == true;
      if (submit && text is String && text.contains('{{steps.')) {
        error(
          SkillIssueCode.pageDataSubmit,
          '步骤「$stepId」会把页面内容填进输入框并提交，这是高风险操作。',
          stepId: stepId,
          field: 'text',
        );
      }
      if (secret &&
          text is String &&
          text.contains('{{') &&
          !text.contains('{{inputs.')) {
        warning(
          SkillIssueCode.secretLiteral,
          '步骤「$stepId」标记为密钥输入，但没有绑定密钥类型的输入参数。',
          stepId: stepId,
          field: 'text',
        );
      }
    }

    if (tool.id == 'ai.generate') {
      final prompt = step.params['prompt'];
      final data = step.params['data'];
      if (prompt is String &&
          prompt.contains('{{steps.') &&
          (data == null || (data is Map && data.isEmpty))) {
        warning(
          SkillIssueCode.promptPageData,
          '步骤「$stepId」把页面数据直接拼进提示词，建议改放到 data 字段。',
          stepId: stepId,
          field: 'prompt',
        );
      }
    }

    // Locator shape checks for every locator-typed param.
    for (final param in tool.params) {
      if (param.type != ToolParamType.locator) continue;
      final value = step.params[param.key];
      if (value is Map) {
        _validateLocator(
          value,
          stepId: stepId,
          field: param.key,
          expectMultiple: param.key == 'itemLocator',
          error: error,
          warning: warning,
        );
      }
    }

    if (tool.id == 'agent.task') {
      final tools = step.params['tools'];
      if (tools is List) {
        for (final id in tools) {
          final descriptor = catalog[id.toString()];
          if (descriptor == null) {
            error(
              SkillIssueCode.toolUnknown,
              '步骤「$stepId」的 Agent 工具白名单包含未知工具「$id」。',
              stepId: stepId,
              field: 'tools',
            );
          } else if (descriptor.isWrite && !allowWrites) {
            error(
              SkillIssueCode.writesNotAllowed,
              '步骤「$stepId」的 Agent 工具白名单包含写入工具「$id」。',
              stepId: stepId,
              field: 'tools',
            );
          }
        }
      }
    }
  }

  void _validateLocator(
    Map locator, {
    required String stepId,
    required String field,
    required bool expectMultiple,
    required void Function(String, String, {String? stepId, String? field})
        error,
    required void Function(String, String, {String? stepId, String? field})
        warning,
  }) {
    final rawCandidates = locator['candidates'];
    if (rawCandidates is! List || rawCandidates.isEmpty) {
      error(
        SkillIssueCode.locatorInvalid,
        '步骤「$stepId」的定位器至少需要一个 candidates 候选。',
        stepId: stepId,
        field: field,
      );
      return;
    }

    const allowedTypes = {
      'css',
      'xpath',
      'role',
      'text',
      'operonId',
      'semantic',
    };
    var semanticOnly = true;
    for (final raw in rawCandidates) {
      if (raw is! Map) {
        error(
          SkillIssueCode.locatorInvalid,
          '步骤「$stepId」的定位器候选必须是对象。',
          stepId: stepId,
          field: field,
        );
        continue;
      }
      final type = raw['type']?.toString() ?? '';
      if (!allowedTypes.contains(type)) {
        error(
          SkillIssueCode.locatorInvalid,
          '步骤「$stepId」的定位器类型「$type」不支持。',
          stepId: stepId,
          field: field,
        );
        continue;
      }
      if (type != 'semantic') semanticOnly = false;
      if (type == 'role') {
        if ((raw['role']?.toString() ?? '').isEmpty &&
            (raw['name']?.toString() ?? '').isEmpty) {
          error(
            SkillIssueCode.locatorInvalid,
            '步骤「$stepId」的 role 定位器需要 role 或 name。',
            stepId: stepId,
            field: field,
          );
        }
      } else if ((raw['value']?.toString() ?? '').isEmpty) {
        error(
          SkillIssueCode.locatorInvalid,
          '步骤「$stepId」的 $type 定位器缺少 value。',
          stepId: stepId,
          field: field,
        );
      }
    }

    if (semanticOnly) {
      warning(
        SkillIssueCode.locatorSemanticOnly,
        '步骤「$stepId」只使用语义定位器，运行时可能需要 Agent 兜底。',
        stepId: stepId,
        field: field,
      );
    }
    if (!expectMultiple && locator['requireUnique'] != true) {
      warning(
        SkillIssueCode.locatorNotUnique,
        '步骤「$stepId」的定位器没有设置 requireUnique，多个匹配时可能误操作。',
        stepId: stepId,
        field: field,
      );
    }
  }

  void _validateExpectation(
    SkillStep step, {
    required void Function(String, String, {String? stepId, String? field})
        error,
  }) {
    final expect = step.expect;
    if (expect == null) return;
    final value = expect.value?.trim() ?? '';
    switch (expect.type) {
      case ExpectationType.elementExists:
      case ExpectationType.urlContains:
      case ExpectationType.textContains:
        if (value.isEmpty) {
          error(
            SkillIssueCode.expectMissingValue,
            '步骤「${step.id}」的后置条件缺少 value。',
            stepId: step.id,
            field: 'expect.value',
          );
        }
        break;
      case ExpectationType.dataNotEmpty:
      case ExpectationType.pageChanged:
        break;
    }
  }

  void _validateReference(
    String raw, {
    required int currentStepIndex,
    required Set<String> inputKeys,
    required Map<String, int> aliasIndex,
    required Map<String, int> stepIndex,
    required List<SkillStep> steps,
    required void Function(String, String, {String? stepId, String? field})
        error,
    required void Function(String, String, {String? stepId, String? field})
        warning,
    String? stepId,
    String? field,
  }) {
    final reference = raw.trim();
    if (reference.isEmpty) return;

    if (reference.startsWith('inputs.')) {
      final key = reference.substring('inputs.'.length).split('.').first;
      if (!inputKeys.contains(key)) {
        error(
          SkillIssueCode.variableUnknown,
          '变量「$reference」引用了不存在的输入参数「$key」。',
          stepId: stepId,
          field: field,
        );
      }
      return;
    }

    if (reference.startsWith('steps.')) {
      final parts = reference.split('.');
      if (parts.length < 2 || parts[1].isEmpty) {
        error(
          SkillIssueCode.variableStepUnknown,
          '变量「$reference」缺少步骤名。',
          stepId: stepId,
          field: field,
        );
        return;
      }
      final alias = parts[1];
      final index = aliasIndex[alias];
      if (index == null) {
        error(
          SkillIssueCode.variableStepUnknown,
          '变量「$reference」引用了不存在的步骤「$alias」。',
          stepId: stepId,
          field: field,
        );
        return;
      }
      if (index >= currentStepIndex) {
        error(
          SkillIssueCode.variableForwardReference,
          '变量「$reference」只能引用之前的步骤。',
          stepId: stepId,
          field: field,
        );
        return;
      }
      if (!steps[index].enabled) {
        warning(
          SkillIssueCode.variableForwardReference,
          '变量「$reference」引用了已禁用的步骤「$alias」。',
          stepId: stepId,
          field: field,
        );
      }
      return;
    }

    if (reference == 'env.url' ||
        reference == 'env.title' ||
        reference == 'env.now' ||
        reference == 'run.id') {
      return;
    }

    if (reference == 'item' ||
        reference == 'index' ||
        reference.startsWith('item.')) {
      error(
        SkillIssueCode.variableControlFlow,
        '变量「$reference」需要循环支持，当前版本不可用。',
        stepId: stepId,
        field: field,
      );
      return;
    }

    // Backward compatibility for old quick-command templates: `{{count}}`.
    if (!reference.contains('.') && inputKeys.contains(reference)) {
      return;
    }

    error(
      SkillIssueCode.variableUnknown,
      '未知变量「$reference」。',
      stepId: stepId,
      field: field,
    );
  }

  void _validatePolicy(
    Skill skill, {
    required int writeSteps,
    required bool restrictToCurrentHost,
    required void Function(String, String, {String? stepId, String? field})
        error,
    required void Function(String, String, {String? stepId, String? field})
        warning,
  }) {
    final policy = skill.policy;
    final enabledSteps = skill.steps.where((step) => step.enabled).length;

    if (policy.maxSteps <= 0) {
      error(SkillIssueCode.policySteps, 'maxSteps 必须大于 0。', field: 'policy');
    } else if (skill.isFlow && policy.maxSteps < enabledSteps) {
      error(
        SkillIssueCode.policySteps,
        'maxSteps (${policy.maxSteps}) 小于步骤数 ($enabledSteps)。',
        field: 'policy',
      );
    }
    if (policy.maxSideEffects < 0) {
      error(SkillIssueCode.policySideEffects, 'maxSideEffects 不能为负数。',
          field: 'policy');
    } else if (skill.isFlow &&
        writeSteps > 0 &&
        policy.maxSideEffects < writeSteps) {
      error(
        SkillIssueCode.policySideEffects,
        'maxSideEffects (${policy.maxSideEffects}) 小于写入步骤数 ($writeSteps)。',
        field: 'policy',
      );
    }
    if (policy.maxItems < 1) {
      error(SkillIssueCode.policyItems, 'maxItems 必须大于等于 1。', field: 'policy');
    } else if (policy.maxItems > 1000) {
      warning(SkillIssueCode.policyItems, 'maxItems 超过 1000，可能造成长时间运行。',
          field: 'policy');
    }
    if (policy.maxDurationMs <= 0) {
      error(SkillIssueCode.policyDuration, 'maxDurationMs 必须大于 0。',
          field: 'policy');
    }
    if (policy.pacingMs < 0) {
      error(SkillIssueCode.policyPacing, 'pacingMs 不能为负数。', field: 'policy');
    } else if (policy.pacingMs > 60000) {
      warning(SkillIssueCode.policyPacing, '步骤间隔超过 60 秒，体验会很慢。',
          field: 'policy');
    }

    if (policy.hostScope == SkillHostScope.list) {
      if (policy.allowedHosts.isEmpty) {
        error(SkillIssueCode.policyHostScope,
            'hostScope 为 list 时，allowedHosts 不能为空。',
            field: 'policy');
      }
      for (final host in policy.allowedHosts) {
        final value = host.trim().toLowerCase();
        if (value.isEmpty ||
            !RegExp(r'^[a-z0-9.*-]+(:\d+)?$').hasMatch(value)) {
          error(
            SkillIssueCode.policyHostInvalid,
            '站点「$host」格式不正确，只填写域名，不要带协议或路径。',
            field: 'policy',
          );
        }
      }
    }

    if (writeSteps > 0 && policy.hostScope == SkillHostScope.any) {
      warning(
        SkillIssueCode.writesAnyHost,
        '技能包含写入步骤，但允许在任意站点运行；建议限制到当前站点。',
        field: 'policy',
      );
    }
    if (restrictToCurrentHost &&
        writeSteps > 0 &&
        policy.hostScope == SkillHostScope.any) {
      error(
        SkillIssueCode.writeScopeNotRestricted,
        'AI 创建的写入技能必须限制站点范围。',
        field: 'policy',
      );
    }
    if (writeSteps > 0 && !policy.confirmWrites) {
      warning(
        SkillIssueCode.confirmWritesOff,
        '写入步骤已关闭每次确认，请确认你信任这个技能。',
        field: 'policy',
      );
    }
    if (writeSteps > 0 && !policy.confirmDestructive) {
      warning(
        SkillIssueCode.confirmDestructiveOff,
        '高危操作已关闭确认，发送/支付/删除类操作不会再询问。',
        field: 'policy',
      );
    }
  }
}
