/// A named OpenAI-compatible endpoint, plus the model worth trying first.
///
/// The suggestion is a starting point, not a claim: providers rename and retire
/// models constantly, which is why the model field stays editable and the
/// endpoint can be asked for its current list. One definition is shared by
/// first-run setup and the engine settings page so the two cannot offer
/// different endpoints.
class ProviderPreset {
  const ProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.model,
    this.note = '',
  });

  final String name;
  final String baseUrl;

  /// A model that is likely to exist and to support tool calling.
  final String model;

  /// One line of setup advice, shown only when it matters.
  final String note;
}

const List<ProviderPreset> providerPresets = [
  ProviderPreset(
    name: 'OpenAI 官方',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
  ),
  ProviderPreset(
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
  ),
  ProviderPreset(
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'openai/gpt-4o-mini',
  ),
  ProviderPreset(
    name: '硅基流动 SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    model: 'Qwen/Qwen2.5-72B-Instruct',
  ),
  ProviderPreset(
    name: 'Moonshot Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k',
  ),
  ProviderPreset(
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-plus',
  ),
  ProviderPreset(
    name: 'Ollama (本地)',
    baseUrl: 'http://localhost:11434/v1',
    model: 'llama3.1',
    note: 'Ollama 跑在电脑上时，localhost 指的是手机本身。'
        '请填电脑的局域网地址，例如 http://192.168.1.5:11434/v1。',
  ),
];
