/// What one model can actually do.
///
/// This exists because the app used to guess: a fixed 32k context window for
/// every model, and a name-prefix heuristic for vision. Both are wrong in ways
/// the user pays for — an 8k local model overflows before the compactor reacts,
/// a 200k model compacts long before it needs to, and a vision model nobody
/// listed silently loses the screenshot tool.
///
/// The profile is per endpoint+model, editable in settings, and a guess only
/// fills in what the user has not said. Nothing here is sent to a provider.
enum ModelTrait {
  /// Let the app decide (the name heuristic, or try and see).
  auto,

  /// The model has this capability.
  yes,

  /// The model does not; do not use it and do not ask the provider.
  no,
}

class ModelProfile {
  const ModelProfile({
    this.contextWindow = defaultContextWindow,
    this.vision = ModelTrait.auto,
    this.reasoning = ModelTrait.auto,
    this.supportsTools = true,
  });

  /// What every model was assumed to have before profiles existed. Kept as the
  /// default so an unconfigured install behaves as it did.
  static const int defaultContextWindow = 32000;

  const ModelProfile.fallback() : this();

  /// Input tokens the model accepts, output reserved. Drives when the
  /// conversation is compacted.
  final int contextWindow;

  /// Whether images can be sent. [ModelTrait.auto] keeps the name heuristic.
  final ModelTrait vision;

  /// Whether `reasoning_effort` is accepted. [ModelTrait.no] stops sending it;
  /// [ModelTrait.auto] sends it and backs off if the endpoint refuses.
  final ModelTrait reasoning;

  /// Whether the model can call tools at all. False means the agent cannot run,
  /// and saying so up front is better than a run that fails on its first call.
  final bool supportsTools;

  ModelProfile copyWith({
    int? contextWindow,
    ModelTrait? vision,
    ModelTrait? reasoning,
    bool? supportsTools,
  }) {
    return ModelProfile(
      contextWindow: contextWindow ?? this.contextWindow,
      vision: vision ?? this.vision,
      reasoning: reasoning ?? this.reasoning,
      supportsTools: supportsTools ?? this.supportsTools,
    );
  }

  /// Resolved for one model id: what the user said, else a guess.
  bool visionFor(String model) => switch (vision) {
        ModelTrait.auto => guessVision(model),
        ModelTrait.yes => true,
        ModelTrait.no => false,
      };

  /// Whether a request may carry `reasoning_effort` at all.
  bool get reasoningAllowed => reasoning != ModelTrait.no;

  Map<String, dynamic> toJson() => {
        'contextWindow': contextWindow,
        'vision': vision.name,
        'reasoning': reasoning.name,
        'supportsTools': supportsTools,
      };

  factory ModelProfile.fromJson(Map<String, dynamic> json) {
    ModelTrait trait(String? name, ModelTrait fallback) {
      for (final value in ModelTrait.values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    final window = (json['contextWindow'] as num?)?.toInt();
    return ModelProfile(
      // A window of zero or a negative number would make every conversation
      // "too long"; fall back rather than trust it.
      contextWindow: window != null && window >= 1000
          ? window
          : defaultContextWindow,
      vision: trait(json['vision'] as String?, ModelTrait.auto),
      reasoning: trait(json['reasoning'] as String?, ModelTrait.auto),
      supportsTools: json['supportsTools'] as bool? ?? true,
    );
  }

  bool get isDefault =>
      contextWindow == defaultContextWindow &&
      vision == ModelTrait.auto &&
      reasoning == ModelTrait.auto &&
      supportsTools;

  /// Whether a model id is likely to accept images.
  ///
  /// A guess, not a capability list: providers expose no reliable flag, and the
  /// alternative is a settings toggle nobody knows how to set. The patterns
  /// below cover the models people actually use; when the guess is wrong the
  /// provider answers with an error the loop reports, which is one wasted call
  /// rather than a silently ignored screenshot.
  ///
  /// A user who knows better overrides it: [vision] = yes or no.
  static bool guessVision(String model) {
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
}
