import 'dart:async';

import 'package:flutter/material.dart';
import '../../config/app_constants.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../config/provider_presets.dart';
import '../../models/llm_config.dart';
import '../../models/model_profile.dart';
import '../../services/llm_service.dart';
import '../../services/llm_tools.dart';
import '../../services/model_probe.dart';
import '../../services/storage_service.dart';
import '../widgets/operon_list_row.dart';

part 'ai_engine_sections.dart';

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
  List<LlmPreset> _presets = const [];
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
  bool _autoCompactEnabled = true;
  final TextEditingController _autoCompactController = TextEditingController();

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();

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
    _autoCompactController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    final config = _storage.getLlmConfig();
    _presets = _storage.getLlmPresets();
    _autoCompactEnabled = _storage.getAutoCompactEnabled();
    _autoCompactController.text = '${_storage.getAutoCompactTokens()}';
    _applyConfigFields(config);
    _loadProfile();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _saveAutoCompactEnabled(bool enabled) {
    setState(() => _autoCompactEnabled = enabled);
    unawaited(_storage.saveAutoCompactEnabled(enabled));
  }

  void _saveAutoCompactTokens(int tokens) {
    unawaited(_storage.saveAutoCompactTokens(tokens));
  }

  void _applyConfigFields(LlmConfig config) {
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    _thinking = config.thinking;
    _maxTokensController.text = config.maxOutputTokens?.toString() ?? '';
  }

  bool _isPresetActive(LlmPreset preset) {
    final current = _currentConfig;
    return preset.config.baseUrl.trim() == current.baseUrl &&
        preset.config.model.trim() == current.model &&
        preset.config.apiKey.trim() == current.apiKey;
  }

  Future<void> _applyPreset(LlmPreset preset) async {
    _saveDebounce?.cancel();
    _applyConfigFields(preset.config);
    await _storage.saveLlmConfig(preset.config);
    _loadProfile();
    if (mounted) {
      setState(() {});
      _snack('已切换到「${preset.name}」');
    }
  }

  Future<void> _saveCurrentAsPreset() async {
    final config = _currentConfig;
    if (config.baseUrl.isEmpty || config.model.isEmpty) {
      _snack('请先填写 Base URL 和 Model 模型名');
      return;
    }
    final controller = TextEditingController(text: config.model);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存为配置预设'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '预设名称',
              hintText: '例如：DeepSeek 日常 / GPT-4o 视觉',
              isDense: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (name == null || name.isEmpty) return;
      final preset = LlmPreset(
        id: 'p_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        config: config,
      );
      await _storage.saveLlmPreset(preset);
      await _storage.saveLlmConfig(config);
      if (mounted) {
        setState(() => _presets = _storage.getLlmPresets());
        _snack('已保存预设「$name」');
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deletePreset(LlmPreset preset) async {
    await _storage.deleteLlmPreset(preset.id);
    if (mounted) {
      setState(() => _presets = _storage.getLlmPresets());
    }
  }

  /// What the user typed, as a config. Reading it from the fields once means
  /// saving and testing cannot disagree.
  LlmConfig get _currentConfig => LlmConfig(
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
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
    final llmService = LlmService();
    try {
      final models = await llmService.fetchModels(config);
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
    } finally {
      llmService.dispose();
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

    try {
      // The agent needs one thing from a model: a tool call. A plain text
      // reply proves the key works but says nothing about whether the agent
      // can drive a page, so the shared probe offers a trivial tool and
      // checks that the model calls it.
      final probe = await probeModel(config: config, profile: _profile);

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
              probe.calledTool ? 'API 与工具调用均正常' : 'API 连通，但模型没有调用工具',
              style: TextStyle(
                color: probe.calledTool
                    ? AppTheme.accentOf(isDark)
                    : AppTheme.warningOf(isDark),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              probe.calledTool
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
              '连接出现异常，请检查网络或密钥：\n${describeLlmFailure(e)}',
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
    }
  }

  LlmPreset? get _activePreset {
    for (final preset in _presets) {
      if (_isPresetActive(preset)) return preset;
    }
    return null;
  }

  void _mutate(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final hairline = AppInk.hairline(isDark);
    final activePreset = _activePreset;
    final uniqueModels = _shownModels.toSet().toList();
    final currentModel = _modelController.text.trim();
    final matchedModel =
        uniqueModels.contains(currentModel) ? currentModel : null;

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
          AppSpace.page,
          AppSpace.page,
          AppSpace.page,
          AppSpace.page + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          _buildPresetsCard(
            isDark: isDark,
            cardColor: cardColor,
            hairline: hairline,
            activePreset: activePreset,
          ),
          const SizedBox(height: AppSpace.x3),
          _buildEndpointConfigCard(
            isDark: isDark,
            cardColor: cardColor,
            hairline: hairline,
            uniqueModels: uniqueModels,
            matchedModel: matchedModel,
          ),
        ],
      ),
    );
  }
}
