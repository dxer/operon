import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/agent_action.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/skill_recording_session.dart';

Map<String, dynamic> _locator(String css, {bool unique = true}) {
  return {
    'ok': true,
    'count': 1,
    'locator': {
      'candidates': [
        {'type': 'css', 'value': css},
        {'type': 'text', 'value': 'Reply', 'tag': 'div'},
      ],
      'requireUnique': unique,
      if (!unique) 'nth': 0,
      'fingerprint': 'not-persisted',
    },
  };
}

void main() {
  SkillRecordingSession session({
    String sample = '这是一条示例回复',
    String host = 'x.com',
  }) {
    return SkillRecordingSession(
      sampleContent: sample,
      currentHost: host,
    );
  }

  test('records a click using the real locator and drops the fingerprint', () {
    final recorder = session();
    final ok = recorder.capture(
      const AgentAction(
        thought: '打开回复框',
        action: ActionType.click,
        elementId: 3,
      ),
      locator: _locator('[data-testid="reply"]', unique: false),
      elementText: 'Reply',
    );

    expect(ok, isTrue);
    final step = recorder.steps.single;
    expect(step.tool, 'page.click');
    expect(step.name, contains('Reply'));
    final locator = step.params['locator'] as Map<String, dynamic>;
    expect(locator['candidates'], hasLength(2));
    expect(locator['requireUnique'], isFalse);
    expect(locator['nth'], 0);
    expect(locator.containsKey('fingerprint'), isFalse);
  });

  test('typed demonstration content becomes the content input', () {
    final recorder = session(sample: '很有启发，感谢分享。');
    final ok = recorder.capture(
      const AgentAction(
        thought: '填写回复',
        action: ActionType.type,
        elementId: 8,
        text: '很有启发，感谢分享。',
      ),
      locator: _locator('[data-testid="tweetTextarea_0"]'),
      elementText: 'Post text',
    );

    expect(ok, isTrue);
    expect(recorder.steps.single.params['text'], '{{inputs.content}}');
    expect(recorder.hasContentInput, isTrue);
    expect(recorder.inputs.single.key, 'content');
    expect(recorder.inputs.single.type, SkillInputType.multiline);
    expect(recorder.inputs.single.required, isTrue);
  });

  test('non-demonstration text is recorded literally and braces are escaped',
      () {
    final recorder = session(sample: '示例回复');
    recorder.capture(
      const AgentAction(
        thought: '输入搜索词',
        action: ActionType.type,
        elementId: 2,
        text: '关键字 {{raw}}',
      ),
      locator: _locator('input[type="search"]'),
      elementText: 'Search',
    );

    expect(recorder.steps.single.params['text'], r'关键字 \{{raw}}');
    expect(recorder.hasContentInput, isFalse);
  });

  test('dry-run submit keeps the submit intent and ends the recording', () {
    final recorder = session();
    final ok = recorder.capture(
      const AgentAction(
        thought: '点击发布',
        action: ActionType.click,
        elementId: 9,
      ),
      locator: _locator('[data-testid="tweetButtonInline"]'),
      elementText: 'Post',
      dryRun: true,
      intent: 'submit',
    );

    expect(ok, isTrue);
    expect(recorder.endedWithDryRun, isTrue);
    final step = recorder.steps.single;
    expect(step.params['intent'], 'submit');
    expect(step.tool, 'page.click');

    final draft = recorder.buildDraft(
      name: '回复推文',
      description: '回复时间线推文',
    )!;
    expect(draft.notes, contains('没有真正点击'));
    // A recorded write is pinned to the host it was recorded on, so it cannot
    // be replayed on another site.
    expect(draft.policy.hostScope, SkillHostScope.list);
    expect(draft.policy.allowedHosts, ['x.com']);
    expect(draft.policy.maxSideEffects, 1);
  });

  test('a click without a locator is not recorded', () {
    final recorder = session();
    final ok = recorder.capture(
      const AgentAction(
        thought: '点击发布',
        action: ActionType.click,
        elementId: 9,
      ),
      elementText: 'Post',
    );

    expect(ok, isFalse);
    expect(recorder.steps, isEmpty);
  });

  test('macro selector is used only as an explicit CSS fallback', () {
    final recorder = session();
    recorder.capture(
      const AgentAction(
        thought: '点击条目',
        action: ActionType.click,
        elementId: 4,
      ),
      macroSelector: 'article:nth-of-type(1)',
      elementText: 'Article',
    );

    final locator =
        recorder.steps.single.params['locator'] as Map<String, dynamic>;
    final candidates = locator['candidates'] as List;
    expect((candidates.single as Map)['type'], 'css');
    expect((candidates.single as Map)['value'], 'article:nth-of-type(1)');
  });

  test('xpath macro selectors are stored as xpath locators', () {
    final recorder = session();
    recorder.capture(
      const AgentAction(
        thought: '点击条目',
        action: ActionType.click,
        elementId: 4,
      ),
      macroSelector: 'xpath://button[contains(text(), "Publish")]',
      elementText: 'Publish',
    );

    final locator =
        recorder.steps.single.params['locator'] as Map<String, dynamic>;
    final candidate = (locator['candidates'] as List).single as Map;
    expect(candidate['type'], 'xpath');
    expect(candidate['value'], 'button[contains(text(), "Publish")]');
  });

  test('navigating records page.open and updates the host', () {
    final recorder = session(host: '');
    recorder.capture(
      const AgentAction(
        thought: '打开网站',
        action: ActionType.navigate,
        url: 'https://www.x.com/home',
      ),
    );

    expect(recorder.steps.single.tool, 'page.open');
    expect(recorder.steps.single.params['url'], 'https://www.x.com/home');
    expect(recorder.host, 'x.com');
  });

  test('buildDraft sizes the policy and pins the host for writes', () {
    final recorder = session();
    recorder.capture(
      const AgentAction(
        thought: '打开回复',
        action: ActionType.click,
        elementId: 3,
      ),
      locator: _locator('[data-testid="reply"]', unique: false),
      elementText: 'Reply',
    );
    recorder.capture(
      const AgentAction(
        thought: '填写回复',
        action: ActionType.type,
        elementId: 8,
        text: '这是一条示例回复',
      ),
      locator: _locator('[data-testid="tweetTextarea_0"]'),
      elementText: 'Post text',
    );
    recorder.capture(
      const AgentAction(
        thought: '点击发布',
        action: ActionType.click,
        elementId: 9,
      ),
      locator: _locator('[data-testid="tweetButtonInline"]'),
      elementText: 'Post',
      dryRun: true,
      intent: 'submit',
    );

    final draft = recorder.buildDraft(
      name: '',
      description: '回复时间线推文',
    )!;
    expect(draft.kind, SkillKind.flow);
    expect(draft.steps, hasLength(3));
    expect(draft.policy.maxSteps, 7);
    expect(draft.policy.maxSideEffects, 3);
    expect(draft.policy.uniqueContent, isTrue);
    expect(draft.policy.confirmWrites, isTrue);
    expect(draft.policy.confirmDestructive, isTrue);
    expect(draft.policy.hostScope, SkillHostScope.list);
    expect(draft.policy.allowedHosts, ['x.com']);
    expect(draft.name, '回复时间线推文');
  });

  test('duplicate consecutive actions are ignored', () {
    final recorder = session();
    const action = AgentAction(
      thought: '滚动',
      action: ActionType.scroll,
      direction: 'down',
    );
    expect(recorder.capture(action), isTrue);
    expect(recorder.capture(action), isFalse);
    expect(recorder.steps, hasLength(1));
  });

  test('isSampleText only matches the demonstration content', () {
    final recorder = session(sample: '示例回复');
    expect(recorder.isSampleText('示例回复'), isTrue);
    expect(recorder.isSampleText(' 示例回复 '), isTrue);
    expect(recorder.isSampleText('搜索词'), isFalse);
    expect(recorder.isSampleText(null), isFalse);
  });

  test('an unlabelled demonstration body still becomes an input', () {
    // No sample was typed in the creation form, so the recorder only has the
    // literal text the agent entered. Baking it in would repost the same
    // sentence on every run.
    final recorder = session(sample: '');
    recorder.capture(
      const AgentAction(
        thought: '填写回复',
        action: ActionType.type,
        elementId: 8,
        text: '这条演示内容不该被写死',
      ),
      locator: _locator('[data-testid="tweetTextarea_0"]'),
      elementText: 'Post text',
    );
    recorder.capture(
      const AgentAction(
        thought: '发布',
        action: ActionType.click,
        elementId: 9,
      ),
      locator: _locator('[data-testid="tweetButton"]'),
      elementText: '发布',
      dryRun: true,
      intent: 'submit',
    );

    final draft = recorder.buildDraft(name: '回复', description: '回复推文')!;
    expect(draft.steps.first.params['text'], '{{inputs.content}}');
    expect(draft.inputs.single.key, 'content');
    expect(draft.inputs.single.hint, contains('这条演示内容不该被写死'));
  });

  test('two different typed texts are left alone instead of guessed', () {
    final recorder = session(sample: '');
    for (final (id, text) in [(1, '关键词'), (2, '正文内容')]) {
      recorder.capture(
        AgentAction(
          thought: '输入',
          action: ActionType.type,
          elementId: id,
          text: text,
        ),
        locator: _locator('textarea:nth-of-type($id)'),
        elementText: '输入框',
      );
    }
    recorder.capture(
      const AgentAction(thought: '发布', action: ActionType.click, elementId: 3),
      locator: _locator('#send'),
      elementText: '发送',
      dryRun: true,
    );

    final draft = recorder.buildDraft(name: '技能', description: '技能')!;
    expect(draft.inputs, isEmpty);
    expect(draft.steps[0].params['text'], '关键词');
    expect(draft.steps[1].params['text'], '正文内容');
  });

  test('deriveName strips common creation prefixes', () {
    expect(
      SkillRecordingSession.deriveName('创建一个回复 x.com 时间线推文的技能'),
      '回复 x.com 时间线推文',
    );
  });
}
