import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../config/app_constants.dart';
import '../../config/app_theme.dart';
import '../../models/llm_config.dart';
import '../../services/llm_service.dart';
import '../../services/storage_service.dart';
import '../../services/theme_service.dart';
import '../widgets/macro_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late StorageService _storage;
  late ThemeService _themeService;
  bool _isLoading = true;
  bool _obscureApiKey = true;
  bool _isTestingApi = false;

  // Controllers
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _uaController = TextEditingController();
  final TextEditingController _homepageController = TextEditingController();

  // Settings State
  double _temperature = 0.1;
  int _maxSteps = 15;
  bool _safeMode = true;
  ThemeMode _themeMode = ThemeMode.system;
  String _selectedSearchEngine = AppConstants.defaultSearchEngine;
  bool _webDarkMode = false;
  bool _blockImages = false;
  bool _javaScriptEnabled = true;
  bool _desktopMode = false;
  int _textZoom = 100;

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
    _uaController.dispose();
    _homepageController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    _themeService = await ThemeService.getInstance();

    final config = _storage.getLlmConfig();
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    _temperature = config.temperature;

    _uaController.text = _storage.getUserAgent();
    _homepageController.text = _storage.getHomepage();
    _maxSteps = _storage.getMaxSteps();
    _safeMode = _storage.getSafeMode();

    _themeMode = _themeService.themeMode;
    _selectedSearchEngine = _storage.getSearchEngine();
    _webDarkMode = _storage.getWebDarkMode();
    _blockImages = _storage.getBlockImages();
    _javaScriptEnabled = _storage.getJavaScriptEnabled();
    _desktopMode = _storage.getDesktopMode();
    _textZoom = _storage.getTextZoom();

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
    await _storage.saveHomepage(_homepageController.text.trim());
    await _storage.saveMaxSteps(_maxSteps);
    await _storage.saveSafeMode(_safeMode);

    await _themeService.setThemeMode(_themeMode);
    await _storage.saveSearchEngine(_selectedSearchEngine);
    await _storage.saveWebDarkMode(_webDarkMode);
    await _storage.saveBlockImages(_blockImages);
    await _storage.saveJavaScriptEnabled(_javaScriptEnabled);
    await _storage.saveDesktopMode(_desktopMode);
    await _storage.saveTextZoom(_textZoom);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('所有配置已成功保存并即时生效！'),
          backgroundColor: AppTheme.accent,
        ),
      );
      Navigator.of(context).pop(true);
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
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.accent, size: 22),
                SizedBox(width: 8),
                Text('API 连接成功', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Text(
              '模型返回正常！\nAction: ${action.action.name}\nThought: ${action.thought}\nSummary: ${action.summary}',
              style: const TextStyle(fontSize: 13),
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
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
                SizedBox(width: 8),
                Text('连接测试失败', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Text(
              e.toString(),
              style: const TextStyle(fontSize: 13),
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

  Future<void> _showClearDataDialog() async {
    bool clearCookies = true;
    bool clearCache = true;
    bool clearStorage = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('清除浏览数据', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text('Cookies 与网站登录态', style: TextStyle(fontSize: 14)),
                subtitle: const Text('清除后需要重新登录各大平台', style: TextStyle(fontSize: 12)),
                value: clearCookies,
                activeColor: AppTheme.primary,
                onChanged: (val) => setDialogState(() => clearCookies = val ?? false),
              ),
              CheckboxListTile(
                title: const Text('网页缓存文件 (Cache)', style: TextStyle(fontSize: 14)),
                subtitle: const Text('释放应用占用的图片与静态脚本存储', style: TextStyle(fontSize: 12)),
                value: clearCache,
                activeColor: AppTheme.primary,
                onChanged: (val) => setDialogState(() => clearCache = val ?? false),
              ),
              CheckboxListTile(
                title: const Text('本地存储 (LocalStorage / IndexedDB)', style: TextStyle(fontSize: 14)),
                value: clearStorage,
                activeColor: AppTheme.primary,
                onChanged: (val) => setDialogState(() => clearStorage = val ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: (clearCookies || clearCache || clearStorage)
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('确认清除', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      if (clearCookies) {
        await CookieManager.instance().deleteAllCookies();
      }
      if (clearStorage) {
        await WebStorageManager.instance().deleteAllData();
      }
      if (clearCache) {
        await InAppWebViewController.clearAllCache();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清除选中的浏览数据与本地缓存！')),
        );
      }
    }
  }

  void _openMacroManagement() {
    showDialog(
      context: context,
      builder: (_) => MacroDialog(
        onSelectMacro: (macro) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已选择宏: ${macro.title}')),
          );
        },
      ),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览器与 AI 设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: AppTheme.accent),
            onPressed: _saveSettings,
            tooltip: '保存所有设置',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          // -------------------------------------------------------------
          // Group 1: 外观与主题
          // -------------------------------------------------------------
          _buildGroupCard(
            title: '外观与主题',
            icon: Icons.palette_outlined,
            children: [
              const Text('主题模式:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    label: Text('跟随系统'),
                    icon: Icon(Icons.brightness_auto, size: 16),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    label: Text('浅色'),
                    icon: Icon(Icons.light_mode, size: 16),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    label: Text('暗色'),
                    icon: Icon(Icons.dark_mode, size: 16),
                  ),
                ],
                selected: {_themeMode},
                onSelectionChanged: (Set<ThemeMode> newSelection) {
                  setState(() {
                    _themeMode = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 14),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('网页智能深色护眼模式', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '将网页色彩强制反色自适应为暗夜模式，夜间更护眼',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                value: _webDarkMode,
                activeColor: AppTheme.primary,
                onChanged: (val) => setState(() => _webDarkMode = val),
              ),

              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('网页字体缩放:', style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  Text('$_textZoom%',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                ],
              ),
              Slider(
                value: _textZoom.toDouble(),
                min: 80,
                max: 150,
                divisions: 7,
                activeColor: AppTheme.primary,
                label: '$_textZoom%',
                onChanged: (val) => setState(() => _textZoom = val.round()),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // -------------------------------------------------------------
          // Group 2: 网页浏览与隐私
          // -------------------------------------------------------------
          _buildGroupCard(
            title: '网页浏览与隐私',
            icon: Icons.language_outlined,
            children: [
              // Search Engine Selector
              Row(
                children: [
                  const Text('默认搜索引擎:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  DropdownButton<String>(
                    value: _selectedSearchEngine,
                    underline: const SizedBox(),
                    items: AppConstants.searchEngines.keys.map((name) {
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedSearchEngine = val);
                      }
                    },
                  ),
                ],
              ),
              const Divider(height: 16),

              TextField(
                controller: _homepageController,
                decoration: const InputDecoration(
                  labelText: '主页 / 起始页网址',
                  hintText: 'https://x.com',
                  prefixIcon: Icon(Icons.home_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('无图模式 (节省流量)', style: TextStyle(fontSize: 14)),
                subtitle: const Text('禁止加载网页网络图片，加快载入并节省流量', style: TextStyle(fontSize: 12, color: Colors.grey)),
                value: _blockImages,
                activeColor: AppTheme.primary,
                onChanged: (val) => setState(() => _blockImages = val),
              ),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 JavaScript', style: TextStyle(fontSize: 14)),
                subtitle: const Text('关闭后大部分动态网页将无法正常交互', style: TextStyle(fontSize: 12, color: Colors.grey)),
                value: _javaScriptEnabled,
                activeColor: AppTheme.primary,
                onChanged: (val) => setState(() => _javaScriptEnabled = val),
              ),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('默认以电脑版网页浏览', style: TextStyle(fontSize: 14)),
                subtitle: const Text('全局使用 PC 桌面浏览器标识访问网站', style: TextStyle(fontSize: 12, color: Colors.grey)),
                value: _desktopMode,
                activeColor: AppTheme.primary,
                onChanged: (val) {
                  setState(() {
                    _desktopMode = val;
                    if (val) {
                      _uaController.text = AppConstants.uaDesktopChrome;
                    } else {
                      _uaController.text = AppConstants.uaAndroidChrome;
                    }
                  });
                },
              ),

              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showClearDataDialog,
                icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 18),
                label: const Text('清除浏览数据与缓存...', style: TextStyle(color: Colors.redAccent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // -------------------------------------------------------------
          // Group 3: AI Agent 大模型配置
          // -------------------------------------------------------------
          _buildGroupCard(
            title: 'AI Agent 大模型引擎',
            icon: Icons.smart_toy_outlined,
            children: [
              const Text(
                '快捷服务商预设（点击自动填充）:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: LlmConfig.presets.map((preset) {
                  return ActionChip(
                    label: Text(preset['name']!, style: const TextStyle(fontSize: 12)),
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
                    ),
                    onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: 'Model 模型名称',
                  hintText: 'deepseek-chat / gpt-4o',
                  prefixIcon: Icon(Icons.model_training, size: 20),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  const Text('温度多样性 (Temperature):', style: TextStyle(fontSize: 13)),
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
            ],
          ),

          const SizedBox(height: 16),

          // -------------------------------------------------------------
          // Group 4: 执行安全与护栏
          // -------------------------------------------------------------
          _buildGroupCard(
            title: '安全与执行护栏',
            icon: Icons.shield_outlined,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('敏感动作人工确认 (Safe Mode)', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '当 AI 点击发推/发布/付款等关键按钮前，暂停并等待你手动确认',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
            ],
          ),

          const SizedBox(height: 16),

          // -------------------------------------------------------------
          // Group 5: 宏管理与关于
          // -------------------------------------------------------------
          _buildGroupCard(
            title: '宏工作流与关于',
            icon: Icons.info_outline,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flash_on, color: Colors.amber),
                title: const Text('快捷宏 (Macro) 管理', style: TextStyle(fontSize: 14)),
                subtitle: const Text('查看、删除或重放已保存的 0 Token 宏任务', style: TextStyle(fontSize: 12, color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openMacroManagement,
              ),
              const Divider(height: 12),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.smartphone, color: AppTheme.primary),
                title: Text('Operon Browser', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Text('版本: v0.1.0 (构建版本 0.1.0+1)\n开源驱动的高性能自主 AI 移动浏览器',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            ],
          ),

          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _buildGroupCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
