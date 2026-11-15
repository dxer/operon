import 'dart:async';
import 'dart:convert';

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

  /// The reply's text, however this endpoint shaped it.
  ///
  /// `content` is a string in the OpenAI spec and a list of parts on some
  /// compatible endpoints. Reading only the string meant those endpoints
  /// looked like a model that answered nothing — the panel then showed an
  /// internal note where the answer belonged.
  String? get content {
    final raw = message['content'];
    if (raw is String) return raw;
    if (raw is List) {
      final buffer = StringBuffer();
      for (final part in raw) {
        if (part is String) {
          buffer.write(part);
        } else if (part is Map) {
          final text = part['text'];
          if (text is String) {
            buffer.write(text);
          } else if (text is Map && text['value'] is String) {
            buffer.write(text['value']);
          }
        }
      }
      final text = buffer.toString();
      return text.isEmpty ? null : text;
    }
    return null;
  }

  /// True when the endpoint sent reasoning but no answer.
  ///
  /// Worth naming: a reasoning model that spends its budget thinking and gets
  /// cut off looks exactly like a model that refused to speak, and the two
  /// need different advice.
  bool get reasoningOnly =>
      (content == null || content!.trim().isEmpty) &&
      message['reasoning_content'] is String &&
      (message['reasoning_content'] as String).trim().isNotEmpty;
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
    void Function(String delta)? onTextDelta,
    void Function(String delta)? onReasoningDelta,
  }) async {
    if (!config.isValid) {
      throw Exception('请先在设置中配置有效的 API Key 与大模型服务地址。');
    }
    if (cancelToken?.isCancelled == true) {
      throw const LlmCancelledException();
    }

    // Agent loops omit `temperature` unless a caller explicitly requests one,
    // letting providers (including thinking/reasoning endpoints) use their
    // own safe default instead of triggering avoidable 400 rejections.
    var sendEffort = config.thinking.sendsEffort &&
        profile.reasoningAllowed &&
        !LlmService.effortUnsupported(config);
    var sendTemperature =
        temperature != null && !LlmService.temperatureUnsupported(config);
    final useStream = onTextDelta != null || onReasoningDelta != null;
    var sendIncludeUsage =
        useStream && !LlmService.streamOptionsUnsupported(config);

    Map<String, dynamic> currentBody() => LlmService.buildRequestBody(
          config: config,
          messages: messages,
          tools: tools,
          temperature: temperature,
          withEffort: sendEffort,
          withTemperature: sendTemperature,
          stream: useStream,
          includeUsage: sendIncludeUsage,
        );

    var effortDropped = false;
    while (true) {
      try {
        if (useStream) {
          final streamed = await sendStreamedTurn(
            config: config,
            body: currentBody(),
            cancelToken: cancelToken,
            onTextDelta: onTextDelta,
            onReasoningDelta: onReasoningDelta,
          );
          return LlmToolResponse(
            message: streamed.message,
            finishReason: streamed.finishReason,
            promptTokens: streamed.promptTokens,
            completionTokens: streamed.completionTokens,
            effortDropped: effortDropped,
          );
        }

        final response = await sendToolTurn(
          config: config,
          body: currentBody(),
          cancelToken: cancelToken,
        );
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
          promptTokens:
              usage is Map ? (usage['prompt_tokens'] as num?)?.toInt() : null,
          completionTokens: usage is Map
              ? (usage['completion_tokens'] as num?)?.toInt()
              : null,
          effortDropped: effortDropped,
        );
      } on LlmRequestException catch (error) {
        final unusable = error.statusCode == 400 || error.statusCode == 422;
        if (!unusable) rethrow;
        final lower = error.message.toLowerCase();
        if (sendEffort && lower.contains('reasoning')) {
          LlmService.markEffortUnsupported(config);
          sendEffort = false;
          effortDropped = true;
          continue;
        }
        if (sendTemperature && lower.contains('temperature')) {
          LlmService.markTemperatureUnsupported(config);
          sendTemperature = false;
          continue;
        }
        if (sendIncludeUsage && lower.contains('stream_options')) {
          LlmService.markStreamOptionsUnsupported(config);
          sendIncludeUsage = false;
          continue;
        }
        rethrow;
      }
    }
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
