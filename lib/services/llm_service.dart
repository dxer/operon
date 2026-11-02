import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/agent_action.dart';
import '../models/llm_config.dart';
import '../utils/json_parser.dart';

class LlmService {
  final http.Client _client;

  LlmService({http.Client? client}) : _client = client ?? http.Client();

  /// Sends the prompt to the configured LLM and returns the parsed AgentAction
  Future<AgentAction> getNextAction({
    required LlmConfig config,
    required List<Map<String, String>> messages,
  }) async {
    if (!config.isValid) {
      throw Exception('请先在设置中配置有效的 API Key 与大模型服务地址。');
    }

    // Normalize endpoint URL
    String endpoint = config.baseUrl.trim();
    if (!endpoint.endsWith('/chat/completions')) {
      if (endpoint.endsWith('/')) {
        endpoint = '${endpoint}chat/completions';
      } else {
        endpoint = '$endpoint/chat/completions';
      }
    }

    final uri = Uri.parse(endpoint);
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer ${config.apiKey.trim()}',
    };

    final body = jsonEncode({
      'model': config.model.trim(),
      'messages': messages,
      'temperature': config.temperature,
      // Many modern models support response_format: { type: "json_object" }
      'response_format': {'type': 'json_object'},
    });

    http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      // If response_format json_object caused an error on older models, retry once without it
      try {
        final fallbackBody = jsonEncode({
          'model': config.model.trim(),
          'messages': messages,
          'temperature': config.temperature,
        });
        response = await _client
            .post(uri, headers: headers, body: fallbackBody)
            .timeout(const Duration(seconds: 45));
      } catch (e2) {
        throw Exception('连接大模型服务失败: $e2');
      }
    }

    if (response.statusCode != 200) {
      String errDetail = response.body;
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

    final content = choices[0]['message']?['content'] as String? ?? '';
    final actionJson = JsonParser.extractJson(content);

    if (actionJson == null) {
      throw Exception('未能从模型回复中解析出合法 Action JSON: $content');
    }

    return AgentAction.fromJson(actionJson);
  }

  void dispose() {
    _client.close();
  }
}
