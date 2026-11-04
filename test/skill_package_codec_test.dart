import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/skill_package_codec.dart';

const _input = SkillInput(
  key: 'content',
  label: '内容',
  type: SkillInputType.multiline,
  required: true,
  hint: '要发布的内容',
);

Skill _instruction() {
  return const Skill(
    id: 'scroll_summary',
    name: '滚动总结',
    description: '总结当前页面。',
    kind: SkillKind.instruction,
    inputs: [_input],
    instructions: '读取当前页面，总结成三点。\n不要点击任何按钮。',
    policy: SkillPolicy(maxSteps: 8, maxItems: 1),
    output: {'summary': '{{steps.read.data}}'},
    builtin: true,
    sortOrder: 2,
  );
}

Skill _flow() {
  return const Skill(
    id: 'reply_timeline',
    name: '回复时间线',
    description: '回复 x.com 时间线上的推文。',
    kind: SkillKind.flow,
    inputs: [_input],
    steps: [
      SkillStep(
        id: 'step_1_click',
        name: '点击回复',
        tool: 'page.click',
        params: {
          'locator': {
            'candidates': [
              {'type': 'css', 'value': '[data-testid="reply"]'},
              {'type': 'text', 'value': 'Reply', 'tag': 'div'},
            ],
            'requireUnique': false,
            'nth': 0,
          },
        },
      ),
      SkillStep(
        id: 'step_2_type',
        name: '输入内容',
        tool: 'page.type',
        params: {
          'locator': {
            'candidates': [
              {'type': 'css', 'value': '[data-testid="tweetTextarea_0"]'},
            ],
            'requireUnique': true,
          },
          'text': '{{inputs.content}}',
          'clear': true,
        },
      ),
      SkillStep(
        id: 'step_3_submit',
        name: '点击发布',
        tool: 'page.click',
        params: {
          'locator': {
            'candidates': [
              {'type': 'css', 'value': '[data-testid="tweetButtonInline"]'},
            ],
            'requireUnique': true,
          },
          'intent': 'submit',
        },
      ),
    ],
    policy: SkillPolicy(
      maxSteps: 7,
      maxSideEffects: 3,
      hostScope: SkillHostScope.currentHost,
      confirmWrites: true,
    ),
  );
}

void main() {
  test('instruction skill round-trips with a minimal SKILL.md', () {
    final files = SkillPackageCodec.encode(_instruction());
    expect(files.flowJson, isNull);
    expect(files.markdown, startsWith('---\n'));
    expect(files.markdown, contains('name: "滚动总结"'));
    expect(files.markdown, contains('不要点击任何按钮。'));
    expect(files.markdown, isNot(contains('operon-kind')));
    expect(files.markdown, isNot(contains('metadata:')));

    final decoded = SkillPackageCodec.decode(
      files,
      dirName: 'scroll_summary',
    );
    expect(decoded.id, 'scroll_summary');
    expect(decoded.name, '滚动总结');
    expect(decoded.kind, SkillKind.instruction);
    expect(decoded.instructions, contains('总结成三点'));
    expect(decoded.inputs.single.key, 'content');
    expect(decoded.policy.maxSteps, 8);
    // Result mapping is portable; app state lives in prefs.
    expect(decoded.output['summary'], '{{steps.read.data}}');
    expect(decoded.builtin, isFalse);
    expect(decoded.sortOrder, 0);
  });

  test('flow skill round-trips through SKILL.md + flow.json', () {
    final files = SkillPackageCodec.encode(_flow());
    expect(files.flowJson, isNotNull);
    expect(files.markdown, contains('## 步骤'));
    expect(files.markdown, contains('点击回复'));
    expect(files.markdown, isNot(contains('kind:')));

    final decoded = SkillPackageCodec.decode(
      files,
      dirName: 'reply_timeline',
    );
    expect(decoded.id, 'reply_timeline');
    expect(decoded.kind, SkillKind.flow);
    expect(decoded.steps, hasLength(3));
    expect(decoded.steps[1].params['text'], '{{inputs.content}}');
    expect(decoded.steps[2].params['intent'], 'submit');
    expect(
      (decoded.steps.first.params['locator'] as Map)['nth'],
      0,
    );
    expect(decoded.policy.hostScope, SkillHostScope.currentHost);
    expect(decoded.instructions, isEmpty);
  });

  test('a flow SKILL.md without flow.json becomes an instruction skill', () {
    final files = SkillPackageCodec.encode(_flow());
    final decoded = SkillPackageCodec.decode(
      SkillPackageFiles(markdown: files.markdown),
      dirName: 'reply_timeline',
    );
    expect(decoded.kind, SkillKind.instruction);
    expect(decoded.steps, isEmpty);
    expect(decoded.instructions, contains('## 步骤'));
  });

  test('old metadata format still decodes', () {
    const markdown = '''
---
name: 旧技能
description: 旧格式
metadata:
  operon-id: old_skill
  operon-kind: instruction
  operon-builtin: true
  operon-sort-order: 3
  operon-inputs:
    - key: content
      label: 内容
      type: multiline
      defaultValue: ""
      required: true
---

使用 {{inputs.content}}。
''';

    final decoded = SkillPackageCodec.decode(
      const SkillPackageFiles(markdown: markdown),
    );
    expect(decoded.id, 'old_skill');
    expect(decoded.kind, SkillKind.instruction);
    expect(decoded.builtin, isTrue);
    expect(decoded.sortOrder, 3);
    expect(decoded.inputs.single.type, SkillInputType.multiline);
    expect(decoded.inputs.single.required, isTrue);
  });

  test('old flow metadata without flow.json is rejected', () {
    const markdown = '''
---
name: 旧流程
metadata:
  operon-kind: flow
---

旧流程说明。
''';
    expect(
      () => SkillPackageCodec.decode(
        const SkillPackageFiles(markdown: markdown),
      ),
      throwsA(isA<SkillPackageException>()),
    );
  });

  test('undeclared input placeholders become inputs automatically', () {
    const skill = Skill(
      id: 'reply',
      name: '回复',
      kind: SkillKind.instruction,
      instructions: '用 {{inputs.tone}} 的语气回复当前推文。',
    );
    final files = SkillPackageCodec.encode(skill);
    expect(files.markdown, isNot(contains('inputs:')));

    final decoded = SkillPackageCodec.decode(files, dirName: 'reply');
    expect(decoded.inputs.single.key, 'tone');
    expect(decoded.inputs.single.required, isTrue);
  });

  test('hosts are portable and drive matchesHost', () {
    const skill = Skill(
      id: 'reply_x',
      name: '回复推文',
      kind: SkillKind.instruction,
      instructions: '回复当前推文。',
      policy: SkillPolicy(
        hostScope: SkillHostScope.list,
        allowedHosts: ['x.com'],
      ),
    );
    final files = SkillPackageCodec.encode(skill);
    expect(files.markdown, contains('hosts:'));

    final decoded = SkillPackageCodec.decode(files, dirName: 'reply_x');
    expect(decoded.policy.hostScope, SkillHostScope.list);
    expect(decoded.policy.allowedHosts, ['x.com']);
    expect(decoded.matchesHost('www.x.com'), isTrue);
    expect(decoded.matchesHost('example.com'), isFalse);
  });

  test('a standard SKILL.md imports as an instruction skill', () {
    const markdown = '''
---
name: reply-x-timeline
description: Reply to posts on the x.com timeline.
---

# Reply to timeline

Read the current page, open the reply box, and write a reply.
''';
    final skill = SkillPackageCodec.decode(
      const SkillPackageFiles(markdown: markdown),
    );

    expect(skill.kind, SkillKind.instruction);
    expect(skill.name, 'Reply to timeline');
    expect(skill.id, 'skill_reply-to-timeline');
    expect(skill.description, 'Reply to posts on the x.com timeline.');
    expect(skill.instructions, contains('open the reply box'));
    expect(skill.builtin, isFalse);
  });

  test('a file without frontmatter is rejected', () {
    expect(
      () => SkillPackageCodec.decode(
        const SkillPackageFiles(markdown: '# Just a document\n'),
      ),
      throwsA(isA<SkillPackageException>()),
    );
  });

  test('frontmatter values with punctuation survive YAML quoting', () {
    const skill = Skill(
      id: 'quoted',
      name: '含冒号: 的技能',
      description: '第一行\n第二行 "quoted"',
      kind: SkillKind.instruction,
      instructions: '做一件事。',
      policy: SkillPolicy(stopOn: ['captcha', 'error']),
    );

    final decoded = SkillPackageCodec.decode(
      SkillPackageCodec.encode(skill),
      dirName: 'quoted',
    );

    expect(decoded.name, '含冒号: 的技能');
    expect(decoded.description, '第一行\n第二行 "quoted"');
    expect(decoded.policy.stopOn, ['captcha', 'error']);
  });

  test('package directory names are stable and filesystem-safe', () {
    const a = Skill(id: 'skill_123', name: '我的技能');
    const b = Skill(id: 'skill_123', name: '改名了');
    const c = Skill(id: '带中文的 id', name: '中文');

    expect(SkillPackageCodec.packageDirName(a), 'skill_123');
    expect(SkillPackageCodec.packageDirName(a),
        SkillPackageCodec.packageDirName(b));
    expect(
      SkillPackageCodec.packageDirName(c),
      matches(RegExp(r'^skill_[a-z0-9_]+$')),
    );
  });
}
