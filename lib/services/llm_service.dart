import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, HttpException, SocketException, TlsException;
import 'package:http/http.dart' as http;
import '../models/llm_config.dart';
import '../utils/cancellation.dart';
import 'llm_stream_parser.dart';

/// Thrown when the user stops a task while its model request is in flight.
class LlmCancelledException implements Exception {
  const LlmCancelledException();

  @override
  String toString() => '大模型请求已取消';
}

/// A network-level failure with a message that is already user facing.
///
/// Keeping it separate from a generic `Exception` lets callers rethrow it
/// unchanged instead of wrapping it in "连接大模型服务失败: Exception: ...".
class LlmRequestException implements Exception {
  final String message;

  /// HTTP status, when there was one. Callers need it to tell "this endpoint
  /// does not understand the field" from "this request is wrong".
  final int? statusCode;

  const LlmRequestException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class _Completion {
  final String content;
  final String? finishReason;

  const _Completion(this.content, this.finishReason);

  /// The provider stopped because it hit the token limit, so the JSON is
  /// almost certainly cut in half rather than genuinely malformed.
  bool get truncated => finishReason == 'length';
}

class LlmService {
  final http.Client _client;
  final Duration _requestTimeout;
  final Duration _retryBackoff;

  LlmService({
    http.Client? client,
    Duration? requestTimeout,
    Duration? retryBackoff,
  })  : _client = client ?? http.Client(),
        _requestTimeout = requestTimeout ?? const Duration(minutes: 3),
        _retryBackoff = retryBackoff ?? const Duration(milliseconds: 800);

  /// Transient failures get two extra attempts.
  static const int _maxRetries = 2;

  /// A timeout already waited the full request budget, so it is retried once
  /// at most: two attempts are the ceiling before the user is told it failed.
  static const int _maxTimeoutRetries = 1;

  String get _timeoutLabel {
    final seconds = _requestTimeout.inSeconds;
    return seconds >= 60
        ? '${(seconds / 60).ceil()} 分钟'
        : '$seconds 秒';
  }

  String get _timeoutMessage =>
      '大模型请求超时（$_timeoutLabel），请稍后重试或换一个更快的模型';

  /// Failures that mean "this attempt never reached the model", not "the model
  /// said no".
  ///
  /// A TLS handshake cut in half, a socket reset by a proxy, a phone that moved
  /// from Wi-Fi to cellular — each one is a lost attempt, not an answer. Only
  /// [http.ClientException] used to be understood here, so a
  /// `HandshakeException` escaped on the first try and reached the user as the
  /// platform's own sentence: "Connection terminated during handshake".
  static bool _isTransportFailure(Object error) =>
      error is http.ClientException ||
      error is HandshakeException ||
      error is TlsException ||
      error is SocketException ||
      error is HttpException;

  /// What the user reads once the last attempt has failed.
  String _retryFailureMessage(int retries, Object? lastError) {
    if (lastError != null && _isTransportFailure(lastError)) {
      return '与模型服务的连接没能建立（已重试 $retries 次）。'
          '多半是网络切换、代理或 VPN 抖动，换个网络再试通常就好。原始信息：$lastError';
    }
    return '大模型请求失败（已重试 $retries 次）: $lastError';
  }

  /// Sends a JSON POST with abort support and bounded retries.
  ///
  /// Retries connection resets, 429/5xx responses and timeouts. A 45s budget
  /// was too tight for reasoning models, which legitimately take minutes on a
  /// hard page; the budget is now three minutes and a timeout gets one retry.
  /// The GET counterpart of [_postJson]. Listing models is read-only, so there
  /// is no retry ladder: a failure is reported once, where the user asked.
  Future<http.Response> _getJson({
    required Uri uri,
    required Map<String, String> headers,
  }) async {
    try {
      return await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw Exception('请求模型列表超时，检查网络或 Base URL');
    } catch (error) {
      throw Exception('连接模型服务失败：$error');
    }
  }

  Future<http.Response> _postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    CancellationToken? cancelToken,
    bool retry = true,
  }) async {
    Object? lastError;
    final maxAttempts = retry ? _maxRetries + 1 : 1;
    var timeoutRetries = 0;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (cancelToken?.isCancelled == true) {
        throw const LlmCancelledException();
      }

      final isLastAttempt = attempt >= maxAttempts - 1;
      final abort = Completer<void>();
      void abortNow() {
        if (!abort.isCompleted) abort.complete();
      }

      cancelToken?.whenCancelled.then((_) => abortNow());
      final timer = Timer(_requestTimeout, abortNow);

      try {
        final request = http.AbortableRequest(
          'POST',
          uri,
          abortTrigger: abort.future,
        )
          ..headers.addAll(headers)
          ..body = body;

        final streamed = await _client.send(request);
        final response = await http.Response.fromStream(streamed);

        if (!isLastAttempt && _isRetryableStatus(response.statusCode)) {
          timer.cancel();
          await Future.delayed(_retryDelay(response, attempt));
          continue;
        }
        timer.cancel();
        return response;
      } on http.RequestAbortedException {
        timer.cancel();
        if (cancelToken?.isCancelled == true) {
          throw const LlmCancelledException();
        }
        if (isLastAttempt || timeoutRetries >= _maxTimeoutRetries) {
          throw LlmRequestException(_timeoutMessage);
        }
        timeoutRetries++;
        lastError = 'timeout';
        await Future.delayed(_retryBackoff * (attempt + 1));
        continue;
      } catch (e) {
        timer.cancel();
        if (cancelToken?.isCancelled == true) {
          throw const LlmCancelledException();
        }
        if (e is TimeoutException) {
          if (isLastAttempt || timeoutRetries >= _maxTimeoutRetries) {
            throw LlmRequestException(_timeoutMessage);
          }
          timeoutRetries++;
          lastError = 'timeout';
          await Future.delayed(_retryBackoff * (attempt + 1));
          continue;
        }
        if (_isTransportFailure(e)) {
          lastError = e;
        } else {
          rethrow;
        }
      }

      if (!isLastAttempt) {
        await Future.delayed(_retryBackoff * (attempt + 1));
      }
    }

    throw LlmRequestException(_retryFailureMessage(maxAttempts - 1, lastError));
  }

  bool _isRetryableStatus(int status) =>
      status == 429 ||
      status == 500 ||
      status == 502 ||
      status == 503 ||
      status == 504;

  Duration _retryDelay(http.Response response, int attempt) {
    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    if (retryAfter != null && retryAfter > 0) {
      return Duration(seconds: retryAfter.clamp(1, 5));
    }
    return _retryBackoff * (attempt + 1);
  }

  /// Providers known to reject `response_format`. Re-sending it on every call
  /// burns a round trip and can surface a confusing error.
  static final Set<String> _jsonModeUnsupported = <String>{};

  static String _providerKey(LlmConfig config) =>
      '${config.baseUrl.trim()}|${config.model.trim()}';

  /// Endpoints that answered 400/422 mentioning `reasoning_effort`. Remembered
  /// so the doomed round trip is paid once per endpoint, not every turn.
  static final Set<String> _effortUnsupported = <String>{};

  /// Endpoints that rejected `temperature`.
  static final Set<String> _temperatureUnsupported = <String>{};

  /// Endpoints that rejected `stream_options`.
  static final Set<String> _streamOptionsUnsupported = <String>{};

  static bool effortUnsupported(LlmConfig config) =>
      _effortUnsupported.contains(_providerKey(config));

  static void markEffortUnsupported(LlmConfig config) =>
      _effortUnsupported.add(_providerKey(config));

  static bool temperatureUnsupported(LlmConfig config) =>
      LlmConfig.omitsTemperature(config.model) ||
      _temperatureUnsupported.contains(_providerKey(config));

  static void markTemperatureUnsupported(LlmConfig config) =>
      _temperatureUnsupported.add(_providerKey(config));

  static bool streamOptionsUnsupported(LlmConfig config) =>
      _streamOptionsUnsupported.contains(_providerKey(config));

  static void markStreamOptionsUnsupported(LlmConfig config) =>
      _streamOptionsUnsupported.add(_providerKey(config));

  /// Test seam: without it one test poisons the next.
  static void forgetUnsupportedEffort() {
    _effortUnsupported.clear();
    _temperatureUnsupported.clear();
    _streamOptionsUnsupported.clear();
  }

  static Map<String, String> authHeaders(LlmConfig config) => {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer ${config.apiKey.trim()}',
      };

  static String extractErrorDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        final message = error is Map ? error['message'] : null;
        if (message != null) return '$message';
      }
    } catch (_) {
      // Keep the raw body: it is more informative than nothing.
    }
    return body;
  }

  static Map<String, dynamic> buildRequestBody({
    required LlmConfig config,
    required List<Map<String, Object?>> messages,
    double? temperature,
    required bool withEffort,
    required bool withTemperature,
    List<Map<String, Object?>>? tools,
    bool withJsonMode = false,
    bool stream = false,
    bool includeUsage = false,
  }) {
    return {
      'model': config.model.trim(),
      'messages': messages,
      if (tools != null) 'tools': tools,
      if (tools != null) 'tool_choice': 'auto',
      if (withTemperature) 'temperature': temperature ?? config.temperature,
      if (withEffort) 'reasoning_effort': config.thinking.effort,
      if (config.maxOutputTokens != null)
        (LlmConfig.usesMaxCompletionTokens(config.model)
            ? 'max_completion_tokens'
            : 'max_tokens'): config.maxOutputTokens,
      if (withJsonMode) 'response_format': {'type': 'json_object'},
      if (stream) 'stream': true,
      if (stream && includeUsage) 'stream_options': {'include_usage': true},
    };
  }

  /// The list of models the endpoint offers, for the picker in settings.
  ///
  /// Every OpenAI-compatible server answers `GET /models`; the shapes differ
  /// only in how the ids are nested, so both the `data[].id` form and a bare
  /// array are accepted. A failure here is not fatal: the user can still type a
  /// model name by hand.
  Future<List<String>> fetchModels(LlmConfig config) async {
    if (config.baseUrl.trim().isEmpty) {
      throw Exception('请先填写 Base URL');
    }
    final response = await _getJson(
      uri: Uri.parse(_modelsEndpointOf(config)),
      headers: authHeaders(config),
    );
    if (response.statusCode != 200) {
      throw LlmRequestException(
        '获取模型列表失败（${response.statusCode}）：${extractErrorDetail(response.body)}',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw Exception('模型列表不是 JSON，确认 Base URL 指向一个 OpenAI 兼容端点');
    }
    final raw = decoded is Map ? decoded['data'] : decoded;
    if (raw is! List) throw Exception('模型列表格式无法识别');

    // A set, because some routers repeat an id and two identical chips is a bug
    // the user has to reason about.
    final ids = <String>{};
    for (final entry in raw) {
      final id = entry is Map ? entry['id'] ?? entry['name'] : entry;
      if (id is String && id.trim().isNotEmpty) ids.add(id.trim());
    }
    final sorted = ids.toList()..sort();
    return sorted;
  }

  static String _modelsEndpointOf(LlmConfig config) {
    final base = config.baseUrl.trim();
    const suffix = '/chat/completions';
    if (base.endsWith(suffix)) {
      return '${base.substring(0, base.length - suffix.length)}/models';
    }
    if (base.endsWith('/models')) return base;
    if (base.endsWith('/')) return '${base}models';
    return '$base/models';
  }

  static String _endpointOf(LlmConfig config) {
    final base = config.baseUrl.trim();
    if (base.endsWith('/chat/completions')) return base;
    if (base.endsWith('/')) return '${base}chat/completions';
    return '$base/chat/completions';
  }

  /// General chat completion helper returning raw String content.
  /// When [onDelta] is supplied, streams tokens via SSE when supported.
  Future<String> chatCompletion({
    required LlmConfig config,
    required List<Map<String, String>> messages,
    double? temperature,
    bool jsonMode = false,
    CancellationToken? cancelToken,
    void Function(String delta)? onDelta,
  }) async {
    if (onDelta != null) {
      if (!config.isValid) {
        throw Exception('请先在设置中配置有效的 API Key 与大模型服务地址。');
      }
      if (cancelToken?.isCancelled == true) {
        throw const LlmCancelledException();
      }
      var wantEffort = config.thinking.sendsEffort && !effortUnsupported(config);
      var wantTemperature = !temperatureUnsupported(config);
      var wantJsonMode =
          jsonMode && !_jsonModeUnsupported.contains(_providerKey(config));
      while (true) {
        final body = buildRequestBody(
          config: config,
          messages: messages,
          temperature: temperature,
          withEffort: wantEffort,
          withTemperature: wantTemperature,
          withJsonMode: wantJsonMode,
          stream: true,
        );
        try {
          final result = await sendStreamedTurn(
            config: config,
            body: body,
            cancelToken: cancelToken,
            onTextDelta: onDelta,
          );
          final content = result.message['content']?.toString() ?? '';
          if (content.isNotEmpty) return content;
          throw Exception('模型返回了空响应');
        } on LlmRequestException catch (error) {
          final bad = error.statusCode == 400 || error.statusCode == 422;
          if (!bad) rethrow;
          final lower = error.message.toLowerCase();
          if (wantEffort && lower.contains('reasoning')) {
            markEffortUnsupported(config);
            wantEffort = false;
            continue;
          }
          if (wantTemperature && lower.contains('temperature')) {
            markTemperatureUnsupported(config);
            wantTemperature = false;
            continue;
          }
          if (wantJsonMode) {
            _jsonModeUnsupported.add(_providerKey(config));
            wantJsonMode = false;
            continue;
          }
          rethrow;
        }
      }
    }

    final completion = await _complete(
      config: config,
      messages: messages,
      temperature: temperature,
      jsonMode: jsonMode,
      cancelToken: cancelToken,
    );
    return completion.content;
  }

  /// Sends one already-built request body with SSE streaming, falling back to
  /// regular JSON parsing if the server responds without `text/event-stream`.
  Future<LlmStreamResult> sendStreamedTurn({
    required LlmConfig config,
    required Map<String, dynamic> body,
    CancellationToken? cancelToken,
    void Function(String delta)? onTextDelta,
    void Function(String delta)? onReasoningDelta,
  }) async {
    final uri = Uri.parse(_endpointOf(config));
    final headers = {
      ...authHeaders(config),
      'Accept': 'text/event-stream',
    };
    final payload = jsonEncode(body);
    Object? lastError;
    const maxAttempts = _maxRetries + 1;
    var timeoutRetries = 0;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (cancelToken?.isCancelled == true) {
        throw const LlmCancelledException();
      }
      final isLastAttempt = attempt >= maxAttempts - 1;
      // Set once any text reached the screen. A retry after that would show the
      // answer twice, so this attempt is the only one that may fail this way.
      var streamedText = false;
      final abort = Completer<void>();
      void abortNow() {
        if (!abort.isCompleted) abort.complete();
      }

      cancelToken?.whenCancelled.then((_) => abortNow());
      final timer = Timer(_requestTimeout, abortNow);

      try {
        final request = http.AbortableRequest(
          'POST',
          uri,
          abortTrigger: abort.future,
        )
          ..headers.addAll(headers)
          ..body = payload;

        final streamed = await _client.send(request);
        if (streamed.statusCode != 200) {
          final errResp = await http.Response.fromStream(streamed);
          timer.cancel();
          if (!isLastAttempt && _isRetryableStatus(errResp.statusCode)) {
            await Future.delayed(_retryDelay(errResp, attempt));
            continue;
          }
          throw LlmRequestException(
            '模型服务返回 ${errResp.statusCode}：${extractErrorDetail(errResp.body)}',
            statusCode: errResp.statusCode,
          );
        }

        final contentType =
            (streamed.headers['content-type'] ?? '').toLowerCase();
        if (contentType.contains('text/event-stream')) {
          final acc = OpenAiSseAccumulator(
            onTextDelta: (delta) {
              streamedText = true;
              onTextDelta?.call(delta);
            },
            onReasoningDelta: onReasoningDelta,
          );
          final result = await acc.consume(streamed.stream);
          timer.cancel();
          return result;
        }

        // Some OpenAI-compatible proxies ignore `stream: true` and reply JSON.
        final full = await http.Response.fromStream(streamed);
        timer.cancel();
        final decoded = jsonDecode(utf8.decode(full.bodyBytes));
        final choices = decoded is Map ? decoded['choices'] : null;
        if (choices is! List || choices.isEmpty) {
          throw Exception('模型返回了空响应');
        }
        final first = choices.first;
        if (first is! Map || first['message'] is! Map) {
          throw Exception('模型返回了无法识别的响应');
        }
        final message = Map<String, Object?>.from(first['message'] as Map);
        final reasoning = message['reasoning_content']?.toString();
        if (reasoning != null && reasoning.isNotEmpty) {
          onReasoningDelta?.call(reasoning);
        }
        final content = message['content'];
        if (content is String && content.isNotEmpty) {
          onTextDelta?.call(content);
        }
        final usage = decoded is Map ? decoded['usage'] : null;
        return LlmStreamResult(
          message: message,
          finishReason: first['finish_reason'] as String?,
          promptTokens:
              usage is Map ? (usage['prompt_tokens'] as num?)?.toInt() : null,
          completionTokens:
              usage is Map ? (usage['completion_tokens'] as num?)?.toInt() : null,
        );
      } on LlmCancelledException {
        timer.cancel();
        rethrow;
      } on LlmRequestException {
        timer.cancel();
        rethrow;
      } on http.RequestAbortedException {
        timer.cancel();
        if (cancelToken?.isCancelled == true) {
          throw const LlmCancelledException();
        }
        if (isLastAttempt || timeoutRetries >= _maxTimeoutRetries) {
          throw LlmRequestException(_timeoutMessage);
        }
        timeoutRetries++;
        lastError = 'timeout';
        await Future.delayed(_retryBackoff * (attempt + 1));
      } catch (e) {
        timer.cancel();
        if (cancelToken?.isCancelled == true) {
          throw const LlmCancelledException();
        }
        if (e is TimeoutException) {
          if (isLastAttempt || timeoutRetries >= _maxTimeoutRetries) {
            throw LlmRequestException(_timeoutMessage);
          }
          timeoutRetries++;
          lastError = 'timeout';
          await Future.delayed(_retryBackoff * (attempt + 1));
          continue;
        }
        if (_isTransportFailure(e)) {
          if (streamedText) {
            throw LlmRequestException(
              '与模型服务的连接中途断开，这次回答不完整。原始信息：$e',
            );
          }
          lastError = e;
          if (!isLastAttempt) {
            await Future.delayed(_retryBackoff * (attempt + 1));
          }
        } else {
          rethrow;
        }
      }
    }

    throw LlmRequestException(_retryFailureMessage(maxAttempts - 1, lastError));
  }

  /// Sends one already-built request body and returns the raw 200 response.
  ///
  /// The agent builds its own body (tool calling changes the shape of a
  /// request), but retries, aborts and endpoint resolution must stay in one
  /// place, so it goes through the same machinery as everything else.
  Future<http.Response> sendToolTurn({
    required LlmConfig config,
    required Map<String, dynamic> body,
    CancellationToken? cancelToken,
  }) async {
    final uri = Uri.parse(_endpointOf(config));
    final response = await _postJson(
      uri: uri,
      headers: authHeaders(config),
      body: jsonEncode(body),
      cancelToken: cancelToken,
    );
    if (response.statusCode == 200) return response;

    throw LlmRequestException(
      '模型服务返回 ${response.statusCode}：${extractErrorDetail(response.body)}',
      statusCode: response.statusCode,
    );
  }

  /// One chat completion, including `response_format` negotiation.
  Future<_Completion> _complete({
    required LlmConfig config,
    required List<Map<String, String>> messages,
    double? temperature,
    bool jsonMode = false,
    CancellationToken? cancelToken,
  }) async {
    if (!config.isValid) {
      throw Exception('请先在设置中配置有效的 API Key 与大模型服务地址。');
    }
    if (cancelToken?.isCancelled == true) {
      throw const LlmCancelledException();
    }

    final uri = Uri.parse(_endpointOf(config));
    final headers = authHeaders(config);
    final key = _providerKey(config);
    final wantJsonMode = jsonMode && !_jsonModeUnsupported.contains(key);

    final wantEffort = config.thinking.sendsEffort && !effortUnsupported(config);
    final wantTemperature = !temperatureUnsupported(config);

    Map<String, dynamic> bodyFor(
      bool withJsonMode, {
      bool? withEffort,
      bool? withTemperature,
    }) =>
        buildRequestBody(
          config: config,
          messages: messages,
          temperature: temperature,
          withEffort: withEffort ?? wantEffort,
          withTemperature: withTemperature ?? wantTemperature,
          withJsonMode: withJsonMode,
        );

    http.Response response;
    try {
      response = await _postJson(
        uri: uri,
        headers: headers,
        body: jsonEncode(bodyFor(wantJsonMode)),
        cancelToken: cancelToken,
      );
    } on LlmCancelledException {
      rethrow;
    } on LlmRequestException {
      rethrow;
    } catch (e) {
      throw Exception('连接大模型服务失败: $e');
    }

    // The same refusal the tool path handles: a model that does not accept
    // reasoning_effort answers 400, and the summary should not die for it.
    if (wantEffort &&
        (response.statusCode == 400 || response.statusCode == 422) &&
        response.body.toLowerCase().contains('reasoning')) {
      try {
        final fallback = await _postJson(
          uri: uri,
          headers: headers,
          body: jsonEncode(bodyFor(wantJsonMode, withEffort: false)),
          cancelToken: cancelToken,
          retry: false,
        );
        if (fallback.statusCode == 200) {
          markEffortUnsupported(config);
          response = fallback;
        }
      } on LlmCancelledException {
        rethrow;
      } catch (_) {
        // Keep the original error: it explains more.
      }
    }

    // Some OpenAI-compatible providers reject response_format with 400 or 422,
    // and the message does not always mention it. Retry once without it and
    // remember the model so later calls skip the doomed first round trip.
    if (wantJsonMode &&
        (response.statusCode == 400 || response.statusCode == 422)) {
      try {
        final fallback = await _postJson(
          uri: uri,
          headers: headers,
          body: jsonEncode(bodyFor(false)),
          cancelToken: cancelToken,
          retry: false,
        );
        if (fallback.statusCode == 200) {
          _jsonModeUnsupported.add(key);
          response = fallback;
        }
      } on LlmCancelledException {
        rethrow;
      } on LlmRequestException {
        rethrow;
      } catch (_) {
        // Keep the original error: it is the more informative one.
      }
    }

    if (response.statusCode != 200) {
      throw Exception(
        '模型服务响应错误 (${response.statusCode}): ${extractErrorDetail(response.body)}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('模型返回了空响应');
    }

    final choice = choices[0];
    return _Completion(
      choice['message']?['content'] as String? ?? '',
      choice['finish_reason'] as String?,
    );
  }

  /// Mobile One-Click Summarizer
  Future<String> summarizeWebPage({
    required LlmConfig config,
    required String title,
    required String url,
    required String content,
    void Function(String delta)? onDelta,
  }) async {
    const systemPrompt = '''
你是一个专业的高效信息提炼大师。你的目标是帮助移动端用户在 30 秒内快速抓住网页精髓。
请根据用户提供的网页标题和正文，输出一份清晰、高价值、排版优美的 Markdown 格式速读简报。

### 输出结构规范：
### 核心结论
- (使用 1~3 条核心要点高度提炼文章核心思想)

### 关键要点与事实清单
- (提炼 3~5 条重要细节、数据支撑或逻辑脉络)

### 核心启示与建议
- (针对读者提炼 1~2 点实际行动建议或最有价值的洞察)
''';

    final userMessage = '''
【网页标题】: $title
【网页链接】: $url
【正文内容】:
$content
''';

    return await chatCompletion(
      config: config,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userMessage},
      ],
      temperature: 0.3,
      onDelta: onDelta,
    );
  }

  /// Mobile Inline Selection Tooltip Query (Translate / Explain / Reply)
  Future<String> querySelection({
    required LlmConfig config,
    required String selectedText,
    required String actionType,
  }) async {
    String systemInstruction = '';
    switch (actionType) {
      case 'translate':
        systemInstruction =
            '你是一个高级翻译官。请将用户选中的文本翻译为自然、优美、地道的中文（若是中文则翻译为英文）。仅输出最终翻译结果，不要任何多余寒暄。';
        break;
      case 'explain':
        systemInstruction =
            '你是一个百科全书顾问。请用最通俗易懂的大白话，解释用户选中的词汇、概念或技术术语，字数在 120 字以内。';
        break;
      case 'reply':
        systemInstruction =
            '你是一个高情商的社交网络达人。请针对用户选中的这句推文/发言，写一条幽默、有见地或引人共鸣的简短社交媒体回复（50 字以内）。';
        break;
      default:
        systemInstruction = '请简要分析并回应以下内容：';
    }

    return await chatCompletion(
      config: config,
      messages: [
        {'role': 'system', 'content': systemInstruction},
        {'role': 'user', 'content': selectedText},
      ],
      temperature: 0.4,
    );
  }

  void dispose() {
    _client.close();
  }
}
