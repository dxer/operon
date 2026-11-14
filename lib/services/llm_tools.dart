import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/llm_config.dart';
import '../models/model_profile.dart';
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
/// Test seam kept at the same name the tests use; the memory itself lives with
/// the rest of the provider quirks in [LlmService].
void forgetUnsupportedEffort() => LlmService.forgetUnsupportedEffort();

extension LlmToolsCall on LlmService {
  Future<LlmToolResponse> chatWithTools({
    required LlmConfig config,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
    double? temperature,
    CancellationToken? cancelToken,
    ModelProfile profile = const ModelProfile.fallback(),
  }) async {
    if (!config.isValid) {
      throw Exception('请先在设置中配置有效的 API Key 与大模型服务地址。');
    }
    if (cancelToken?.isCancelled == true) {
      throw const LlmCancelledException();
    }

    // Three reasons not to send it: the user picked 自动, this model is marked
    // as not accepting the field, or an earlier turn already proved it doesn't.
    final wantEffort = config.thinking.sendsEffort &&
        profile.reasoningAllowed &&
        !LlmService.effortUnsupported(config);

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
      LlmService.markEffortUnsupported(config);
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

/// Kept as a thin alias so existing callers and tests keep one name.
bool modelSupportsVision(String model) => ModelProfile.guessVision(model);
