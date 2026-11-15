/// How much the model should think before answering.
///
/// The names are the user's, not a provider's: an OpenAI-compatible endpoint
/// spells this `reasoning_effort`, and plenty of endpoints do not understand the
/// field at all. [auto] therefore sends nothing at all — the safe default, and
/// the only one that cannot make a working setup start failing.
enum ThinkingLevel {
  auto('自动', null, '由模型自己决定，不额外发送参数'),
  fast('快速响应', 'low', '直接回答，适合读一页、点一下这类简单步骤'),
  deep('深度思考', 'high', '想清楚再动手，适合多步任务，但更慢更贵');

  const ThinkingLevel(this.label, this.effort, this.description);

  final String label;

  /// The `reasoning_effort` value, or null when nothing should be sent.
  final String? effort;

  final String description;

  /// Whether this level asks the provider for anything at all.
  bool get sendsEffort => effort != null;
}

/// Configuration for the OpenAI-compatible LLM provider
class LlmConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final ThinkingLevel thinking;

  /// Output ceiling in tokens. Null means "leave it to the provider", which is
  /// the right default: guessing low truncates an answer, guessing high costs
  /// money on a provider that ignores it anyway.
  final int? maxOutputTokens;

  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.temperature = 0.2,
    this.thinking = ThinkingLevel.auto,
    this.maxOutputTokens,
  });

  /// Empty on purpose: there is one endpoint shape (OpenAI-compatible) and the
  /// user supplies it. Nothing here guesses a vendor.
  factory LlmConfig.defaultConfig() => const LlmConfig(
        baseUrl: '',
        apiKey: '',
        model: '',
        temperature: 0.1,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'temperature': temperature,
        'thinking': thinking.name,
        if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
      };

  factory LlmConfig.fromJson(Map<String, dynamic> json) => LlmConfig(
        baseUrl: json['baseUrl'] ?? '',
        apiKey: json['apiKey'] ?? '',
        model: json['model'] ?? '',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.1,
        thinking: ThinkingLevel.values.firstWhere(
          (level) => level.name == json['thinking'],
          orElse: () => ThinkingLevel.auto,
        ),
        maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt(),
      );

  LlmConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
    ThinkingLevel? thinking,
    int? maxOutputTokens,
    bool clearMaxOutputTokens = false,
  }) {
    return LlmConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      thinking: thinking ?? this.thinking,
      maxOutputTokens:
          clearMaxOutputTokens ? null : (maxOutputTokens ?? this.maxOutputTokens),
    );
  }

  bool get isValid =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  /// Models that renamed the output ceiling. Sending `max_tokens` to these is a
  /// 400, and sending `max_completion_tokens` to anything else is too.
  static bool usesMaxCompletionTokens(String model) {
    final name = model.trim().toLowerCase();
    return name.startsWith('o1') ||
        name.startsWith('o3') ||
        name.startsWith('o4') ||
        name.startsWith('gpt-5');
  }

  /// Reasoning series models that reject custom `temperature` values (such as
  /// 0.1) on OpenAI-compatible endpoints.
  static bool omitsTemperature(String model) {
    final name = model.trim().toLowerCase();
    return name.startsWith('o1') ||
        name.startsWith('o3') ||
        name.startsWith('o4');
  }
}

/// A named, reusable LLM endpoint configuration preset.
class LlmPreset {
  const LlmPreset({
    required this.id,
    required this.name,
    required this.config,
  });

  final String id;
  final String name;
  final LlmConfig config;

  LlmPreset copyWith({
    String? id,
    String? name,
    LlmConfig? config,
  }) =>
      LlmPreset(
        id: id ?? this.id,
        name: name ?? this.name,
        config: config ?? this.config,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'config': config.toJson(),
      };

  factory LlmPreset.fromJson(Map<String, dynamic> json) => LlmPreset(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        config: json['config'] is Map
            ? LlmConfig.fromJson(Map<String, dynamic>.from(json['config'] as Map))
            : LlmConfig.defaultConfig(),
      );
}
