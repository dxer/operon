import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/skill_repair_service.dart';

void main() {
  test('parses a locator from plain JSON', () {
    final locator = SkillRepairService.parseLocator('''
{"locator":{"candidates":[{"type":"text","value":"回复"}],"requireUnique":true},"reason":"按钮文字唯一"}
''');

    expect(locator, isNotNull);
    expect(locator!['candidates'], hasLength(1));
    expect(locator['requireUnique'], isTrue);
  });

  test('parses a locator wrapped in a Markdown fence', () {
    final locator = SkillRepairService.parseLocator('''
```json
{"locator":{"candidates":[{"type":"css","value":".reply"}]}}
```
''');

    expect(locator, isNotNull);
    expect(locator!['requireUnique'], isTrue);
  });

  test('rejects missing or empty candidates', () {
    expect(SkillRepairService.parseLocator('{"reason":"no locator"}'), isNull);
    expect(
      SkillRepairService.parseLocator(
        '{"locator":{"candidates":[]}}',
      ),
      isNull,
    );
    expect(
      SkillRepairService.parseLocator(
        '{"locator":{"candidates":[{"type":"text"}]}}',
      ),
      isNull,
    );
  });

  test('accepts role candidates but rejects semantic-only candidates', () {
    final role = SkillRepairService.parseLocator(
      '{"locator":{"candidates":[{"type":"role","role":"button","name":"回复"}]}}',
    );
    expect(role, isNotNull);

    final semantic = SkillRepairService.parseLocator(
      '{"locator":{"candidates":[{"type":"semantic","value":"回复按钮"}]}}',
    );
    expect(semantic, isNull);
  });

  test('canRepair only accepts locator-based steps', () {
    const click = SkillStep(
      id: 's1',
      name: '点击回复',
      tool: 'page.click',
      params: {
        'locator': {
          'candidates': [
            {'type': 'text', 'value': '回复'},
          ],
        },
      },
    );
    const open = SkillStep(
      id: 's2',
      name: '打开网页',
      tool: 'page.open',
      params: {'url': 'https://example.com'},
    );
    const clickWithoutLocator = SkillStep(
      id: 's3',
      name: '点击',
      tool: 'page.click',
    );

    expect(SkillRepairService.canRepair(click), isTrue);
    expect(SkillRepairService.canRepair(open), isFalse);
    expect(SkillRepairService.canRepair(clickWithoutLocator), isFalse);
  });
}
