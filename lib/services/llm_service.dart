import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/agent_action.dart';
import '../models/llm_config.dart';
import '../utils/cancellation.dart';
import '../utils/json_parser.dart';

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

  const LlmRequestException(this.message);

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

  static String _endpointOf(LlmConfig config) {
    final base = config.baseUrl.trim();
    if (base.endsWith('/chat/completions')) return base;
    if (base.endsWith('/')) return '${base}chat/completions';
    return '$base/chat/completions';
  }

  static String _clip(String text, [int max = 600]) =>
      text.length > max ? '${text.substring(0, max)}…' : text;

  /// Sends the prompt to the configured LLM and returns the parsed AgentAction.
  ///
  /// A single malformed reply used to end the whole task, throwing away every
  /// step already taken. It now gets one repair round with the bad output and
  /// a format reminder, which is much cheaper than restarting the run.
  Future<AgentAction> getNextAction({
    required LlmConfig config,
    required List<Map<String, String>> messages,
    CancellationToken? cancelToken,
  }) async {
    final first = await _complete(
      config: config,
      messages: messages,
      jsonMode: true,
      cancelToken: cancelToken,
    );
    final parsed = _parseAction(first.content);
    if (parsed != null && parsed.action != ActionType.unknown) return parsed;

    final hint = first.truncated
        ? '你上一条回复因为过长被截断。请只输出一个短小的 JSON 动作，不要任何解释。'
        : parsed != null
            ? '动作类型 "${_clip(first.content, 120)}" 不受支持。可用动作：'
                'click、type、press_key、select_option、hover、scroll、navigate、'
                'go_back、wait、extract_data、finish。请只输出一个合法 JSON。'
            : '你上一条回复不是合法的动作 JSON：\n${_clip(first.content)}\n'
                '请只输出一个 JSON 对象，不要 Markdown，不要解释。';

    final repaired = await _complete(
      config: config,
      messages: [
        ...messages,
        {'role': 'assistant', 'content': _clip(first.content)},
        {'role': 'user', 'content': hint},
      ],
      // Format compliance matters more than variety here.
      temperature: 0,
      jsonMode: true,
      cancelToken: cancelToken,
    );

    final action = _parseAction(repaired.content);
    if (action != null && action.action != ActionType.unknown) return action;

    throw Exception(
      repaired.truncated
          ? '模型输出连续被截断，无法得到完整动作。请换一个上下文更长的模型，或把目标拆小。'
          : '未能从模型回复中解析出合法 Action JSON: ${_clip(repaired.content)}',
    );
  }

  AgentAction? _parseAction(String content) {
    final json = JsonParser.extractJson(content);
    return json == null ? null : AgentAction.fromJson(json);
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
