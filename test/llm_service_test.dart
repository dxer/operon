import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:operon/models/agent_action.dart';
import 'package:operon/models/llm_config.dart';
import 'package:operon/services/llm_service.dart';

const _config = LlmConfig(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'test-key',
  model: 'test-model',
);

http.Response _ok(String content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          }
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _completion(String content, {String finishReason = 'stop'}) =>
    http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': content},
            'finish_reason': finishReason,
          }
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Simulates a provider that never answers, so the abort trigger is the only
/// thing that ends the request — the same path a real timeout takes.
class _HangingClient extends http.BaseClient {
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final abortable = request as http.AbortableRequest;
    await abortable.abortTrigger;
    throw http.RequestAbortedException(request.url);
  }
}

void main() {
  LlmService service(MockClient client) => LlmService(
        client: client,
        retryBackoff: Duration.zero,
      );

  test('a transient 500 is retried and the next success is used', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) return http.Response('upstream error', 500);
      return _ok('done');
    });

    final text = await service(client).chatCompletion(
      config: _config,
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
    );

    expect(text, 'done');
    expect(calls, 2);
  });

  test('persistent 5xx stops after three attempts', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('still down', 503);
    });

    await expectLater(
      service(client).chatCompletion(
        config: _config,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      ),
      throwsA(isA<Exception>()),
    );
    expect(calls, 3);
  });

  test('a 400 is a request bug and is not retried', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{"error":{"message":"bad request"}}', 400);
    });

    await expectLater(
      service(client).chatCompletion(
        config: _config,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      ),
      throwsA(isA<Exception>()),
    );
    expect(calls, 1);
  });

  test('connection resets are retried', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls < 3) throw http.ClientException('connection reset');
      return _ok('recovered');
    });

    final text = await service(client).chatCompletion(
      config: _config,
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
    );

    expect(text, 'recovered');
    expect(calls, 3);
  });

  test('a timeout is retried once and then reported clearly', () async {
    final client = _HangingClient();
    final llm = LlmService(
      client: client,
      requestTimeout: const Duration(milliseconds: 20),
      retryBackoff: Duration.zero,
    );

    await expectLater(
      llm.chatCompletion(
        config: _config,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      ),
      throwsA(
        isA<LlmRequestException>().having(
          (e) => e.toString(),
          'message',
          contains('超时'),
        ),
      ),
    );
    // Initial attempt plus exactly one timeout retry.
    expect(client.calls, 2);
  });

  group('action JSON repair', () {
    const validAction =
        '{"thought":"点击按钮","action":"click","params":{"element_id":2}}';

    test('a non-JSON reply is repaired once instead of failing the task',
        () async {
      var calls = 0;
      String? repairPrompt;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) return _completion('我认为应该先点击按钮。');
        repairPrompt = request.body;
        return _completion(validAction);
      });

      final action = await service(client).getNextAction(
        config: _config,
        messages: const [
          {'role': 'user', 'content': '点按钮'},
        ],
      );

      expect(action.action, ActionType.click);
      expect(calls, 2);
      expect(repairPrompt, contains('不是合法的动作 JSON'));
    });

    test('a truncated reply is diagnosed as truncation', () async {
      var calls = 0;
      String? repairPrompt;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return _completion(
            '{"thought":"点击按钮","action":"click","params":{"element_id"',
            finishReason: 'length',
          );
        }
        repairPrompt = request.body;
        return _completion(validAction);
      });

      final action = await service(client).getNextAction(
        config: _config,
        messages: const [
          {'role': 'user', 'content': '点按钮'},
        ],
      );

      expect(action.action, ActionType.click);
      expect(repairPrompt, contains('截断'));
    });

    test('an unsupported action type asks for a valid one', () async {
      var calls = 0;
      String? repairPrompt;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return _completion('{"thought":"传送","action":"teleport"}');
        }
        repairPrompt = request.body;
        return _completion(validAction);
      });

      final action = await service(client).getNextAction(
        config: _config,
        messages: const [
          {'role': 'user', 'content': '点按钮'},
        ],
      );

      expect(action.action, ActionType.click);
      expect(repairPrompt, contains('不受支持'));
    });
  });

  test('a provider rejecting response_format is retried and remembered',
      () async {
    var calls = 0;
    final bodies = <String>[];
    final client = MockClient((request) async {
      calls++;
      bodies.add(request.body);
      if (request.body.contains('response_format')) {
        return http.Response('{"error":{"message":"unsupported"}}', 422);
      }
      return _completion(
        '{"thought":"点击","action":"click","params":{"element_id":1}}',
      );
    });

    const config = LlmConfig(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'test-key',
      model: 'no-json-mode-model',
    );
    final llm = service(client);
    const messages = [
      {'role': 'user', 'content': '点按钮'},
    ];

    await llm.getNextAction(config: config, messages: messages);
    await llm.getNextAction(config: config, messages: messages);

    expect(calls, 3); // 422 + fallback, then a single call without it.
    expect(bodies.first, contains('response_format'));
    expect(bodies[2], isNot(contains('response_format')));
  });
}
