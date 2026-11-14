import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/agent_task_record.dart';
import 'package:operon/services/goal_handoff.dart';
import 'package:operon/utils/task_markdown.dart';

AgentTaskRecord record({
  String goal = '把这三条新闻的要点整理出来',
  String status = 'completed',
  String? targetUrl = 'https://example.com/news',
  String? errorMessage,
  List<String> logs = const ['步骤 1: 读取页面', '步骤 2: 完成'],
  List<String> sensitive = const [],
}) {
  return AgentTaskRecord(
    id: 'r1',
    goal: goal,
    status: status,
    startedAt: DateTime(2026, 3, 1, 9, 5),
    endedAt: DateTime(2026, 3, 1, 9, 6, 20),
    steps: 4,
    maxSteps: 15,
    safeMode: true,
    targetUrl: targetUrl,
    errorMessage: errorMessage,
    logs: logs,
    sensitiveActions: sensitive,
  );
}

void main() {
  group('asking again from the history', () {
    tearDown(GoalHandoff.clear);

    test('a goal waits until the browser takes it, then it is gone', () {
      GoalHandoff.send(goal: '整理要点', url: 'https://example.com/news');

      final request = GoalHandoff.take();
      expect(request?.goal, '整理要点');
      expect(request?.url, 'https://example.com/news');
      expect(GoalHandoff.take(), isNull,
          reason: 'a goal is asked once; a second sheet would be a surprise');
    });

    test('whitespace-only goals and urls are dropped', () {
      GoalHandoff.send(goal: '   ', url: 'https://example.com');
      expect(GoalHandoff.take(), isNull);

      GoalHandoff.send(goal: '做点什么', url: '  ');
      expect(GoalHandoff.take()?.url, isNull,
          reason: 'an empty url must not navigate the tab to nothing');
    });

    test('a second send replaces the first', () {
      GoalHandoff.send(goal: '第一件');
      GoalHandoff.send(goal: '第二件');
      expect(GoalHandoff.take()?.goal, '第二件',
          reason: 'tapping two rows meant the second one');
    });
  });

  group('a record as markdown', () {
    test('carries what the user came for', () {
      final markdown = taskRecordToMarkdown(record(logs: const [
        '步骤 1: 读取页面',
        '完成：三条要点已整理',
      ]));

      expect(markdown, contains('# 把这三条新闻的要点整理出来'));
      expect(markdown, contains('已完成'));
      expect(markdown, contains('2026-03-01 09:05'));
      expect(markdown.contains('2 分'), isFalse, reason: 'it took 1m20s');
      expect(markdown, contains('1 分 20 秒'));
      expect(markdown, contains('4 / 15'));
      expect(markdown, contains('https://example.com/news'));
      expect(markdown, contains('完成：三条要点已整理'));
      expect(markdown, startsWith('# '));
    });

    test('an internal page is not written out as a url', () {
      final markdown = taskRecordToMarkdown(
        record(targetUrl: 'operon://newtab'),
      );
      expect(markdown.contains('operon://'), isFalse);
    });

    test('errors and sensitive steps get their own sections', () {
      final markdown = taskRecordToMarkdown(record(
        status: 'error',
        errorMessage: '模型服务返回 401：invalid api key',
        sensitive: const ['发布回复'],
      ));
      expect(markdown, contains('执行异常'));
      expect(markdown, contains('## 敏感操作'));
      expect(markdown, contains('- 发布回复'));
      expect(markdown, contains('## 错误'));
      expect(markdown, contains('invalid api key'));
    });

    test('an empty record still produces something readable', () {
      final markdown = taskRecordToMarkdown(record(
        goal: '',
        logs: const [],
        targetUrl: null,
      ));
      expect(markdown, contains('# 未命名任务'));
      expect(markdown.contains('## 执行记录'), isFalse);
    });
  });
}
