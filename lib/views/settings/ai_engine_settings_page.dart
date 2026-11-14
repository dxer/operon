import 'dart:async';

import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/llm_config.dart';
import '../../models/model_profile.dart';
import '../../services/llm_service.dart';
import '../../services/llm_tools.dart';
import '../../services/storage_service.dart';

class AiEngineSettingsPage extends StatefulWidget {
  const AiEngineSettingsPage({super.key});

  @override
  State<AiEngineSettingsPage> createState() => _AiEngineSettingsPageState();
}

class _AiEngineSettingsPageState extends State<AiEngineSettingsPage> {
  late StorageService _storage;
  bool _isLoading = true;
  bool _obscureApiKey = true;
  bool _isTestingApi = false;
  bool _isLoadingModels = false;
  List<String> _models = const [];
  ThinkingLevel _thinking = ThinkingLevel.auto;
  final TextEditingController _maxTokensController = TextEditingController();

  /// Typing must reach the store, but not one write per keystroke — and it must
  /// not announce itself. Only the save button says anything.
  Timer? _saveDebounce;

  /// The base URL the shown model list came from. A list from another endpoint
  /// is worse than no list: it offers names that endpoint has never heard of.
  String? _modelsFor;

  /// What this endpoint+model can do, and which key it was loaded for, so a
  /// model change cannot leave the previous model's capabilities on screen.
  ModelProfile _profile = const ModelProfile();
  String? _profileFor;
  final TextEditingController _contextWindowController = TextEditingController();

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  double _temperature = 0.1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    // A keystroke from the last 400ms is still pending. Flush it, capturing the
    // config before the controllers go away — the write itself does not need us.
    final pendingWrite = _saveDebounce?.isActive ?? false;
    _saveDebounce?.cancel();
    if (pendingWrite) unawaited(_storage.saveLlmConfig(_currentConfig));
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _maxTokensController.dispose();
    _contextWindowController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    final config = _storage.getLlmConfig();
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    _temperature = config.temperature;
    _thinking = config.thinking;
    _maxTokensController.text = config.maxOutputTokens?.toString() ?? '';
    _loadProfile();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// What the user typed, as a config. Reading it from the fields once means
  /// saving and testing cannot disagree.
  LlmConfig get _currentConfig => LlmConfig(
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
        temperature: _temperature,
        thinking: _thinking,
        // 0 and negatives are a 400 at the endpoint, not a ceiling.
        maxOutputTokens: _parsedMaxTokens,
      );

  /// The fetched list, but only while it still describes the endpoint on
  /// screen. Change the base URL and the old names stop being offered.
  List<String> get _shownModels =>
      _modelsFor == _baseUrlController.text.trim() ? _models : const [];

  /// Reads the profile for the model currently in the field.
  void _loadProfile() {
    final config = _currentConfig;
    _profile = _storage.getModelProfile(config);
    _profileFor = StorageService.modelProfileKey(config);
    _contextWindowController.text = _profile.contextWindow.toString();
  }

  /// Called when the model itself changed: the profile belongs to a model, so
  /// showing the previous one would be showing a lie.
  void _reloadProfileIfModelChanged() {
    if (_profileFor == StorageService.modelProfileKey(_currentConfig)) return;
    setState(_loadProfile);
  }

  /// Writes the profile for the model in the field, at most once per keystroke
  /// burst, the same way the rest of the form persists.
  void _saveProfile(ModelProfile profile) {
    setState(() => _profile = profile);
    _profileFor = StorageService.modelProfileKey(_currentConfig);
    unawaited(_storage.saveModelProfile(_currentConfig, profile));
  }

  int? get _parsedMaxTokens {
    final value = int.tryParse(_maxTokensController.text.trim());
    return value != null && value > 0 ? value : null;
  }

  /// Writes without comment. Called from every keystroke, so it stays quiet.
  Future<void> _persist() async {
    _saveDebounce?.cancel();
    await _storage.saveLlmConfig(_currentConfig);
  }

  void _schedulePersist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _persist);
    // The model chips light up from the field's text, so a keystroke has to
    // rebuild even though nothing was written yet.
    setState(() {});
  }

  /// The explicit save. Flushes anything typed but not yet written.
  Future<void> _saveConfig() async {
    if (_saveDebounce?.isActive ?? false) _saveDebounce!.cancel();
    await _storage.saveLlmConfig(_currentConfig);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 配置已成功保存')),
      );
    }
  }

  /// Asks the endpoint what it offers, and offers it back as choices.
  Future<void> _fetchModels() async {
    final config = _currentConfig;
    if (config.baseUrl.trim().isEmpty) {
      _snack('请先填写 Base URL');
      return;
    }
    FocusScope.of(context).unfocus();
    await _persist();
    setState(() => _isLoadingModels = true);
    try {
      final models = await LlmService().fetchModels(config);
      if (!mounted) return;
      setState(() {
        _models = models;
        _modelsFor = config.baseUrl.trim();
        _isLoadingModels = false;
      });
      if (models.isEmpty) {
        _snack('这个端点没有返回任何模型');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingModels = false);
      _snack(describeLlmFailure(error));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _testConnection() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = _currentConfig;

    if (!config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先填写完整的 Base URL、API Key 与 Model 名称'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isTestingApi = true);
    final llmService = LlmService();

    try {
      // The agent needs one thing from a model: a tool call. A plain text
      // reply proves the key works but says nothing about whether the agent
      // can drive a page, so the probe offers a trivial tool and checks that
      // the model calls it.
      final probe = await llmService.chatWithTools(
        config: config,
        // The probe is what tells the user whether this model can drive a page,
        // so it asks the same question the run would.
        profile: _profile,
        messages: [
          {
            'role': 'user',
            'content': '调用 ping 工具，把 name 设为 "ok"。只调用工具，不要解释。',
          },
        ],
        tools: [
          {
            'type': 'function',
            'function': {
              'name': 'ping',
              'description': '连通性探测',
              'parameters': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string', 'description': '固定填 ok'},
                },
                'required': ['name'],
                'additionalProperties': false,
              },
            },
          },
        ],
      );

      final calls = probe.message['tool_calls'];
      final calledTool = calls is List &&
          calls.any((call) =>
              call is Map &&
              call['function'] is Map &&
              (call['function'] as Map)['name'] == 'ping');

      if (mounted) {
        setState(() => _isTestingApi = false);
        // A refused preference is worth reporting here: this dialog is where
        // the user is deciding whether the setup works.
        final effortNote = probe.effortDropped
            ? '（注意：这个端点不接受 reasoning_effort，'
                '「${_thinking.label}」不会生效，请求按「自动」发送。）'
            : '';
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              calledTool ? 'API 与工具调用均正常' : 'API 连通，但模型没有调用工具',
              style: TextStyle(
                color: calledTool ? AppTheme.accentOf(isDark) : AppTheme.warningOf(isDark),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              calledTool
                  ? '模型响应正常，并能调用工具，可以直接驱动网页。$effortNote'
                  : '模型能返回内容，但没有调用工具。Operon 的智能体依赖 function calling；'
                      '请换一个支持工具调用的模型，否则任务无法执行。\n\n'
                      '模型回复：${(probe.content ?? '').trim().isEmpty ? '（空）' : probe.content}',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('好的'),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTestingApi = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('API 连通测试失败',
                style: TextStyle(
                    color: AppTheme.dangerOf(isDark),
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            content: Text(
              '连接出现异常，请检查网络或密钥：\n$e',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('关闭'),
              )
            ],
          ),
        );
      }
    } finally {
      llmService.dispose();
    }
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      );

  /// Three-way switch: the user's answer, or "you decide".
  Widget _traitRow(
    String title,
    ModelTrait value,
    ValueChanged<ModelTrait> onChanged, {
    required String autoLabel,
  }) {
    final labels = {
      ModelTrait.auto: autoLabel,
      ModelTrait.yes: '支持',
      ModelTrait.no: '不支持',
    };
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final trait in ModelTrait.values)
              ChoiceChip(
                label: Text(labels[trait]!,
                    style: const TextStyle(fontSize: 11.5)),
                selected: value == trait,
                onSelected: (_) => onChanged(trait),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 智能体引擎'),
        actions: [
          IconButton(
            icon: Icon(Icons.check_rounded, color: AppTheme.accentOf(isDark)),
            tooltip: '保存配置',
            onPressed: _saveConfig,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OpenAI 兼容端点配置',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _baseUrlController,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.example.com/v1',
                    helperText: '任意 OpenAI 兼容端点，末尾会自动补 /chat/completions',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) {
                    _schedulePersist();
                    _reloadProfileIfModelChanged();
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'sk-...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                  ),
                  onChanged: (_) => _schedulePersist(),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _modelController,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Model 模型名',
                          hintText: '点右侧获取，或直接填写',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (_) {
                          _schedulePersist();
                          _reloadProfileIfModelChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _isLoadingModels ? null : _fetchModels,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isLoadingModels
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('获取列表', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                if (_shownModels.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  // Picking is the point: a name typed from memory is the most
                  // common way a working endpoint stops working. The list is
                  // capped and scrolls because a router can offer hundreds.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_shownModels.length} 个可用模型',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ),
                      if (_modelController.text.isNotEmpty &&
                          _shownModels.contains(_modelController.text))
                        Icon(Icons.check_circle_rounded,
                            size: 13, color: AppTheme.accentOf(isDark)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 148),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                        width: 0.8,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final model in _shownModels)
                            ChoiceChip(
                              label: Text(model,
                                  style: const TextStyle(fontSize: 11.5)),
                              selected: _modelController.text == model,
                              onSelected: (_) {
                                setState(() => _modelController.text = model);
                                _persist();
                                _reloadProfileIfModelChanged();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  '思考级别',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final level in ThinkingLevel.values)
                      ChoiceChip(
                        label: Text(level.label, style: const TextStyle(fontSize: 12)),
                        selected: _thinking == level,
                        onSelected: (_) {
                          setState(() => _thinking = level);
                          _persist();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _thinking.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _maxTokensController,
                  style: const TextStyle(fontSize: 14),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '最大输出 token（可留空）',
                    hintText: '留空则交给模型自己决定',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => _schedulePersist(),
                ),
                const SizedBox(height: 16),
                _sectionLabel('模型能力'),
                const SizedBox(height: 4),
                Text(
                  '这里填的是这个模型自己的规格。不填就按默认猜：上下文 32000、'
                  '视觉看模型名。填对了，长任务不会提前被压缩，也不会在本地小模型上溢出。',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _contextWindowController,
                  style: const TextStyle(fontSize: 14),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '上下文窗口（token）',
                    hintText: '${ModelProfile.defaultContextWindow}',
                    helperText: '模型一次能读多少个 token',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (text) {
                    final value = int.tryParse(text.trim());
                    if (value == null || value < 1000) return;
                    _saveProfile(_profile.copyWith(contextWindow: value));
                  },
                ),
                const SizedBox(height: 12),
                _traitRow(
                  '图片输入',
                  _profile.vision,
                  (trait) => _saveProfile(_profile.copyWith(vision: trait)),
                  autoLabel: '按模型名猜',
                ),
                const SizedBox(height: 8),
                _traitRow(
                  '思考参数',
                  _profile.reasoning,
                  (trait) => _saveProfile(_profile.copyWith(reasoning: trait)),
                  autoLabel: '先试，被拒再退',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _profile.supportsTools,
                  title: const Text('支持工具调用',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '关掉后智能体不会用这个模型跑任务',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  onChanged: (value) =>
                      _saveProfile(_profile.copyWith(supportsTools: value)),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Temperature 采样温度',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(_temperature.toStringAsFixed(2),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryOf(isDark))),
                  ],
                ),
                Slider(
                  value: _temperature,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: _temperature.toStringAsFixed(2),
                  activeColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) {
                    setState(() => _temperature = val);
                  },
                  onChangeEnd: (val) async {
                    await _persist();
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isTestingApi ? null : _testConnection,
                    icon: _isTestingApi
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bolt_rounded, size: 18),
                    label: Text(_isTestingApi ? '正在测试连接中...' : '测试 API 连通性'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
