import 'dart:convert';

/// Configuration for the OpenAI-compatible LLM provider
class LlmConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;

  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.temperature = 0.2,
  });

  /// Default configuration pointing to DeepSeek (high capability, very low cost)
  factory LlmConfig.defaultConfig() {
    return const LlmConfig(
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: '',
      model: 'deepseek-chat',
      temperature: 0.1,
    );
  }

  /// Preset providers for quick setup
  static final List<Map<String, String>> presets = [
    {
      'name': 'DeepSeek',
      'baseUrl': 'https://api.deepseek.com/v1',
      'model': 'deepseek-chat',
      'hint': 'High reasoning capability, very economical for agent loops',
    },
    {
      'name': 'OpenAI (GPT-4o)',
      'baseUrl': 'https://api.openai.com/v1',
      'model': 'gpt-4o',
      'hint': 'Standard flagship model',
    },
    {
      'name': 'OpenAI (GPT-4o-mini)',
      'baseUrl': 'https://api.openai.com/v1',
      'model': 'gpt-4o-mini',
      'hint': 'Fast and lightweight for mobile automation',
    },
    {
      'name': 'SiliconFlow (Qwen2.5)',
      'baseUrl': 'https://api.siliconflow.cn/v1',
      'model': 'Qwen/Qwen2.5-72B-Instruct',
      'hint': 'Domestic fast high-speed API',
    },
    {
      'name': 'Ollama (Local / LAN)',
      'baseUrl': 'http://192.168.1.100:11434/v1',
      'model': 'llama3.1:8b',
      'hint': 'Local model running on your computer',
    },
  ];

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'temperature': temperature,
      };

  factory LlmConfig.fromJson(Map<String, dynamic> json) => LlmConfig(
        baseUrl: json['baseUrl'] ?? 'https://api.deepseek.com/v1',
        apiKey: json['apiKey'] ?? '',
        model: json['model'] ?? 'deepseek-chat',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.1,
      );

  LlmConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
  }) {
    return LlmConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
    );
  }

  bool get isValid => apiKey.trim().isNotEmpty && baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;
}
