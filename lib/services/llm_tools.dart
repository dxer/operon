import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/llm_config.dart';
import '../utils/cancellation.dart';
import 'llm_service.dart';

/// One tool-calling reply, as the provider wrote it.
///
/// Deliberately unparsed: the service's job is the HTTP exchange, and the
/// agent's adapter is the only place that needs to know what a `tool_calls`
/// entry looks like.
class LlmToolResponse {
  const LlmToolResponse({
    required this.message,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
    this.effortDropped = false,
  });

  final Map<String, Object?> message;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;

  /// The endpoint rejected `reasoning_effort`, so this reply came back without
  /// it. The run continues, but the user has to know their choice was ignored.
  final bool effortDropped;

  String? get content {
    final raw = message['content'];
    return raw is String ? raw : null;
  }
}

/// A chat completion that offers tools to the model.
///
/// This is the one place the request shape differs from a plain completion:
/// `tools` plus `tool_choice: auto`. Everything else — retries, aborts,
/// endpoint resolution — is the same machinery the rest of the app uses, so a
/// provider quirk only has to be fixed once.
/// Endpoints that answered 400/422 to `reasoning_effort`. Remembered for the
/// rest of the session so the doomed round trip is paid once, not every turn.
final Set<String> _effortUnsupported = <String>{};

/// Test seam for [_effortUnsupported]; without it one test poisons the next.
void forgetUnsupportedEffort() => _effortUnsupported.clear();

extension LlmToolsCall on LlmService {
  Future<LlmToolResponse> chatWithTools({
    required LlmConfig config,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
    double? temperature,
    CancellationToken? cancelToken,
  }) async {
    if (!config.isValid) {
      throw Exception('请先在设置中配置有效的 API Key 与大模型服务地址。');
    }
    if (cancelToken?.isCancelled == true) {
      throw const LlmCancelledException();
    }

    final key = '${config.baseUrl.trim()}|${config.model.trim()}';
    final wantEffort = config.thinking.sendsEffort && !_effortUnsupported.contains(key);

    Map<String, dynamic> bodyFor({required bool withEffort}) => {
          'model': config.model.trim(),
          'messages': messages,
          'tools': tools,
          'tool_choice': 'auto',
          'temperature': temperature ?? config.temperature,
          // 自动 sends nothing: many compatible endpoints reject reasoning_effort,
          // and a working setup must not start failing because of a preference.
          if (withEffort) 'reasoning_effort': config.thinking.effort,
          if (config.maxOutputTokens != null)
            (LlmConfig.usesMaxCompletionTokens(config.model)
                ? 'max_completion_tokens'
                : 'max_tokens'): config.maxOutputTokens,
        };

    http.Response response;
    var effortDropped = false;
    try {
      response = await sendToolTurn(
        config: config,
        body: bodyFor(withEffort: wantEffort),
        cancelToken: cancelToken,
      );
    } on LlmRequestException catch (error) {
      final unusable = error.statusCode == 400 || error.statusCode == 422;
      // Only retry when the server's own words point at the field. A 400 about
      // something else must reach the user as a failure, not be silently
      // re-sent without the thinking level.
      final aboutEffort = error.message.toLowerCase().contains('reasoning');
      if (!wantEffort || !unusable || !aboutEffort) rethrow;
      // Same shape as the response_format fallback: one attempt without the
      // offending field, and never send it to this endpoint again.
      _effortUnsupported.add(key);
      response = await sendToolTurn(
        config: config,
        body: bodyFor(withEffort: false),
        cancelToken: cancelToken,
      );
      effortDropped = true;
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('模型返回了空响应');
    }
    final choice = choices.first;
    if (choice is! Map) throw Exception('模型返回了无法识别的响应');
    final message = choice['message'];
    if (message is! Map) throw Exception('模型返回了空的 message');

    final usage = decoded['usage'];
    return LlmToolResponse(
      message: Map<String, Object?>.from(message),
      finishReason: choice['finish_reason'] as String?,
      promptTokens: usage is Map ? (usage['prompt_tokens'] as num?)?.toInt() : null,
      completionTokens:
          usage is Map ? (usage['completion_tokens'] as num?)?.toInt() : null,
      effortDropped: effortDropped,
    );
  }
}

/// Turns a provider failure into something the user can act on.
///
/// The one case worth naming: a model that cannot call tools. Without this the
/// user sees "400 Bad Request" and has no way to know the fix is another model.
String describeLlmFailure(Object error) {
  final text = '$error';
  final lower = text.toLowerCase();
  if (lower.contains('tool') || lower.contains('function')) {
    if (lower.contains('not support') ||
        lower.contains('unsupported') ||
        lower.contains('invalid') ||
        lower.contains('no endpoints') ||
        lower.contains('does not')) {
      return '当前模型不支持工具调用（tool calling），请在设置里换一个支持 function calling 的模型。'
          '原始信息：$text';
    }
  }
  if (lower.contains('context') && (lower.contains('length') || lower.contains('window'))) {
    return '对话超出了模型的上下文窗口。请把任务拆小，或换一个窗口更大的模型。原始信息：$text';
  }
  if (lower.contains('api key') || lower.contains('401') || lower.contains('unauthorized')) {
    return 'API Key 无效或已过期，请在设置里检查。原始信息：$text';
  }
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return '模型请求超时。请稍后重试，或换一个更快的模型。原始信息：$text';
  }
  return text.replaceFirst('Exception: ', '');
}

/// Whether a model id is likely to accept images.
///
/// A guess, not a capability list: providers expose no reliable flag, and the
/// alternative is a settings toggle nobody knows how to set. The patterns below
/// cover the models people actually use; when the guess is wrong the provider
/// answers with an error the loop reports, which is one wasted call rather than
/// a silently ignored screenshot.
bool modelSupportsVision(String model) {
  final id = model.toLowerCase();
  const markers = [
    'gpt-4o',
    'gpt-4.1',
    'gpt-5',
    'o3',
    'o4',
    'claude-3',
    'claude-4',
    'claude-sonnet',
    'claude-opus',
    'gemini',
    'glm-4v',
    'glm-4.5v',
    'qwen-vl',
    'qwen2-vl',
    'qwen2.5-vl',
    'qvq',
    'internvl',
    'llava',
    'minicpm-v',
    'pixtral',
    'vision',
    '-vl',
    'vl-',
  ];
  return markers.any(id.contains);
}
