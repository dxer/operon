import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/llm_config.dart';
import '../../services/llm_service.dart';
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

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  double _temperature = 0.1;

  final List<Map<String, String>> _presets = [
    {
      'label': 'DeepSeek',
      'baseUrl': 'https://api.deepseek.com',
      'model': 'deepseek-chat',
    },
    {
      'label': 'OpenAI (GPT-4o)',
      'baseUrl': 'https://api.openai.com/v1',
      'model': 'gpt-4o-mini',
    },
    {
      'label': '阿里通义千问',
      'baseUrl': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'model': 'qwen-turbo',
    },
    {
      'label': '智谱 GLM',
      'baseUrl': 'https://open.bigmodel.cn/api/paas/v4',
      'model': 'glm-4-flash',
    },
    {
      'label': 'Moonshot (Kimi)',
      'baseUrl': 'https://api.moonshot.cn/v1',
      'model': 'moonshot-v1-8k',
    },
    {
      'label': 'Ollama (本地)',
      'baseUrl': 'http://10.0.2.2:11434/v1',
      'model': 'llama3.1',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    final config = _storage.getLlmConfig();
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    _temperature = config.temperature;
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    final config = LlmConfig(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      temperature: _temperature,
    );
    await _storage.saveLlmConfig(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 配置已成功保存')),
      );
    }
  }

  Future<void> _testConnection() async {
    final config = LlmConfig(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      temperature: _temperature,
    );

    if (!config.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先填写完整的 Base URL、API Key 与 Model 名称'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isTestingApi = true);
    final llmService = LlmService();

    try {
      final testMessages = [
        {'role': 'system', 'content': '你是一个自动化助手，必须回复合法的 JSON 动作。'},
        {'role': 'user', 'content': '测试连接：请输出 finish 动作，summary 为 "连接成功"'}
      ];

      final action = await llmService.getNextAction(
        config: config,
        messages: testMessages,
      );
      final summary = action.summary?.trim() ?? '';

      if (mounted) {
        setState(() => _isTestingApi = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('API 连通性测试通过',
                style: TextStyle(
                    color: Colors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            content: Text(
              '模型响应正常！\n返回动作: ${action.action.name}\n反馈摘要: ${summary.isNotEmpty ? summary : "成功达成连通"}',
              style: const TextStyle(fontSize: 13),
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
            title: const Text('API 连通测试失败',
                style: TextStyle(
                    color: Colors.redAccent,
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

  void _applyPreset(Map<String, String> preset) {
    setState(() {
      _baseUrlController.text = preset['baseUrl']!;
      _modelController.text = preset['model']!;
    });
    _saveConfig();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已套用 ${preset['label']} 预设')),
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
            icon: const Icon(Icons.check_rounded, color: AppTheme.accent),
            tooltip: '保存配置',
            onPressed: _saveConfig,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
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
                  '服务商快速套用',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _presets.map((preset) {
                    final isCurrent =
                        _baseUrlController.text == preset['baseUrl'] &&
                            _modelController.text == preset['model'];
                    return ActionChip(
                      label: Text(preset['label']!,
                          style: const TextStyle(fontSize: 12)),
                      backgroundColor: isCurrent
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : null,
                      side: isCurrent
                          ? const BorderSide(
                              color: AppTheme.primary, width: 1.2)
                          : null,
                      onPressed: () => _applyPreset(preset),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
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
                    hintText: 'https://api.deepseek.com',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => _saveConfig(),
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
                  onChanged: (_) => _saveConfig(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _modelController,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Model 模型名',
                    hintText: 'deepseek-chat',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => _saveConfig(),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Temperature 采样温度',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(_temperature.toStringAsFixed(2),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary)),
                  ],
                ),
                Slider(
                  value: _temperature,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: _temperature.toStringAsFixed(2),
                  activeColor: AppTheme.primary,
                  onChanged: (val) {
                    setState(() => _temperature = val);
                  },
                  onChangeEnd: (val) async {
                    await _saveConfig();
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
