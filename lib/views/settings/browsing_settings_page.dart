import 'package:flutter/material.dart';
import '../../config/app_constants.dart';
import '../../config/app_theme.dart';
import '../../services/haptic_service.dart';
import '../../services/storage_service.dart';

class BrowsingSettingsPage extends StatefulWidget {
  const BrowsingSettingsPage({super.key});

  @override
  State<BrowsingSettingsPage> createState() => _BrowsingSettingsPageState();
}

class _BrowsingSettingsPageState extends State<BrowsingSettingsPage> {
  late StorageService _storage;
  bool _isLoading = true;

  bool _blockImages = false;
  bool _javaScriptEnabled = true;
  bool _desktopMode = false;
  bool _hapticsEnabled = true;
  final TextEditingController _uaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _uaController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    _blockImages = _storage.getBlockImages();
    _javaScriptEnabled = _storage.getJavaScriptEnabled();
    _desktopMode = _storage.getDesktopMode();
    _hapticsEnabled = _storage.getHapticsEnabled();
    _uaController.text = _storage.getUserAgent();
    if (!mounted) return;
    setState(() => _isLoading = false);
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
        title: const Text('浏览与隐私保护'),
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
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('无图模式 (拦截图片加载)',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('在弱网环境下大幅缩减流量消耗并加快正文加载',
                      style: TextStyle(fontSize: 12, color: AppTheme.neutral)),
                  value: _blockImages,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (val) async {
                    setState(() => _blockImages = val);
                    await _storage.saveBlockImages(val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('JavaScript 脚本支持',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('关闭可彻底防御恶意弹窗，但现代网页功能可能受限',
                      style: TextStyle(fontSize: 12, color: AppTheme.neutral)),
                  value: _javaScriptEnabled,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (val) async {
                    setState(() => _javaScriptEnabled = val);
                    await _storage.saveJavaScriptEnabled(val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('默认电脑桌面版渲染',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('新建标签页默认使用 PC 宽屏视口及 Desktop User-Agent',
                      style: TextStyle(fontSize: 12, color: AppTheme.neutral)),
                  value: _desktopMode,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (val) async {
                    setState(() => _desktopMode = val);
                    await _storage.saveDesktopMode(val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('触感反馈',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('按钮、切换标签和拖动悬浮球时的轻微震动',
                      style: TextStyle(fontSize: 12, color: AppTheme.neutral)),
                  value: _hapticsEnabled,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (val) async {
                    setState(() => _hapticsEnabled = val);
                    HapticService.enabled = val;
                    await _storage.saveHapticsEnabled(val);
                  },
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
                  'User-Agent 请求标识',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  '向网站声明的客户端设备身份',
                  style: TextStyle(fontSize: 12, color: AppTheme.neutral),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: '常用设备预设',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: AppConstants.userAgentPresets.entries.map((e) {
                    return DropdownMenuItem(
                      value: e.value,
                      child: Text(e.key, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      _uaController.text = val;
                      _storage.saveUserAgent(val);
                      setState(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _uaController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: '自定义 User-Agent 字符串',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (val) => _storage.saveUserAgent(val.trim()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
