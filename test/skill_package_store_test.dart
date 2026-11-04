import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/skill.dart';
import 'package:operon/services/skill_package_codec.dart';
import 'package:operon/services/skill_package_store.dart';

const _instruction = Skill(
  id: 'scroll_summary',
  name: '滚动总结',
  description: '总结当前页面。',
  kind: SkillKind.instruction,
  instructions: '读取当前页面并总结。',
  policy: SkillPolicy(maxSteps: 5),
);

const _flow = Skill(
  id: 'reply_timeline',
  name: '回复时间线',
  description: '回复时间线推文。',
  kind: SkillKind.flow,
  steps: [
    SkillStep(
      id: 'step_1_click',
      name: '点击回复',
      tool: 'page.click',
      params: {
        'locator': {
          'candidates': [
            {'type': 'css', 'value': '[data-testid="reply"]'},
          ],
          'requireUnique': false,
          'nth': 0,
        },
      },
    ),
  ],
  policy: SkillPolicy(maxSteps: 5, maxSideEffects: 1),
);

void main() {
  late Directory root;
  late FileSkillPackageStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('operon_skill_pkg_');
    store = FileSkillPackageStore(root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('sync writes SKILL.md and flow.json where needed', () async {
    await store.sync(const [_instruction, _flow]);

    final instructionDir = Directory(
        '${root.path}/${SkillPackageCodec.packageDirName(_instruction)}');
    final flowDir =
        Directory('${root.path}/${SkillPackageCodec.packageDirName(_flow)}');

    expect(
      await File('${instructionDir.path}/SKILL.md').exists(),
      isTrue,
    );
    expect(
      await File('${instructionDir.path}/flow.json').exists(),
      isFalse,
    );
    expect(await File('${flowDir.path}/SKILL.md').exists(), isTrue);
    expect(await File('${flowDir.path}/flow.json').exists(), isTrue);
  });

  test('readAll returns decodable packages', () async {
    await store.sync(const [_instruction, _flow]);
    final entries = await store.readAll();
    final skills = entries
        .map((entry) => SkillPackageCodec.decode(
              entry.files,
              dirName: entry.dirName,
            ))
        .toList();

    expect(skills, hasLength(2));
    expect(
        skills.map((skill) => skill.id),
        containsAll([
          'scroll_summary',
          'reply_timeline',
        ]));
    final flow = skills.firstWhere((skill) => skill.id == 'reply_timeline');
    expect(flow.steps.single.tool, 'page.click');
  });

  test('sync removes packages for deleted skills', () async {
    await store.sync(const [_instruction, _flow]);
    await store.sync(const [_instruction]);

    final entries = await store.readAll();
    final ids = entries.map((entry) => SkillPackageCodec.decode(
          entry.files,
          dirName: entry.dirName,
        ).id);
    expect(ids, contains('scroll_summary'));
    expect(ids, isNot(contains('reply_timeline')));
  });

  test('unreadable or corrupt packages are skipped', () async {
    await store.sync(const [_flow]);
    final dir = Directory(
      '${root.path}/${SkillPackageCodec.packageDirName(_flow)}',
    );
    await File('${dir.path}/flow.json').writeAsString('not-json');

    final entries = await store.readAll();
    expect(entries, hasLength(1));
    expect(
      () => SkillPackageCodec.decode(
        entries.single.files,
        dirName: entries.single.dirName,
      ),
      throwsA(isA<SkillPackageException>()),
    );
  });

  test('a hand-written or corrupt package is never deleted', () async {
    await store.sync(const [_instruction]);

    // A user drops in a package the store did not write, and another one is
    // corrupt. Neither may be pruned by the next save.
    final handWritten = Directory('${root.path}/my_own_skill');
    await handWritten.create(recursive: true);
    await File('${handWritten.path}/SKILL.md').writeAsString('''
---
name: 我手写的技能
---

总结当前页面。
''');
    final corrupt = Directory('${root.path}/broken_skill');
    await corrupt.create(recursive: true);
    await File('${corrupt.path}/SKILL.md').writeAsString('not a package');

    await store.sync(const [_instruction]);

    expect(await handWritten.exists(), isTrue);
    expect(await corrupt.exists(), isTrue);
  });

  test('an instruction skill removes a stale flow.json', () async {
    final flowDir =
        Directory('${root.path}/${SkillPackageCodec.packageDirName(_flow)}');
    await store.sync(const [_flow]);
    expect(await File('${flowDir.path}/flow.json').exists(), isTrue);

    // Same id and directory, but the skill changed to instruction.
    const changed = Skill(
      id: 'reply_timeline',
      name: '回复时间线',
      kind: SkillKind.instruction,
      instructions: '只读说明。',
    );
    await store.sync(const [changed]);
    expect(await File('${flowDir.path}/flow.json').exists(), isFalse);
  });
}
