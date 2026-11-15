import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:operon/models/llm_config.dart';
import 'package:operon/services/llm_service.dart';
import 'package:operon/services/llm_stream_parser.dart';
import 'package:operon/services/llm_tools.dart';

void main() {
  const testConfig = LlmConfig(
    baseUrl: 'https://api.example.com/v1',
    apiKey: 'sk-test-123',
    model: 'gpt-4o',
    temperature: 0.2,
  );

  group('OpenAiSseAccumulator', () {
    test('assembles content, reasoning_content, usage and split tool_calls',
        () async {
      final textDeltas = <String>[];
      final reasoningDeltas = <String>[];
      final acc = OpenAiSseAccumulator(
        onTextDelta: textDeltas.add,
        onReasoningDelta: reasoningDeltas.add,
      );

      final ssePayload = [
        'data: {"choices":[{"index":0,"delta":{"reasoning_content":"Think"}}]}\n\n',
        'data: {"choices":[{"index":0,"delta":{"reasoning_content":"ing..."}}]}\n\n',
        'data: {"choices":[{"index":0,"delta":{"content":"Hel"}}]}\n\n',
        'data: {"choices":[{"index":0,"delta":{"content":"lo!"}}]}\n\n',
        'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"act","arguments":"{\\"target\\":"}}]}}]}\n\n',
        'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"r1\\"}"}}]},"finish_reason":"tool_calls"}]}\n\n',
        'data: {"choices":[],"usage":{"prompt_tokens":120,"completion_tokens":34}}\n\n',
        'data: [DONE]\n\n',
      ].join();

      // Split into arbitrary UTF-8 byte chunks to test partial-line buffering.
      final bytes = utf8.encode(ssePayload);
      final chunks = <List<int>>[];
      for (var i = 0; i < bytes.length; i += 17) {
        final end = (i + 17) > bytes.length ? bytes.length : i + 17;
        chunks.add(bytes.sublist(i, end));
      }

      final result = await acc.consume(Stream<List<int>>.fromIterable(chunks));

      expect(textDeltas, ['Hel', 'lo!']);
      expect(reasoningDeltas, ['Think', 'ing...']);
      expect(result.message['content'], 'Hello!');
      expect(result.message['reasoning_content'], 'Thinking...');
      expect(result.finishReason, 'tool_calls');
      expect(result.promptTokens, 120);
      expect(result.completionTokens, 34);
      final toolCalls = result.message['tool_calls'] as List<Object?>;
      expect(toolCalls, hasLength(1));
      final firstCall = toolCalls.first as Map<String, Object?>;
      expect(firstCall['id'], 'call_1');
      final fn = firstCall['function'] as Map<String, Object?>;
      expect(fn['name'], 'act');
      expect(fn['arguments'], '{"target":"r1"}');
    });
  });

  group('LlmService streaming', () {
    setUp(() {
      LlmService.forgetUnsupportedEffort();
    });

    test('chatWithTools streams SSE deltas and falls back when stream_options is rejected',
        () async {
      var attempt = 0;
      final client = MockClient.streaming((request, bodyStream) async {
        attempt++;
        final bodyText = await utf8.decodeStream(bodyStream);
        final bodyJson = jsonDecode(bodyText) as Map<String, dynamic>;
        expect(bodyJson['stream'], true);

        if (attempt == 1) {
          expect(bodyJson.containsKey('stream_options'), true);
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":"unknown field stream_options"}')),
            400,
          );
        }

        expect(bodyJson.containsKey('stream_options'), false);
        final sse = [
          'data: {"choices":[{"index":0,"delta":{"content":"正"}}]}\n\n',
          'data: {"choices":[{"index":0,"delta":{"content":"在点击"},"finish_reason":"stop"}]}\n\n',
          'data: [DONE]\n\n',
        ].join();
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });

      final service = LlmService(client: client);
      final received = <String>[];
      final response = await service.chatWithTools(
        config: testConfig,
        messages: const [
          {'role': 'user', 'content': 'hello'},
        ],
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'ping',
              'description': 'probe',
              'parameters': {'type': 'object', 'properties': {}},
            },
          },
        ],
        onTextDelta: received.add,
      );

      expect(attempt, 2);
      expect(received, ['正', '在点击']);
      expect(response.content, '正在点击');
      expect(response.finishReason, 'stop');
    });

    test('a TLS handshake cut short before any text is retried', () async {
      var calls = 0;
      final client = MockClient.streaming((request, bodyStream) async {
        calls++;
        if (calls == 1) {
          // What the phone actually reports on a flaky network or a proxy that
          // closes the tunnel: the first attempt never reached the model.
          throw const HandshakeException('Connection terminated during handshake');
        }
        final sse = [
          'data: {"choices":[{"index":0,"delta":{"content":"好了"},"finish_reason":"stop"}]}\n\n',
          'data: [DONE]\n\n',
        ].join();
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });

      final service = LlmService(client: client, retryBackoff: Duration.zero);
      final received = <String>[];
      final response = await service.chatWithTools(
        config: testConfig,
        messages: const [
          {'role': 'user', 'content': 'hello'},
        ],
        tools: const [],
        onTextDelta: received.add,
      );

      expect(calls, 2, reason: 'a lost attempt is not the model failing');
      expect(received, ['好了']);
      expect(response.content, '好了');
    });

    test('a connection that dies after text was shown is not retried', () async {
      var calls = 0;
      final client = MockClient.streaming((request, bodyStream) async {
        calls++;
        Stream<List<int>> halfThenBroken() async* {
          yield utf8.encode(
            'data: {"choices":[{"index":0,"delta":{"content":"半句话"}}]}\n\n',
          );
          throw const HandshakeException('Connection terminated during handshake');
        }

        return http.StreamedResponse(
          halfThenBroken(),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });

      final service = LlmService(client: client, retryBackoff: Duration.zero);
      final received = <String>[];

      await expectLater(
        service.chatWithTools(
          config: testConfig,
          messages: const [
            {'role': 'user', 'content': 'hello'},
          ],
          tools: const [],
          onTextDelta: received.add,
        ),
        throwsA(
          isA<LlmRequestException>().having(
            (error) => error.message,
            'message',
            contains('中途断开'),
          ),
        ),
      );

      // Retrying would print the answer a second time, so the first attempt is
      // the only one: the excerpt already on screen says what arrived.
      expect(calls, 1);
      expect(received, ['半句话']);
    });

    test('chatWithTools handles non-stream application/json fallback cleanly',
        () async {
      final client = MockClient.streaming((request, bodyStream) async {
        final jsonReply = jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'Done non-stream',
              },
              'finish_reason': 'stop',
            }
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
        });
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonReply)),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = LlmService(client: client);
      final deltas = <String>[];
      final response = await service.chatWithTools(
        config: testConfig,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        tools: const [],
        onTextDelta: deltas.add,
      );

      expect(response.content, 'Done non-stream');
      expect(response.promptTokens, 10);
      expect(response.completionTokens, 5);
      expect(deltas, ['Done non-stream']);
    });

    test('chatCompletion emits streaming deltas when onDelta is supplied',
        () async {
      final client = MockClient.streaming((request, bodyStream) async {
        final sse = [
          'data: {"choices":[{"index":0,"delta":{"content":"A"}}]}\n\n',
          'data: {"choices":[{"index":0,"delta":{"content":"B"},"finish_reason":"stop"}]}\n\n',
          'data: [DONE]\n\n',
        ].join();
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = LlmService(client: client);
      final chunks = <String>[];
      final text = await service.chatCompletion(
        config: testConfig,
        messages: const [
          {'role': 'user', 'content': 'summarize'},
        ],
        onDelta: chunks.add,
      );

      expect(chunks, ['A', 'B']);
      expect(text, 'AB');
    });
  });

  group('describeLlmFailure', () {
    test('a raw handshake error points at the network, not the model', () {
      final message = describeLlmFailure(
        const HandshakeException('Connection terminated during handshake'),
      );

      expect(message, contains('连接中断'));
      expect(message, contains('没有到达模型'));
      expect(message, contains('HandshakeException'),
          reason: 'the raw text stays, for diagnosis');
    });
  });
}
