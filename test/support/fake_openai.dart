import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:operon/models/llm_config.dart';

/// One reply a scripted model will give, in the shape an OpenAI-compatible
/// endpoint returns it.
class FakeTurn {
  const FakeTurn({this.content, this.calls = const [], this.finishReason});

  final String? content;

  /// `(name, arguments)` pairs, arguments as the raw JSON string a model writes.
  final List<({String name, String arguments, String? id})> calls;
  final String? finishReason;

  Map<String, Object?> toMessage() => {
        'role': 'assistant',
        'content': content,
        if (calls.isNotEmpty)
          'tool_calls': [
            for (var i = 0; i < calls.length; i++)
              {
                'id': calls[i].id ?? 'call_${i + 1}',
                'type': 'function',
                'function': {
                  'name': calls[i].name,
                  'arguments': calls[i].arguments,
                },
              },
          ],
      };
}

FakeTurn say(String text) => FakeTurn(content: text);

FakeTurn call(String name, [Map<String, Object?> args = const {}, String? id]) => FakeTurn(
      calls: [
        (
          name: name,
          arguments: jsonEncode(args),
          id: id,
        ),
      ],
    );

FakeTurn calls(List<({String name, Map<String, Object?> args})> list) => FakeTurn(
      calls: [
        for (var i = 0; i < list.length; i++)
          (name: list[i].name, arguments: jsonEncode(list[i].args), id: 'call_${i + 1}'),
      ],
    );

/// A stand-in for any OpenAI-compatible endpoint, good enough to drive the whole
/// agent: the HTTP request the app really sends, the JSON it expects back, and a
/// record of every message it was given.
///
/// The point is not to test HTTP. It is that the run — prompt, tool loop,
/// guards, receipts, the panel's state — is exercised through the same code path
/// a real model would take, with the model itself scripted.
class FakeOpenAi {
  FakeOpenAi._(this._server, this.script);

  final HttpServer _server;
  final List<FakeTurn> script;

  /// Every request body the app sent, in order.
  final List<Map<String, Object?>> requests = [];

  /// Headers worth asserting on, such as the bearer token.
  final List<String> authHeaders = [];

  /// Answer 400 instead of a completion, to test the failure path.
  String? failWith;

  /// What `GET /models` offers. Empty means the endpoint has no list.
  List<String> modelList = const ['fake-model', 'fake-model-mini', 'o3-mini'];

  /// Answer `/models` with an error status, to test the picker's failure path.
  int? modelsStatus;

  /// Reject `reasoning_effort` with a 400, the way several compatible endpoints
  /// do. The rejection does not consume a scripted turn.
  bool rejectReasoningEffort = false;

  int _index = 0;

  static Future<FakeOpenAi> start(List<FakeTurn> script) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeOpenAi._(server, script);
    server.listen(fake._serve);
    return fake;
  }

  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  LlmConfig get config => LlmConfig(
        baseUrl: baseUrl,
        apiKey: 'sk-test-token',
        model: 'fake-model',
        temperature: 0,
      );

  /// The messages of one request, as the model saw them.
  List<Map<String, Object?>> messagesOf(int request) =>
      (requests[request]['messages'] as List).cast<Map<String, Object?>>();

  /// Every message of every request, flattened: for "did the model ever see X?".
  List<Map<String, Object?>> get allMessages => [
        for (var i = 0; i < requests.length; i++) ...messagesOf(i),
      ];

  Future<void> close() => _server.close(force: true);

  Future<void> _serve(HttpRequest request) async {
    if (request.method == 'GET' && request.uri.path.endsWith('/models')) {
      authHeaders.add(request.headers.value('authorization') ?? '');
      final status = modelsStatus;
      if (status != null) {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {'message': 'invalid api key'},
        }));
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'object': 'list',
        'data': [
          for (final id in modelList) {'id': id, 'object': 'model', 'owned_by': 'fake'},
        ],
      }));
      await request.response.close();
      return;
    }
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }
    authHeaders.add(request.headers.value('authorization') ?? '');
    final raw = await utf8.decodeStream(request);
    Map<String, Object?> body = const {};
    try {
      body = (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      // Recorded as empty: a test that cares will assert on requests.
    }
    requests.add(body);

    if (rejectReasoningEffort && body.containsKey('reasoning_effort')) {
      request.response.statusCode = 400;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': {'message': 'Unsupported parameter: reasoning_effort'},
      }));
      await request.response.close();
      return;
    }

    final failure = failWith;
    if (failure != null) {
      request.response.statusCode = 400;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': {'message': failure},
      }));
      await request.response.close();
      return;
    }

    final turn = _index < script.length
        ? script[_index++]
        : say('（脚本用完了）');
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'id': 'chatcmpl-fake',
      'object': 'chat.completion',
      'model': body['model'] ?? 'fake-model',
      'choices': [
        {
          'index': 0,
          'message': turn.toMessage(),
          'finish_reason':
              turn.finishReason ?? (turn.calls.isEmpty ? 'stop' : 'tool_calls'),
        },
      ],
      'usage': {'prompt_tokens': 100, 'completion_tokens': 20, 'total_tokens': 120},
    }));
    await request.response.close();
  }
}
