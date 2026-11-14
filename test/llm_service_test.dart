import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

}
