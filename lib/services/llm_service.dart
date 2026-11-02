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
      // If error indicates response_format unsupported, retry once without it
      if (response.statusCode == 400 &&
          (response.body.contains('response_format') || response.body.contains('json_object'))) {
        try {
          final fallbackBody = jsonEncode({
            'model': config.model.trim(),
            'messages': messages,
            'temperature': config.temperature,
          });
          response = await _client
              .post(uri, headers: headers, body: fallbackBody)
              .timeout(const Duration(seconds: 45));
        } catch (_) {}
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

  /// General chat completion helper returning raw String content
  Future<String> chatCompletion({
    required LlmConfig config,
    required List<Map<String, String>> messages,
    double? temperature,
  }) async {
    if (!config.isValid) {
      throw Exception('请先在设置中配置有效的 API Key 与大模型服务地址。');
    }

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
      'temperature': temperature ?? config.temperature,
    });

    final response = await _client
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw Exception('大模型响应错误 (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('模型返回了空响应');
    }

    return choices[0]['message']?['content'] as String? ?? '';
  }

  /// Mobile One-Click Summarizer
  Future<String> summarizeWebPage({
    required LlmConfig config,
    required String title,
    required String url,
    required String content,
  }) async {
    final systemPrompt = '''
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
        systemInstruction = '你是一个高级翻译官。请将用户选中的文本翻译为自然、优美、地道的中文（若是中文则翻译为英文）。仅输出最终翻译结果，不要任何多余寒暄。';
        break;
      case 'explain':
        systemInstruction = '你是一个百科全书顾问。请用最通俗易懂的大白话，解释用户选中的词汇、概念或技术术语，字数在 120 字以内。';
        break;
      case 'reply':
        systemInstruction = '你是一个高情商的社交网络达人。请针对用户选中的这句推文/发言，写一条幽默、有见地或引人共鸣的简短社交媒体回复（50 字以内）。';
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
    final systemPrompt = '''
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
        'matchPattern': decoded['matchPattern']?.toString() ?? (currentUrl.isNotEmpty ? '*${Uri.tryParse(currentUrl)?.host ?? ""}*' : '*'),
        'code': decoded['code']?.toString() ?? '// 脚本生成异常',
      };
    } catch (e) {
      // Fallback if model returned plain code or non-JSON
      return {
        'name': '自定义 AI 脚本',
        'description': prompt,
        'matchPattern': currentUrl.isNotEmpty ? '*${Uri.tryParse(currentUrl)?.host ?? ""}*' : '*',
        'code': raw.startsWith('(') ? raw : '(() => {\n  try {\n    $raw\n  } catch (e) { console.error(e); }\n})();',
      };
    }
  }

  void dispose() {
    _client.close();
  }
}
