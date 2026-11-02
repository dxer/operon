import 'dart:convert';

import '../config/skill_authoring_prompt.dart';
import '../config/tool_catalog.dart';
import '../models/llm_config.dart';
import '../models/skill.dart';
import '../services/skill_validator.dart';
import '../utils/cancellation.dart';
import '../utils/json_parser.dart';
import 'llm_service.dart';
import 'webview_controller_wrapper.dart';

class SkillAuthoringResult {
  final SkillDraft? draft;
  final SkillValidationResult validation;
  final String? error;
  final String raw;
  final int attempts;

  const SkillAuthoringResult({
    this.draft,
    this.validation = const SkillValidationResult([]),
    this.error,
    this.raw = '',
    this.attempts = 0,
  });

  bool get ok => draft != null && error == null && !validation.hasErrors;
}

/// Turns a natural-language description into a validated skill draft.
///
/// The model is never allowed to save or run anything. It gets one repair
/// attempt after a validation failure, then the UI shows the remaining issues.
class SkillAuthoringService {
  final LlmService llmService;
  final SkillValidator validator;

  SkillAuthoringService({
    LlmService? llmService,
    SkillValidator? validator,
  })  : llmService = llmService ?? LlmService(),
        validator = validator ?? SkillValidator();

  Future<SkillAuthoringResult> generate({
    required String description,
    required LlmConfig config,
    WebViewControllerWrapper? webView,
    bool referencePage = true,
    bool allowWrites = false,
    bool restrictToCurrentHost = false,
    Skill? baseSkill,
    List<String> existingNames = const [],
    CancellationToken? token,
    void Function(String stage)? onProgress,
  }) async {
    final text = description.trim();
    if (text.isEmpty) {
      return const SkillAuthoringResult(error: '请先描述你想让技能做什么');
    }
    if (!config.isValid) {
      return const SkillAuthoringResult(
        error: '请先在设置中配置有效的大模型 API Key',
      );
    }
    if (token?.isCancelled == true) {
      return const SkillAuthoringResult(error: '生成已取消');
    }

    onProgress?.call('正在读取页面摘要…');
    final page = await _pageContext(
      webView,
      referencePage: referencePage,
      token: token,
    );
    final currentHost = page.host;

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': SkillAuthoringPrompt.system(
          allowWrites: allowWrites,
          restrictToCurrentHost: restrictToCurrentHost,
          currentHost: currentHost,
          maxSteps: 12,
        ),
      },
      {
        'role': 'user',
        'content': SkillAuthoringPrompt.user(
          description: text,
          pageContext: page.text,
          allowWrites: allowWrites,
          referencePage: referencePage,
          baseSkill: baseSkill == null
              ? null
              : jsonEncode(_maskedSkillJson(baseSkill)),
        ),
      },
    ];

    onProgress?.call('正在生成技能…');
    String raw;
    try {
      raw = await llmService.chatCompletion(
        config: config,
        messages: messages,
        temperature: 0.2,
        jsonMode: true,
        cancelToken: token,
      );
    } catch (e) {
      return SkillAuthoringResult(error: e.toString(), raw: '');
    }

    var draft = _parseDraft(raw);
    var attempts = 0;
    if (draft == null) {
      // One repair attempt for malformed JSON, using the raw response as the
      // only context. This is common with providers that ignore jsonMode.
      onProgress?.call('模型返回格式异常，正在修复…');
      try {
        raw = await llmService.chatCompletion(
          config: config,
          messages: [
            ...messages,
            {
              'role': 'assistant',
              'content': raw,
            },
            {
              'role': 'user',
              'content': SkillAuthoringPrompt.repair(
                previousDraft: raw,
                issues: '输出不是合法 JSON，或缺少 name/steps/instructions 字段。',
              ),
            },
          ],
          temperature: 0.2,
          jsonMode: true,
          cancelToken: token,
        );
        draft = _parseDraft(raw);
      } catch (e) {
        return SkillAuthoringResult(error: e.toString(), raw: raw);
      }
      attempts++;
    }

    if (draft == null) {
      return SkillAuthoringResult(
        error: '模型没有返回可解析的技能 JSON',
        raw: raw,
        attempts: attempts,
      );
    }

    var normalized = _normalizeDraft(
      draft,
      allowWrites: allowWrites,
      currentHost: currentHost,
      restrictToCurrentHost: restrictToCurrentHost,
    );
    var validation = _validate(
      normalized,
      allowWrites,
      currentHost,
      restrictToCurrentHost,
    );

    var repairRounds = 0;
    while (validation.hasErrors && repairRounds < 2) {
      if (token?.isCancelled == true) {
        return SkillAuthoringResult(
          draft: normalized,
          validation: validation,
          error: '生成已取消',
          raw: raw,
          attempts: attempts + repairRounds,
        );
      }
      repairRounds++;
      onProgress?.call('发现 ${validation.errors.length} 个问题，正在自动修复…');
      try {
        raw = await llmService.chatCompletion(
          config: config,
          messages: [
            ...messages,
            {
              'role': 'assistant',
              'content': jsonEncode(normalized.toJson()),
            },
            {
              'role': 'user',
              'content': SkillAuthoringPrompt.repair(
                previousDraft: jsonEncode(normalized.toJson()),
                issues: validation.repairHint,
              ),
            },
          ],
          temperature: 0.2,
          jsonMode: true,
          cancelToken: token,
        );
      } catch (e) {
        return SkillAuthoringResult(
          draft: normalized,
          validation: validation,
          error: e.toString(),
          raw: raw,
          attempts: attempts + repairRounds,
        );
      }
      final repaired = _parseDraft(raw);
      if (repaired == null) continue;
      normalized = _normalizeDraft(
        repaired,
        allowWrites: allowWrites,
        currentHost: currentHost,
        restrictToCurrentHost: restrictToCurrentHost,
      );
      validation = _validate(
        normalized,
        allowWrites,
        currentHost,
        restrictToCurrentHost,
      );
    }

    if (validation.hasErrors) {
      return SkillAuthoringResult(
        draft: normalized,
        validation: validation,
        error: '技能草案仍有校验错误，请手动调整',
        raw: raw,
        attempts: attempts + repairRounds,
      );
    }

    return SkillAuthoringResult(
      draft: normalized,
      validation: validation,
      raw: raw,
      attempts: attempts + repairRounds,
    );
  }

  SkillValidationResult _validate(
    SkillDraft draft,
    bool allowWrites,
    String? currentHost,
    bool restrictToCurrentHost,
  ) {
    return validator.validateDraft(
      draft,
      allowWrites: allowWrites,
      currentHost: currentHost,
      // AI-authored skills may not hardcode a navigation to another host.
      // A user-supplied URL input is still allowed.
      restrictToCurrentHost: true,
      allowedToolIds: ToolCatalog.authoringIds,
    );
  }

  SkillDraft _normalizeDraft(
    SkillDraft draft, {
    required bool allowWrites,
    required String? currentHost,
    required bool restrictToCurrentHost,
  }) {
    final writeCount = draft.steps.where((step) {
      final tool = ToolCatalog.find(step.tool);
      return tool?.isWrite == true;
    }).length;
    final llmCount = draft.steps.where((step) {
      final tool = ToolCatalog.find(step.tool);
      return tool?.usesLlm == true;
    }).length;

    var policy = draft.policy;
    if (draft.steps.isNotEmpty) {
      policy = policy.copyWith(
        maxSteps: policy.maxSteps < draft.steps.length
            ? draft.steps.length + 4
            : policy.maxSteps,
        maxLlmCalls:
            policy.maxLlmCalls < llmCount ? llmCount + 1 : policy.maxLlmCalls,
        maxSideEffects: policy.maxSideEffects < writeCount
            ? writeCount
            : policy.maxSideEffects,
      );
    }
    if (allowWrites && writeCount > 0) {
      policy = policy.copyWith(
        hostScope: SkillHostScope.currentHost,
        confirmWrites: true,
        confirmDestructive: true,
      );
    }
    if (!allowWrites && writeCount > 0) {
      // Leave the write steps in place so validation can explain exactly which
      // step needs permission; the UI offers a regenerate-with-writes action.
    }

    return draft.copyWith(policy: policy);
  }

  /// Never send secret input defaults or secret field payloads to the model.
  Map<String, dynamic> _maskedSkillJson(Skill skill) {
    final json = jsonDecode(jsonEncode(skill.toJson())) as Map<String, dynamic>;
    final inputs = json['inputs'];
    if (inputs is List) {
      for (final item in inputs) {
        if (item is Map && item['type'] == 'secret') {
          item['defaultValue'] = '';
        }
      }
    }
    final steps = json['steps'];
    if (steps is List) {
      for (final item in steps) {
        if (item is! Map) continue;
        final params = item['params'];
        if (params is Map && params['secret'] == true) {
          params['text'] = '••••••';
        }
      }
    }
    return json;
  }

  SkillDraft? _parseDraft(String raw) {
    final map = JsonParser.extractJson(raw);
    if (map == null) return null;
    try {
      final draft = SkillDraft.fromJson(map);
      if (draft.name.trim().isEmpty) return null;
      if (draft.kind == SkillKind.flow && draft.steps.isEmpty) return null;
      if (draft.kind == SkillKind.instruction &&
          draft.instructions.trim().isEmpty) {
        return null;
      }
      return draft;
    } catch (_) {
      return null;
    }
  }

  Future<_PageContext> _pageContext(
    WebViewControllerWrapper? webView, {
    required bool referencePage,
    CancellationToken? token,
  }) async {
    if (webView == null || !referencePage) {
      return const _PageContext(text: '未参考当前页面。', host: null);
    }
    try {
      final article = await webView.extractReadableContent();
      final title = article['title']?.toString() ?? await webView.getTitle();
      final url = article['url']?.toString() ?? await webView.getUrl();
      final content = article['content']?.toString() ?? '';
      final host = Uri.tryParse(url)?.host ?? '';
      final clipped = content.length > 4000
          ? '${content.substring(0, 4000)}\n…(已截取)'
          : content;
      final elements = await webView.getInteractiveSummary(maxItems: 60);
      final elementLines = elements.isEmpty
          ? ''
          : '\n\n可交互元素（仅标签，不含输入值）：\n${elements.map((item) {
              final type = item['role']?.toString().isNotEmpty == true
                  ? item['role']
                  : item['type'];
              return '- [$type] ${item['label']}';
            }).join('\n')}';
      return _PageContext(
        host: host.isEmpty ? null : host,
        text: '标题：$title\n网址：$url\n\n$clipped$elementLines',
      );
    } catch (_) {
      return const _PageContext(text: '无法读取当前页面摘要。', host: null);
    }
  }
}

class _PageContext {
  final String text;
  final String? host;

  const _PageContext({required this.text, this.host});
}
