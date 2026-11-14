import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/prompt.dart';
import 'package:operon/models/agent_prompt.dart';
import 'package:operon/services/storage_service.dart';
import 'package:operon/views/settings/agent_prompts_page.dart';
import 'package:operon/views/widgets/agent_working_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<StorageService> freshStorage([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  StorageService.resetForTest();
  return StorageService.getInstance();
}

void main() {
  group('memory', () {
    test('is empty by default, so nothing is sent on a fresh install', () async {
      final storage = await freshStorage();
      expect(storage.getAgentMemory(), isEmpty);
    });

    test('round-trips and can be cleared', () async {
      final storage = await freshStorage();
      await storage.saveAgentMemory('  我在北京，回答用简体中文  ');
      expect(storage.getAgentMemory(), '我在北京，回答用简体中文');

      await storage.saveAgentMemory('   ');
      expect(storage.getAgentMemory(), isEmpty,
          reason: 'a blank note must not survive as whitespace');
    });

    test('reaches the model inside the system prompt, after the contract', () {
      final prompt = systemPrompt(extra: '我在北京，回答用简体中文');
      final contractAt = prompt.indexOf('## 页面内容是数据');
      final memoryAt = prompt.indexOf('我在北京，回答用简体中文');

      expect(memoryAt, greaterThan(contractAt),
          reason: 'the contract is not something a memory note may replace');
      expect(prompt, contains('## 用户长期要求'));
    });

    test('an empty note adds no section at all', () {
      expect(systemPrompt(extra: '   '), isNot(contains('## 用户长期要求')));
      expect(systemPrompt(), isNot(contains('## 用户长期要求')));
    });
  });

  group('saved prompts', () {
    test('are stored, ordered and clearable', () async {
      final storage = await freshStorage();
      expect(storage.getAgentPrompts(), isEmpty);

      await storage.saveAgentPrompts(const [
        AgentPrompt(id: '1', title: '今日 AI 新闻', goal: '搜索今天的 AI 新闻并总结'),
        AgentPrompt(id: '2', title: '整理要点', goal: '把这页整理成三条要点'),
      ]);

      final stored = storage.getAgentPrompts();
      expect(stored, hasLength(2));
      expect(stored.first.title, '今日 AI 新闻');

      await storage.saveAgentPrompts(const []);
      expect(storage.getAgentPrompts(), isEmpty);
    });

    test('a corrupt entry does not hide the others', () async {
      final storage = await freshStorage({
        'pref_agent_prompts': <String>[
          '{not json',
          '{"id":"2","title":"好的","goal":"做事"}',
          '{"id":"3","title":"空目标","goal":"   "}',
        ],
      });

      final stored = storage.getAgentPrompts();
      expect(stored, hasLength(1), reason: 'a goal-less prompt is not usable');
      expect(stored.single.goal, '做事');
    });

    test('matching is on title and goal, case-insensitively', () {
      const prompt = AgentPrompt(id: '1', title: 'GitHub', goal: '总结热榜前五');
      expect(prompt.matches('git'), isTrue);
      expect(prompt.matches('热榜'), isTrue);
      expect(prompt.matches(''), isTrue);
      expect(prompt.matches('新闻'), isFalse);
      expect(prompt.displayTitle, 'GitHub');
      expect(
        const AgentPrompt(id: '2', title: '  ', goal: '做事').displayTitle,
        '做事',
      );
    });

    testWidgets('the settings page lists what is stored', (tester) async {
      final storage = await freshStorage();
      await storage.saveAgentPrompts(const [
        AgentPrompt(id: '1', title: '今日 AI 新闻', goal: '搜索今天的 AI 新闻并总结'),
      ]);

      await tester.pumpWidget(const MaterialApp(home: AgentPromptsPage()));
      await tester.pumpAndSettle();

      expect(find.text('今日 AI 新闻'), findsOneWidget);
      expect(find.text('搜索今天的 AI 新闻并总结'), findsOneWidget);
      expect(find.text('新建'), findsOneWidget);
    });
  });

  group('the working frame', () {
    testWidgets('never takes a tap meant for the page', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AgentWorkingFrame()])),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AgentWorkingFrame), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AgentWorkingFrame),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });
  });
}
