import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/llm_config.dart';
import '../utils/cancellation.dart';

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
      return await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
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
        if (e is http.ClientException) {
          lastError = e;
        } else {
          rethrow;
        }
      }

      if (!isLastAttempt) {
        await Future.delayed(_retryBackoff * (attempt + 1));
      }
    }

    throw LlmRequestException('大模型请求失败（已重试 ${maxAttempts - 1} 次）: $lastError');
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
      headers: {
        'Authorization': 'Bearer ${config.apiKey.trim()}',
        'Content-Type': 'application/json; charset=utf-8',
      },
    );
    if (response.statusCode != 200) {
      var detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] is Map) {
          final message = (decoded['error'] as Map)['message'];
          if (message != null) detail = '$message';
        }
      } catch (_) {
        // The raw body is more use than nothing.
      }
      throw LlmRequestException('获取模型列表失败（${response.statusCode}）：$detail');
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

  /// General chat completion helper returning raw String content
  Future<String> chatCompletion({
    required LlmConfig config,
    required List<Map<String, String>> messages,
    double? temperature,
    bool jsonMode = false,
    CancellationToken? cancelToken,
  }) async {
    final completion = await _complete(
      config: config,
      messages: messages,
      temperature: temperature,
      jsonMode: jsonMode,
      cancelToken: cancelToken,
    );
    return completion.content;
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
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer ${config.apiKey.trim()}',
    };
    final response = await _postJson(
      uri: uri,
      headers: headers,
      body: jsonEncode(body),
      cancelToken: cancelToken,
    );
    if (response.statusCode == 200) return response;

    var detail = response.body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final error = decoded['error'];
        final message = error is Map ? error['message'] : null;
        if (message != null) detail = '$message';
      }
    } catch (_) {
      // Keep the raw body: it is more informative than nothing.
    }
    throw LlmRequestException(
      '模型服务返回 ${response.statusCode}：$detail',
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
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer ${config.apiKey.trim()}',
    };
    final key = _providerKey(config);
    final wantJsonMode = jsonMode && !_jsonModeUnsupported.contains(key);

    Map<String, dynamic> bodyFor(bool withJsonMode) => {
          'model': config.model.trim(),
          'messages': messages,
          'temperature': temperature ?? config.temperature,
          if (config.thinking.sendsEffort) 'reasoning_effort': config.thinking.effort,
          if (config.maxOutputTokens != null)
            (LlmConfig.usesMaxCompletionTokens(config.model)
                ? 'max_completion_tokens'
                : 'max_tokens'): config.maxOutputTokens,
          if (withJsonMode) 'response_format': {'type': 'json_object'},
        };

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
      var errDetail = response.body;
      try {
        final errJson = jsonDecode(response.body);
        if (errJson['error']?['message'] != null) {
          errDetail = errJson['error']['message'];
        }
      } catch (_) {}
      throw Exception('模型服务响应错误 (${response.statusCode}): $errDetail');
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

  /// AI UserScript Generator
  Future<Map<String, String>> generateUserScript({
    required LlmConfig config,
    required String prompt,
    required String currentUrl,
    required String pageTitle,
    String? domSnippet,
  }) async {
    const systemPrompt = '''
你是一个资深前端开发专家与浏览器油猴脚本（UserScript）编写大师。
用户希望为移动端网页编写一段定制化的自动化/去广告/样式调整 JavaScript 脚本。

请根据用户的需求描述，生成安全、精炼且鲁棒性强的 UserScript 代码。

### 输出格式规范：
你必须直接返回一个合法的 JSON 字符串（严禁包含 markdown 标记如 ```json，不要输出任何多余寒暄）：
{
  "name": "脚本名称（如：知乎去弹窗与自动展开）",
  "description": "脚本作用的一句话简介（如：自动关闭知乎登录拦截遮罩并展开全文）",
  "matchPattern": "最佳域名匹配模式（如：*://*.zhihu.com/* 或 *twitter.com* 或 *）",
  "code": "完整的匿名自执行 JavaScript 脚本。务必使用 (() => { try { ... } catch (e) { console.error('[UserScript]', e); } })(); 包裹；对于动态渲染的内容，使用 MutationObserver 或轮询/延迟处理；绝不引起页面死循环。"
}
''';

    final userMessage = '''
【用户需求】: $prompt
【当前网页标题】: $pageTitle
【当前网页链接】: $currentUrl
${domSnippet != null && domSnippet.isNotEmpty ? '【网页结构参考】:\n$domSnippet' : ''}
''';

    final raw = await chatCompletion(
      config: config,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userMessage},
      ],
      temperature: 0.2,
    );

    try {
      String cleaned = raw.trim();
      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      }
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.substring(3);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
      cleaned = cleaned.trim();
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
      return {
        'name': decoded['name']?.toString() ?? '自定义 AI 脚本',
        'description': decoded['description']?.toString() ?? prompt,
        'matchPattern': decoded['matchPattern']?.toString() ??
            (currentUrl.isNotEmpty
                ? '*${Uri.tryParse(currentUrl)?.host ?? ""}*'
                : '*'),
        'code': decoded['code']?.toString() ?? '// 脚本生成异常',
      };
    } catch (e) {
      // Fallback if model returned plain code or non-JSON
      return {
        'name': '自定义 AI 脚本',
        'description': prompt,
        'matchPattern': currentUrl.isNotEmpty
            ? '*${Uri.tryParse(currentUrl)?.host ?? ""}*'
            : '*',
        'code': raw.startsWith('(')
            ? raw
            : '(() => {\n  try {\n    $raw\n  } catch (e) { console.error(e); }\n})();',
      };
    }
  }

  void dispose() {
    _client.close();
  }
}
