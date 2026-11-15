import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:operon/agent/compactor.dart';
import 'package:operon/agent/context.dart';
import 'package:operon/agent/transcript.dart';
import 'package:operon/config/app_constants.dart';
import 'package:operon/config/app_theme.dart';
import 'package:operon/models/agent_conversation.dart';
import 'package:operon/models/agent_state.dart';
import 'package:operon/models/llm_config.dart';
import 'package:operon/services/conversation_store.dart';
import 'package:operon/services/llm_service.dart';
import 'package:operon/services/storage_service.dart';
import 'package:operon/views/settings/ai_engine_settings_page.dart';
import 'package:operon/views/widgets/agent_bottom_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('parseCompactCommand', () {
    test('parses bare /compact and optional focus note', () {
      final bare = parseCompactCommand('/compact');
      expect(bare, isNotNull);
      expect(bare!.focusNote, isEmpty);

      final withSpace = parseCompactCommand('  /COMPACT   保留价格和链接  ');
      expect(withSpace, isNotNull);
      expect(withSpace!.focusNote, '保留价格和链接');
    });

    test('rejects prefixes and prose mentioning /compact', () {
      expect(parseCompactCommand('/compactify'), isNull);
      expect(parseCompactCommand('请帮我 /compact 上下文'), isNull);
      expect(parseCompactCommand(''), isNull);
    });
  });

  group('ContextCompactor + ConversationStore + transcript', () {
    AgentConversation sampleConversation() {
      final t1 = AgentTurn(
        id: 't1',
        message: '打开商品页面查看价格',
        startedAt: DateTime(2026, 1, 1, 10, 0),
        endedAt: DateTime(2026, 1, 1, 10, 1),
        status: 'completed',
        targetUrl: 'https://shop.example.com/item/1',
        steps: const [
          AgentTurnStep(
            tool: 'navigate',
            summary: '打开商品页',
            detail: 'https://shop.example.com/item/1',
          ),
        ],
        result: '商品当前价格为 ¥199，有现货。',
      );
      final t2 = AgentTurn(
        id: 't2',
        message: '对比优惠券信息',
        startedAt: DateTime(2026, 1, 1, 10, 2),
        endedAt: DateTime(2026, 1, 1, 10, 3),
        status: 'completed',
        result: '可用满 100 减 20 优惠券，最终到手 ¥179。',
      );
      return AgentConversation(
        id: 'conv_1',
        title: '商品比价',
        createdAt: DateTime(2026, 1, 1, 10, 0),
        updatedAt: DateTime(2026, 1, 1, 10, 3),
        turns: [t1, t2],
      );
    }

    test('uses LLM summary when configured and applies compaction cleanly',
        () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final messages = body['messages'] as List<Object?>;
        final prompt = (messages.last as Map)['content'] as String;
        expect(prompt, contains('只保留价格'));

        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '- 目标：对比商品价格\n- 结论：券后 ¥179'},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final llm = LlmService(client: mockClient);
      addTearDown(llm.dispose);

      final store = ConversationStore.inMemory();
      final created = store.create(now: DateTime(2026, 1, 1, 10, 0));
      final conversation = sampleConversation();
      await store.appendTurn(created.id, conversation.turns[0]);
      await store.appendTurn(created.id, conversation.turns[1]);

      final stored = store.byId(created.id)!;
      final outcome = await ContextCompactor.compactConversation(
        stored,
        config: const LlmConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'sk-test',
          model: 'gpt-test',
        ),
        focusNote: '只保留价格',
        llmService: llm,
      );

      expect(outcome.usedLlm, isTrue);
      expect(outcome.compactedTurnCount, 2);
      expect(outcome.summary, contains('¥179'));

      final markerTurn = AgentTurn(
        id: 't_compact',
        message: '/compact 只保留价格',
        startedAt: DateTime(2026, 1, 1, 10, 4),
        endedAt: DateTime(2026, 1, 1, 10, 4),
        status: 'completed',
        result: outcome.summary,
        isCompaction: true,
      );
      await store.applyCompaction(
        created.id,
        summary: outcome.summary,
        recordTurn: markerTurn,
      );

      expect(stored.compactedTurns, 3);
      expect(stored.hasUncompactedHistory, isFalse);

      // Adding a subsequent turn leaves only the summary + the new turn in transcript.
      await store.appendTurn(
        created.id,
        AgentTurn(
          id: 't3',
          message: '帮我下单',
          startedAt: DateTime(2026, 1, 1, 10, 5),
          endedAt: DateTime(2026, 1, 1, 10, 6),
          status: 'completed',
          result: '已进入结算页。',
        ),
      );

      final messages = priorMessages(
        stored.turns,
        compactedSummary: stored.compactedSummary,
        compactedTurns: stored.compactedTurns,
      );
      expect(messages.length, 3); // summary user msg + t3 user + t3 assistant
      expect(messages.first['content'], contains('¥179'));
      expect(messages[1]['content'], '帮我下单');
      expect(messages[2]['content'], '已进入结算页。');
    });

    test('falls back to deterministic summary when endpoint fails', () async {
      final mockClient = MockClient(
        (_) async => http.Response('upstream error', 500),
      );
      final llm = LlmService(
        client: mockClient,
        retryBackoff: Duration.zero,
      );
      addTearDown(llm.dispose);

      final conversation = sampleConversation();
      final outcome = await ContextCompactor.compactConversation(
        conversation,
        config: const LlmConfig(
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'sk-test',
          model: 'gpt-test',
        ),
        llmService: llm,
      );

      expect(outcome.usedLlm, isFalse);
      expect(outcome.summary, contains('打开商品页面查看价格'));
      expect(outcome.summary, contains('对比优惠券信息'));
    });
  });

  group('ContextManager Auto-Compact', () {
    List<Map<String, Object?>> buildMessages(int intermediateTurns) {
      final list = <Map<String, Object?>>[
        {'role': 'system', 'content': 'system prompt'},
        {'role': 'user', 'content': 'initial goal'},
      ];
      for (var i = 0; i < intermediateTurns; i++) {
        list.add({
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'call_$i',
              'type': 'function',
              'function': {'name': 'read_page', 'arguments': '{}'},
            },
          ],
        });
        list.add({
          'role': 'tool',
          'tool_call_id': 'call_$i',
          'content': 'Observation #$i ${'x' * 360}',
        });
      }
      list.add({'role': 'user', 'content': 'latest instruction'});
      return list;
    }

    test('triggers autoCompacted when autoCompact is enabled and threshold hit',
        () {
      final manager = ContextManager(
        limits: const ContextLimits(
          windowTokens: 200000,
          autoCompact: true,
          autoCompactTokens: 200,
          keepRecentResults: 1,
        ),
      );
      final plan = manager.prepare(buildMessages(6));
      expect(plan.autoCompacted, isTrue);
      expect(plan.elided + plan.droppedTurns, greaterThan(0));
    });

    test('triggers autoCompacted via observedPromptTokens even on concise turns',
        () {
      final manager = ContextManager(
        limits: const ContextLimits(
          windowTokens: 200000,
          autoCompact: true,
          autoCompactTokens: 500,
          keepRecentResults: 6,
        ),
      );
      final plan = manager.prepare(
        buildMessages(4),
        observedPromptTokens: 600,
      );
      expect(plan.autoCompacted, isTrue);
      expect(plan.droppedTurns, greaterThan(0));
    });

    test('leaves context untouched below hardLimit when autoCompact is false',
        () {
      final manager = ContextManager(
        limits: const ContextLimits(
          windowTokens: 200000,
          autoCompact: false,
          autoCompactTokens: 200,
        ),
      );
      final original = buildMessages(6);
      final plan = manager.prepare(original);
      expect(plan.autoCompacted, isFalse);
      expect(plan.elided, 0);
      expect(plan.droppedTurns, 0);
      expect(plan.messages.length, original.length);
    });
  });

  group('StorageService Auto-Compact settings', () {
    test('defaults to enabled=true and 200K tokens and persists changes',
        () async {
      final storage = await StorageService.getInstance();
      expect(storage.getAutoCompactEnabled(), isTrue);
      expect(
        storage.getAutoCompactTokens(),
        AppConstants.defaultAutoCompactTokens,
      );
      expect(storage.getAutoCompactTokens(), 200000);

      await storage.saveAutoCompactEnabled(false);
      await storage.saveAutoCompactTokens(128000);
      expect(storage.getAutoCompactEnabled(), isFalse);
      expect(storage.getAutoCompactTokens(), 128000);

      await storage.saveAutoCompactEnabled(true);
      await storage.saveAutoCompactTokens(
        AppConstants.defaultAutoCompactTokens,
      );
    });
  });

  group('UI integration', () {
    testWidgets(
        'AgentBottomSheet lists /compact when typing / and renders compaction turn card',
        (tester) async {
      tester.view.physicalSize = const Size(400, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final store = ConversationStore.inMemory();
      final created = store.create(now: DateTime(2026, 1, 1, 10, 0));
      await store.appendTurn(
        created.id,
        AgentTurn(
          id: 't1',
          message: '/compact',
          startedAt: DateTime(2026, 1, 1, 10, 0),
          endedAt: DateTime(2026, 1, 1, 10, 0),
          status: 'completed',
          result: '已保留核心结论。',
          isCompaction: true,
        ),
      );

      String? startedGoal;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme.copyWith(
            splashFactory: InkRipple.splashFactory,
          ),
          home: Scaffold(
            body: AgentBottomSheet(
              state: const AgentState(),
              onStart: (_, goal, __) => startedGoal = goal,
              onResume: () {},
              onStop: () {},
              onConfirmAction: (_) {},
              onConfirmCaptcha: (_) {},
              safeMode: true,
              onSafeModeChanged: (_) {},
              prompts: const [],
              store: store,
              conversationId: created.id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已压缩上下文'), findsOneWidget);
      await tester.tap(find.text('已压缩上下文'));
      await tester.pumpAndSettle();
      expect(find.text('已保留核心结论。'), findsOneWidget);

      await tester.tap(find.text('指令'));
      await tester.pumpAndSettle();
      expect(find.text('/compact [重点说明]'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '/com');
      await tester.pumpAndSettle();

      expect(find.text('/compact [重点说明]'), findsOneWidget);
      expect(find.textContaining('压缩当前对话上下文'), findsOneWidget);

      await tester.tap(find.text('/compact [重点说明]'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '/compact ');

      await tester.tap(find.byTooltip('开始任务'));
      await tester.pumpAndSettle();
      expect(startedGoal, '/compact');
    });

    testWidgets('AiEngineSettingsPage exposes Auto-Compact toggle & threshold',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme.copyWith(
            splashFactory: InkRipple.splashFactory,
          ),
          home: const AiEngineSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Auto-Compact 触发阈值（token）'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('自动压缩上下文（Auto-Compact）'), findsOneWidget);
      expect(find.text('Auto-Compact 触发阈值（token）'), findsOneWidget);
      final thresholdField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Auto-Compact 触发阈值（token）'),
      );
      expect(thresholdField.controller!.text, '200000');

      await tester.enterText(
        find.widgetWithText(TextField, 'Auto-Compact 触发阈值（token）'),
        '128000',
      );
      await tester.pumpAndSettle();

      final storage = await StorageService.getInstance();
      expect(storage.getAutoCompactTokens(), 128000);

      await tester.tap(find.text('自动压缩上下文（Auto-Compact）'));
      await tester.pumpAndSettle();
      expect(storage.getAutoCompactEnabled(), isFalse);

      await storage.saveAutoCompactEnabled(true);
      await storage.saveAutoCompactTokens(
        AppConstants.defaultAutoCompactTokens,
      );
    });
  });
}
