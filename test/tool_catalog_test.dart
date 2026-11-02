import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/tool_catalog.dart';
import 'package:operon/models/tool_descriptor.dart';

void main() {
  test('tool ids are unique', () {
    final ids = ToolCatalog.all.map((tool) => tool.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('P1 exposes the twelve core tools', () {
    expect(ToolCatalog.p1.length, 12);
    expect(ToolCatalog.p1.every((tool) => ToolCatalog.isP1(tool.id)), isTrue);
    expect(ToolCatalog.find('page.read_region')?.risk, ToolRisk.read);
    expect(ToolCatalog.find('page.click')?.risk, ToolRisk.write);
    expect(ToolCatalog.find('ai.generate')?.cost, ToolCost.llm);
  });

  test('every tool has unique parameter keys', () {
    for (final tool in ToolCatalog.all) {
      final keys = tool.params.map((param) => param.key).toList();
      expect(keys.toSet().length, keys.length,
          reason: '${tool.id} has duplicate params');
    }
  });

  test('editor exposes all implemented tools', () {
    expect(ToolCatalog.availableIds, contains('agent.task'));
    expect(ToolCatalog.availableIds, contains('macro.run'));
    expect(ToolCatalog.availableIds, contains('notify'));
    expect(ToolCatalog.availableIds, isNot(contains('page.screenshot')));
  });

  test('prompt catalog exposes implemented authoring tools only', () {
    final catalog = ToolCatalog.promptCatalog();
    expect(catalog.length, ToolCatalog.authoringIds.length);
    expect(catalog.map((item) => item['id']), contains('agent.task'));
    expect(catalog.map((item) => item['id']), isNot(contains('macro.run')));
  });

  test('committing write tools require confirmation by default', () {
    for (final id in [
      'page.click',
      'page.type',
      'page.press_key',
      'page.select',
      'macro.run',
    ]) {
      final tool = ToolCatalog.find(id);
      expect(tool, isNotNull);
      expect(tool!.isWrite, isTrue);
      expect(tool.requiresConfirmation, isTrue,
          reason: '$id should require confirmation');
    }
  });
}
