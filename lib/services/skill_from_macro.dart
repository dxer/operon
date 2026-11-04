import '../models/macro_workflow.dart';
import '../models/skill.dart';
import '../models/tool_descriptor.dart';
import '../utils/url_utils.dart';

/// Converts a recorded macro into an editable flow-skill draft.
///
/// This is intentionally deterministic: no model is used. Recorded selectors
/// become locator candidates, and the user can edit them before saving.
class SkillFromMacro {
  SkillFromMacro._();

  static SkillDraft? fromMacro(MacroWorkflow macro) {
    if (macro.steps.isEmpty) return null;
    final steps = <SkillStep>[];
    var writes = 0;

    for (var i = 0; i < macro.steps.length; i++) {
      final recorded = macro.steps[i];
      final action = recorded.action.toLowerCase();
      final locator = _locator(recorded);
      SkillStep? step;
      switch (action) {
        case 'click':
          if (locator == null) continue;
          step = SkillStep(
            id: 'step_${i + 1}_click',
            name: recorded.description.isEmpty ? '点击' : recorded.description,
            tool: 'page.click',
            params: {'locator': locator, 'waitAfterMs': 800},
            onError: const StepFailurePolicy(action: StepFailureAction.stop),
          );
          writes++;
          break;
        case 'type':
          if (locator == null || (recorded.text ?? '').isEmpty) continue;
          step = SkillStep(
            id: 'step_${i + 1}_type',
            name: recorded.description.isEmpty ? '输入' : recorded.description,
            tool: 'page.type',
            params: {
              'locator': locator,
              'text': recorded.text ?? '',
              'clear': true,
              'submit': false,
            },
            onError: const StepFailurePolicy(action: StepFailureAction.stop),
          );
          writes++;
          break;
        case 'press_key':
        case 'presskey':
          step = SkillStep(
            id: 'step_${i + 1}_key',
            name: recorded.description.isEmpty ? '按键' : recorded.description,
            tool: 'page.press_key',
            params: {'key': recorded.key ?? 'Enter'},
            onError: const StepFailurePolicy(action: StepFailureAction.stop),
          );
          writes++;
          break;
        case 'select_option':
        case 'selectoption':
        case 'select':
          if (locator == null || (recorded.selectValue ?? '').isEmpty) continue;
          step = SkillStep(
            id: 'step_${i + 1}_select',
            name: recorded.description.isEmpty ? '下拉选择' : recorded.description,
            tool: 'page.select',
            params: {
              'locator': locator,
              'value': recorded.selectValue ?? '',
            },
            onError: const StepFailurePolicy(action: StepFailureAction.stop),
          );
          writes++;
          break;
        case 'hover':
          if (locator == null) continue;
          step = SkillStep(
            id: 'step_${i + 1}_hover',
            name: recorded.description.isEmpty ? '悬停' : recorded.description,
            tool: 'page.hover',
            params: {'locator': locator},
          );
          writes++;
          break;
        case 'wait':
          step = SkillStep(
            id: 'step_${i + 1}_wait',
            name: recorded.description.isEmpty ? '等待' : recorded.description,
            tool: 'page.wait',
            params: {'ms': 1000},
          );
          break;
        case 'scroll':
          step = SkillStep(
            id: 'step_${i + 1}_scroll',
            name: recorded.description.isEmpty ? '滚动' : recorded.description,
            tool: 'page.scroll',
            params: {'direction': recorded.direction ?? 'down'},
          );
          break;
        case 'navigate':
          if ((recorded.url ?? '').isEmpty) continue;
          step = SkillStep(
            id: 'step_${i + 1}_open',
            name: recorded.description.isEmpty ? '打开网页' : recorded.description,
            tool: 'page.open',
            params: {'url': recorded.url},
          );
          break;
        case 'go_back':
        case 'goback':
          step = SkillStep(
            id: 'step_${i + 1}_back',
            name: recorded.description.isEmpty ? '后退' : recorded.description,
            tool: 'page.back',
          );
          break;
        default:
          break;
      }
      if (step != null) steps.add(step);
    }

    if (steps.isEmpty) return null;
    final host = normalizeHost(hostOf(macro.initialUrl));
    return SkillDraft(
      name: macro.title.trim().isEmpty ? '录制技能' : macro.title.trim(),
      description: '由录制的宏任务转换，可继续编辑定位器与参数。',
      kind: SkillKind.flow,
      steps: steps,
      policy: SkillPolicy(
        maxSteps: steps.length + 4,
        maxSideEffects: writes,
        maxItems: 1,
        maxDurationMs: 180000,
        confirmWrites: true,
        confirmDestructive: true,
        hostScope: writes == 0
            ? SkillHostScope.any
            : (host.isEmpty
                ? SkillHostScope.currentHost
                : SkillHostScope.list),
        allowedHosts: host.isEmpty ? const [] : [host],
      ),
    );
  }

  static Map<String, dynamic>? _locator(MacroStep step) {
    final selector = step.selector?.trim() ?? '';
    if (selector.isNotEmpty) {
      if (selector.startsWith('xpath://')) {
        return {
          'candidates': [
            {'type': 'xpath', 'value': selector.substring(8)},
          ],
          'requireUnique': true,
        };
      }
      return {
        'candidates': [
          {'type': 'css', 'value': selector},
        ],
        'requireUnique': true,
      };
    }
    final text = step.targetText?.trim() ?? '';
    if (text.isNotEmpty) {
      return {
        'candidates': [
          {'type': 'text', 'value': text},
        ],
        'requireUnique': true,
      };
    }
    return null;
  }

  static bool isWrite(String tool) {
    switch (tool) {
      case 'page.click':
      case 'page.type':
      case 'page.press_key':
      case 'page.select':
      case 'page.hover':
      case 'macro.run':
      case 'agent.task':
        return true;
    }
    return false;
  }

  static ToolRisk riskOf(String tool) {
    if (isWrite(tool)) return ToolRisk.write;
    return ToolRisk.read;
  }
}
