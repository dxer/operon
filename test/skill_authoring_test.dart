import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/skill_authoring_mode.dart';
import 'package:operon/config/skill_authoring_prompt.dart';
import 'package:operon/models/llm_config.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/llm_service.dart';
import 'package:operon/services/skill_authoring_service.dart';
import 'package:operon/utils/cancellation.dart';

class _FakeLlmService extends LlmService {
  final List<String> responses;
  int calls = 0;

  _FakeLlmService(this.responses);

  @override
  Future<String> chatCompletion({
    required LlmConfig config,
    required List<Map<String, String>> messages,
    double? temperature,
    bool jsonMode = false,
    CancellationToken? cancelToken,
  }) async {
    final index = calls < responses.length ? calls : responses.length - 1;
    calls++;
    return responses[index];
  }
}

class _RecordingLlmService extends LlmService {
  final List<List<Map<String, String>>> calls = [];
  final String response;

  _RecordingLlmService(this.response);

  @override
  Future<String> chatCompletion({
    required LlmConfig config,
    required List<Map<String, String>> messages,
    double? temperature,
    bool jsonMode = false,
    CancellationToken? cancelToken,
  }) async {
    calls.add(messages);
    return response;
  }
}

const _config = LlmConfig(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'test-key',
  model: 'test-model',
);

const _validDraft = '''
{
  "name": "评论区总结",
  "description": "读取评论区并总结",
  "kind": "flow",
  "inputs": [
    {"key": "limit", "label": "最多条数", "type": "number", "defaultValue": "20", "required": true}
  ],
  "steps": [
    {
      "id": "read",
      "name": "读取评论",
      "tool": "page.read_region",
      "params": {
        "locator": {
          "candidates": [{"type": "css", "value": ".comment-list"}],
          "requireUnique": true
        },
        "mode": "text"
      },
      "saveAs": "comments",
      "onError": {"action": "stop"}
    }
  ],
  "policy": {
    "maxSteps": 8,
    "maxSideEffects": 0,
    "maxItems": 20
  }
}
''';

const _unknownToolDraft = '''
{
  "name": "坏技能",
  "kind": "flow",
  "steps": [
    {"id": "x", "name": "X", "tool": "page.nope", "params": {}}
  ]
}
''';

const _writeDraft = '''
{
  "name": "点击技能",
  "kind": "flow",
  "steps": [
    {
      "id": "click",
      "name": "点击",
      "tool": "page.click",
      "params": {
        "locator": {
          "candidates": [{"type": "text", "value": "发送"}],
          "requireUnique": true
        }
      }
    }
  ],
  "policy": {"maxSteps": 4, "maxSideEffects": 1}
}
''';

const _instructionDraft = '''
{
  "name": "回复推文",
  "description": "回复当前推文",
  "kind": "instruction",
  "instructions": "找到推文下方的回复按钮，点击后填写 {{inputs.content}}，用 {{inputs.tone}} 的语气，最后点击发布。",
  "inputs": [
    {"key": "content", "label": "内容", "type": "multiline", "required": true}
  ],
  "hosts": ["x.com"]
}
''';

void main() {
  test('valid model output becomes a runnable draft', () async {
    final fake = _FakeLlmService([_validDraft]);
    final service = SkillAuthoringService(llmService: fake);

    final result = await service.generate(
      description: '读取评论区并总结',
      config: _config,
      referencePage: false,
      mode: SkillAuthoringMode.flow,
    );

    expect(result.ok, isTrue, reason: result.validation.repairHint);
    expect(result.draft?.name, '评论区总结');
    expect(result.draft?.steps.single.tool, 'page.read_region');
    expect(fake.calls, 1);
  });

  test('validation failure triggers one repair call', () async {
    final fake = _FakeLlmService([_unknownToolDraft, _validDraft]);
    final service = SkillAuthoringService(llmService: fake);

    final result = await service.generate(
      description: '读取评论区并总结',
      config: _config,
      referencePage: false,
      mode: SkillAuthoringMode.flow,
    );

    expect(result.ok, isTrue, reason: result.validation.repairHint);
    expect(fake.calls, 2);
  });

  test('malformed JSON is repaired once', () async {
    final fake = _FakeLlmService(['not json', _validDraft]);
    final service = SkillAuthoringService(llmService: fake);

    final result = await service.generate(
      description: '读取评论区并总结',
      config: _config,
      referencePage: false,
      mode: SkillAuthoringMode.flow,
    );

    expect(result.ok, isTrue, reason: result.validation.repairHint);
    expect(fake.calls, 2);
  });

  test('write steps are rejected unless writes are enabled', () async {
    final fake = _FakeLlmService([_writeDraft, _writeDraft, _writeDraft]);
    final service = SkillAuthoringService(llmService: fake);

    final result = await service.generate(
      description: '点击发送按钮',
      config: _config,
      referencePage: false,
      allowWrites: false,
      mode: SkillAuthoringMode.flow,
    );

    expect(result.ok, isFalse);
    expect(result.error, isNotNull);
    expect(result.validation.hasErrors, isTrue);
  });

  test('write steps are accepted with writes and site restriction', () async {
    final fake = _FakeLlmService([_writeDraft]);
    final service = SkillAuthoringService(llmService: fake);

    final result = await service.generate(
      description: '点击发送按钮',
      config: _config,
      referencePage: false,
      allowWrites: true,
      restrictToCurrentHost: true,
      mode: SkillAuthoringMode.flow,
    );

    expect(result.ok, isTrue, reason: result.validation.repairHint);
    expect(result.draft?.policy.confirmWrites, isTrue);
    expect(result.draft?.policy.confirmDestructive, isTrue);
    // No reference page was read, so there is no host to pin; the weaker
    // "stay on the starting site" scope is the fallback.
    expect(result.draft?.policy.hostScope, SkillHostScope.currentHost);
  });

  test('AI modify never receives secret defaults or payloads', () async {
    final fake = _RecordingLlmService(_validDraft);
    final service = SkillAuthoringService(llmService: fake);
    final base = Skill(
      id: 's1',
      name: '登录并发送',
      description: '',
      kind: SkillKind.flow,
      origin: SkillOrigin.user,
      version: 1,
      inputs: const [
        SkillInput(
          key: 'password',
          label: '密码',
          type: SkillInputType.secret,
          defaultValue: 'super-secret-value',
        ),
      ],
      steps: const [
        SkillStep(
          id: 'type',
          name: '输入密码',
          tool: 'page.type',
          params: {
            'locator': {
              'candidates': [
                {'type': 'css', 'value': '#password'}
              ]
            },
            'text': 'super-secret-value',
            'secret': true,
          },
        ),
      ],
      policy: const SkillPolicy(maxSteps: 4, maxSideEffects: 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    await service.generate(
      description: '把密码输入改成更安全的方式',
      config: _config,
      referencePage: false,
      allowWrites: true,
      baseSkill: base,
      mode: SkillAuthoringMode.flow,
    );

    final sent = fake.calls.first.map((item) => item['content']).join('\n');
    expect(sent, isNot(contains('super-secret-value')));
    expect(sent, contains('••••••'));
  });

  test('instruction prompt asks for a prompt, not a step list', () {
    final prompt = SkillAuthoringPrompt.system(
      allowWrites: true,
      mode: SkillAuthoringMode.instruction,
      currentHost: 'x.com',
    );
    expect(prompt, contains('提示词技能作者'));
    expect(prompt, contains('不要输出 steps'));
    expect(prompt, contains('最多用 2 个'));
    expect(prompt, isNot(contains('可用工具')));
  });

  test('instruction mode produces a prompt skill without steps', () async {
    final fake = _FakeLlmService([_instructionDraft]);
    final service = SkillAuthoringService(llmService: fake);

    final result = await service.generate(
      description: '回复当前推文',
      config: _config,
      referencePage: false,
      mode: SkillAuthoringMode.instruction,
    );

    expect(result.ok, isTrue, reason: result.validation.repairHint);
    expect(result.draft?.kind, SkillKind.instruction);
    expect(result.draft?.steps, isEmpty);
    expect(result.draft?.instructions, contains('回复按钮'));
    expect(result.draft?.policy.hostScope, SkillHostScope.list);
    expect(result.draft?.policy.allowedHosts, ['x.com']);
    // The prompt references `tone` but never declares it; the service adds it
    // so the placeholder cannot render as an empty string. Undeclared inputs
    // stay optional — only the declaration makes a field required.
    final inputs = result.draft!.inputs;
    expect(inputs.map((input) => input.key), ['content', 'tone']);
    expect(inputs.first.required, isTrue);
    expect(inputs.last.required, isFalse);
    expect(inputs.last.label, '语气');
  });

  test('invalid config fails fast without calling the model', () async {
    final fake = _FakeLlmService([_validDraft]);
    final service = SkillAuthoringService(llmService: fake);

    final result = await service.generate(
      description: '读取评论区并总结',
      config: const LlmConfig(
        baseUrl: '',
        apiKey: '',
        model: '',
      ),
      referencePage: false,
    );

    expect(result.ok, isFalse);
    expect(fake.calls, 0);
  });
}
