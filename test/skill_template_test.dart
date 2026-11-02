import 'package:flutter_test/flutter_test.dart';
import 'package:operon/utils/skill_template.dart';

void main() {
  test('renders inputs and step data in strings', () {
    final context = <String, dynamic>{
      'inputs': {'count': 3, 'tone': '友好'},
      'steps': {
        'comments': {
          'data': {
            'items': [
              {'text': '第一条'},
              {'text': '第二条'},
            ],
          },
        },
      },
    };

    expect(
      SkillTemplate.renderString('处理 {{inputs.count}} 条，语气 {{ inputs.tone }}。',
          context),
      '处理 3 条，语气 友好。',
    );
    expect(
      SkillTemplate.renderString('{{steps.comments.data.items.1.text}}', context),
      '第二条',
    );
  });

  test('exact placeholders preserve the original type', () {
    final context = <String, dynamic>{
      'inputs': {'count': 3, 'enabled': true},
      'steps': {
        'list': {
          'data': [
            {'text': 'a'},
          ],
        },
      },
    };

    expect(
      SkillTemplate.renderValue('{{inputs.count}}', context),
      isA<int>(),
    );
    expect(
      SkillTemplate.renderValue('{{inputs.enabled}}', context),
      isA<bool>(),
    );
    expect(
      SkillTemplate.renderValue('{{steps.list.data}}', context),
      isA<List>(),
    );
  });

  test('embedded list value is JSON encoded', () {
    final rendered = SkillTemplate.renderString(
      '结果：{{steps.list.data}}',
      {
        'steps': {
          'list': {
            'data': [
              {'text': 'a'},
            ],
          },
        },
      },
    );
    expect(rendered, contains('"text":"a"'));
  });

  test('renders nested maps and lists', () {
    final rendered = SkillTemplate.renderValue(
      {
        'url': 'https://example.com/{{inputs.id}}',
        'items': ['{{inputs.id}}', 2],
      },
      {
        'inputs': {'id': '42'},
      },
    ) as Map<String, dynamic>;

    expect(rendered['url'], 'https://example.com/42');
    expect(rendered['items'], ['42', 2]);
  });

  test('unknown variables fail in strict mode and can be relaxed', () {
    expect(
      () => SkillTemplate.renderString('{{inputs.missing}}', {}),
      throwsA(isA<SkillTemplateException>()),
    );
    expect(
      SkillTemplate.renderString('x{{inputs.missing}}y', {}, strict: false),
      'xy',
    );
  });

  test('escaped braces stay literal', () {
    expect(
      SkillTemplate.renderString(r'\{{inputs.name}}', {
        'inputs': {'name': 'n'},
      }),
      '{{inputs.name}}',
    );
  });

  test('references are discovered recursively', () {
    final refs = SkillTemplate.referencesIn({
      'a': '{{inputs.one}}',
      'b': ['{{steps.read.data}}', {'c': '{{env.url}}'}],
    });

    expect(refs, containsAll(['inputs.one', 'steps.read.data', 'env.url']));
  });

  test('bare input keys remain compatible with old quick commands', () {
    expect(
      SkillTemplate.renderString('处理 {{count}} 条', {
        'inputs': {'count': '5'},
      }),
      '处理 5 条',
    );
  });
}
