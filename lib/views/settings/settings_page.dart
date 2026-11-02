import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../config/app_constants.dart';
import '../../config/app_theme.dart';
import '../../models/llm_config.dart';
import '../../services/llm_service.dart';
import '../../services/storage_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late StorageService _storage;
  bool _isLoading = true;
  bool _obscureApiKey = true;
  bool _isTestingApi = false;

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _uaController = TextEditingController();
  double _temperature = 0.1;
  int _maxSteps = 15;
  bool _safeMode = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    final config = _storage.getLlmConfig();
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    _temperature = config.temperature;
    _uaController.text = _storage.getUserAgent();
    _maxSteps = _storage.getMaxSteps();
    _safeMode = _storage.getSafeMode();

    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    final config = LlmConfig(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      temperature: _temperature,
    );
    await _storage.saveLlmConfig(config);
    await _storage.saveUserAgent(_uaController.text.trim());
    await _storage.saveMaxSteps(_maxSteps);
    await _storage.saveSafeMode(_safeMode);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已成功保存！'),
          backgroundColor: AppTheme.accent,
        ),
      );
      Navigator.of(context).pop(true); // Return true to indicate settings updated
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
        {
          'role': 'user',
          'content': '测试连接：请输出 finish 动作，summary 为 "连接成功"'
        }
      ];

      final action = await llmService.getNextAction(
        config: config,
        messages: testMessages,
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.darkCard,
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.accent, size: 22),
                SizedBox(width: 8),
                Text('API 连接成功', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Text(
              '模型返回正常！\nAction: ${action.action.name}\nThought: ${action.thought}\nSummary: ${action.summary}',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.darkCard,
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
                SizedBox(width: 8),
                Text('连接测试失败', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Text(
              e.toString(),
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingApi = false);
      }
    }
  }

  Future<void> _clearAllCookies() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('确认清除所有 Cookie？', style: TextStyle(fontSize: 16)),
        content: const Text(
          '清除后所有网站的登录状态（包括推特/X）都将失效，需重新登录。',
          style: TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await CookieManager.instance().deleteAllCookies();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清除所有 Cookies 及会话缓存')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('配置中心'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: AppTheme.accent),
            onPressed: _saveSettings,
            tooltip: '保存设置',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section 1: LLM Configuration
          _buildSectionHeader('AI 大模型配置', Icons.smart_toy_outlined),
          const SizedBox(height: 8),
          const Text(
            '快捷预设（点击自动填充）:',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: LlmConfig.presets.map((preset) {
              return ActionChip(
                label: Text(preset['name']!, style: const TextStyle(fontSize: 12)),
                backgroundColor: const Color(0xFF1E2732),
                side: const BorderSide(color: AppTheme.darkBorder),
                onPressed: () {
                  setState(() {
                    _baseUrlController.text = preset['baseUrl']!;
                    _modelController.text = preset['model']!;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              hintText: 'https://api.deepseek.com/v1',
              prefixIcon: Icon(Icons.link, size: 20),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              prefixIcon: const Icon(Icons.key, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                  size: 20,
                  color: Colors.white54,
                ),
                onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: 'Model 名称',
              hintText: 'deepseek-chat / gpt-4o',
              prefixIcon: Icon(Icons.model_training, size: 20),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              const Text('生成多样性 (Temperature):', style: TextStyle(fontSize: 13)),
              const Spacer(),
              Text(_temperature.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
            ],
          ),
          Slider(
            value: _temperature,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            activeColor: AppTheme.primary,
            onChanged: (val) => setState(() => _temperature = val),
          ),

          OutlinedButton.icon(
            onPressed: _isTestingApi ? null : _testConnection,
            icon: _isTestingApi
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bolt, size: 18),
            label: Text(_isTestingApi ? '测试中...' : '测试大模型连通性'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: AppTheme.primary),
            ),
          ),

          const SizedBox(height: 28),

          // Section 2: Browser & Stealth Configuration
          _buildSectionHeader('浏览器与防检测 (User-Agent)', Icons.language_outlined),
          const SizedBox(height: 8),
          const Text(
            '预设 User-Agent (点击切换):',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 6),
          ...AppConstants.userAgentPresets.entries.map((entry) {
            final isSelected = _uaController.text == entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: InkWell(
                onTap: () => setState(() => _uaController.text = entry.value),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary.withOpacity(0.15) : const Color(0xFF16181C),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.darkBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 16,
                        color: isSelected ? AppTheme.primary : Colors.white38,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),

          TextField(
            controller: _uaController,
            maxLines: 2,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              labelText: '当前生效的 User-Agent',
            ),
          ),

          const SizedBox(height: 28),

          // Section 3: Safety & Loop Guardrails
          _buildSectionHeader('安全与执行护栏', Icons.shield_outlined),
          const SizedBox(height: 8),

          SwitchListTile(
            title: const Text('敏感操作人工确认 (Safe Mode)', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '当 AI 点击发推/发布/付款等关键按钮前，暂停并等待你手动确认',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            value: _safeMode,
            activeColor: AppTheme.accent,
            onChanged: (val) => setState(() => _safeMode = val),
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              const Text('单次任务最大步数限制:', style: TextStyle(fontSize: 13)),
              const Spacer(),
              Text('$_maxSteps 步',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
            ],
          ),
          Slider(
            value: _maxSteps.toDouble(),
            min: 5,
            max: 30,
            divisions: 25,
            activeColor: AppTheme.primary,
            onChanged: (val) => setState(() => _maxSteps = val.round()),
          ),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _clearAllCookies,
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
            label: const Text('清除所有 Cookies 与本地缓存', style: TextStyle(color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
