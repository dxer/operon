import 'dart:convert';

import '../models/llm_config.dart';
import '../models/skill.dart';
import '../models/skill_run.dart';
import '../utils/cancellation.dart';
import '../utils/json_parser.dart';
import 'llm_service.dart';
import 'webview_controller_wrapper.dart';

/// Outcome of a locator repair attempt.
class SkillRepairResult {
  /// The skill with the failed step's locator replaced.
  final Skill skill;

  /// Why the model picked this candidate.
  final String reason;

  /// Whether the new locator resolved on the current page.
  final bool verified;

  const SkillRepairResult({
    required this.skill,
    this.reason = '',
    this.verified = false,
  });
}

/// Proposes a replacement locator when a flow step cannot find its target.
///
/// This is deliberately narrow: it only rewrites the `locator` parameter of
/// one failed step, and the user always reviews the result in the editor
/// before saving. It never runs the repaired skill automatically.
class SkillRepairService {
  final LlmService llmService;

  SkillRepairService({LlmService? llmService})
      : llmService = llmService ?? LlmService();

  /// Closes the HTTP client owned by this service. Do not call this when the
  /// [LlmService] was injected and is shared elsewhere.
  void dispose() => llmService.dispose();

  static const Set<String> _locatorTools = {
    'page.click',
    'page.type',
    'page.press_key',
    'page.select',
    'page.hover',
    'page.read_region',
    'page.scroll',
    'page.wait',
  };

  static bool canRepair(SkillStep step) {
    return _locatorTools.contains(step.tool) && step.params['locator'] is Map;
  }

  Future<SkillRepairResult?> repairLocator({
    required Skill skill,
    required SkillStepResult failedStep,
    required WebViewControllerWrapper webView,
    required LlmConfig config,
    CancellationToken? token,
  }) async {
    if (!config.isValid) {
      throw Exception('请先在设置中配置大模型 API Key');
    }
    final index = skill.steps.indexWhere((step) => step.id == failedStep.stepId);
    if (index < 0) return null;
    final step = skill.steps[index];
    if (!canRepair(step)) return null;

    final elements = await webView.getInteractiveSummary(maxItems: 80);
    final labels = elements
        .map((item) {
          final role = item['role']?.toString().isNotEmpty == true
              ? item['role']
              : item['type'];
          final label = item['label']?.toString() ?? '';
          return '- [$role] $label';
        })
        .where((line) => line.trim().isNotEmpty)
        .join('\n');

    final error = failedStep.errorMessage?.trim().isNotEmpty == true
        ? failedStep.errorMessage
        : (failedStep.errorCode ?? '未知错误');
    final oldLocator = const JsonEncoder.withIndent('  ')
        .convert(step.params['locator']);

    final prompt = '''
技能步骤「${step.name}」使用工具 ${step.tool} 执行失败：$error

原定位器：
$oldLocator

当前页面可交互元素（仅标签，不含输入值）：
${labels.isEmpty ? '（没有读取到可交互元素）' : labels}

请给出一个新的定位器候选链。要求：
1. 优先使用 text 或 role 候选，CSS 只作为补充；不要使用容易变化的 class 名。
2. candidates 按优先级排列，可以给 2-3 个候选。
3. 目标必须唯一；无法唯一时 requireUnique 设为 false 并给出更具体的候选。
4. 只输出一个 JSON 对象，不要 Markdown：
{"locator":{"candidates":[{"type":"text","value":"回复"}],"requireUnique":true},"reason":"一句话原因"}
''';

    final raw = await llmService.chatCompletion(
      config: config,
      messages: [
        {
          'role': 'system',
          'content': '你是网页自动化技能的定位器修复器。只输出 JSON，不要执行任何操作。',
        },
        {'role': 'user', 'content': prompt},
      ],
      temperature: 0.1,
      jsonMode: true,
      cancelToken: token,
    );

    final locator = parseLocator(raw);
    if (locator == null) return null;

    var verified = false;
    try {
      final resolved = await webView.resolveLocator(locator);
      verified = resolved['found'] == true;
    } catch (_) {
      // A failed verification is not fatal: the user may still edit the
      // candidate chain manually.
    }

    final steps = List<SkillStep>.from(skill.steps);
    steps[index] = step.copyWith(
      params: {...step.params, 'locator': locator},
    );

    String reason = '';
    final decoded = JsonParser.extractJson(raw);
    if (decoded != null) reason = decoded['reason']?.toString() ?? '';

    return SkillRepairResult(
      skill: skill.copyWith(steps: steps, updatedAt: DateTime.now()),
      reason: reason,
      verified: verified,
    );
  }

  /// Extracts and validates a locator candidate chain from model output.
  static Map<String, dynamic>? parseLocator(String raw) {
    final decoded = JsonParser.extractJson(raw);
    if (decoded == null) return null;
    final rawLocator = decoded['locator'];
    if (rawLocator is! Map) return null;
    final locator = Map<String, dynamic>.from(rawLocator);

    final rawCandidates = locator['candidates'];
    if (rawCandidates is! List) return null;
    final candidates = rawCandidates
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(_isValidCandidate)
        .toList();
    if (candidates.isEmpty) return null;

    locator['candidates'] = candidates;
    locator['requireUnique'] ??= true;
    return locator;
  }

  /// Only the types the page-side resolver can actually match are accepted.
  /// `semantic` is intentionally excluded: it needs an agent fallback and
  /// would never verify on the current page.
  static bool _isValidCandidate(Map<String, dynamic> candidate) {
    final type = candidate['type']?.toString().toLowerCase() ?? '';
    switch (type) {
      case 'css':
      case 'xpath':
      case 'operonid':
      case 'text':
        return candidate['value']?.toString().trim().isNotEmpty ?? false;
      case 'role':
        return candidate['role']?.toString().trim().isNotEmpty ?? false;
      default:
        return false;
    }
  }
}
