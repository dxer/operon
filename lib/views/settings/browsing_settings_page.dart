import 'package:flutter/material.dart';
import '../../config/app_constants.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../services/haptic_service.dart';
import '../../services/storage_service.dart';
import '../widgets/operon_list_row.dart';

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
  bool _readingModeEnabled = true;
  bool _selectionMenuEnabled = true;
  bool _pageSummaryEnabled = true;
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
    _readingModeEnabled = _storage.getReadingModeEnabled();
    _selectionMenuEnabled = _storage.getSelectionMenuEnabled();
    _pageSummaryEnabled = _storage.getPageSummaryEnabled();
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
            16, 12, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(
                color: AppInk.hairline(isDark),
                width: AppStroke.hairline,
              ),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: const Text('无图模式',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text('拦截网页图片加载以节省流量',
                      style: TextStyle(
                          fontSize: 11.5, color: AppInk.tertiary(isDark))),
                  value: _blockImages,
                  activeThumbColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) async {
                    setState(() => _blockImages = val);
                    await _storage.saveBlockImages(val);
                  },
                ),
                Divider(
                  height: AppStroke.hairline,
                  thickness: AppStroke.hairline,
                  color: AppInk.hairline(isDark),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: const Text('JavaScript 脚本支持',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text('关闭可防弹窗，部分现代网页可能无法交互',
                      style: TextStyle(
                          fontSize: 11.5, color: AppInk.tertiary(isDark))),
                  value: _javaScriptEnabled,
                  activeThumbColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) async {
                    setState(() => _javaScriptEnabled = val);
                    await _storage.saveJavaScriptEnabled(val);
                  },
                ),
                Divider(
                  height: AppStroke.hairline,
                  thickness: AppStroke.hairline,
                  color: AppInk.hairline(isDark),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: const Text('默认电脑桌面版渲染',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text('新标签默认使用 PC 视口与 UA',
                      style: TextStyle(
                          fontSize: 11.5, color: AppInk.tertiary(isDark))),
                  value: _desktopMode,
                  activeThumbColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) async {
                    setState(() => _desktopMode = val);
                    await _storage.saveDesktopMode(val);
                  },
                ),
                Divider(
                  height: AppStroke.hairline,
                  thickness: AppStroke.hairline,
                  color: AppInk.hairline(isDark),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: const Text('触感反馈',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  value: _hapticsEnabled,
                  activeThumbColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) async {
                    setState(() => _hapticsEnabled = val);
                    HapticService.enabled = val;
                    await _storage.saveHapticsEnabled(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '阅读与摘要',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppInk.tertiary(isDark),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(
                color: AppInk.hairline(isDark),
                width: AppStroke.hairline,
              ),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: const Text('纯净阅读',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text('去除跳转横幅与遮罩，展开全文',
                      style: TextStyle(
                          fontSize: 11.5, color: AppInk.tertiary(isDark))),
                  value: _readingModeEnabled,
                  activeThumbColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) async {
                    setState(() => _readingModeEnabled = val);
                    await _storage.saveReadingModeEnabled(val);
                  },
                ),
                Divider(
                  height: AppStroke.hairline,
                  thickness: AppStroke.hairline,
                  color: AppInk.hairline(isDark),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: const Text('划词操作',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text('选中文字后弹出解释、翻译与追问',
                      style: TextStyle(
                          fontSize: 11.5, color: AppInk.tertiary(isDark))),
                  value: _selectionMenuEnabled,
                  activeThumbColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) async {
                    setState(() => _selectionMenuEnabled = val);
                    await _storage.saveSelectionMenuEnabled(val);
                  },
                ),
                Divider(
                  height: AppStroke.hairline,
                  thickness: AppStroke.hairline,
                  color: AppInk.hairline(isDark),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: const Text('页面总结',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text('菜单内显示 AI 速读入口（会产生模型调用）',
                      style: TextStyle(
                          fontSize: 11.5, color: AppInk.tertiary(isDark))),
                  value: _pageSummaryEnabled,
                  activeThumbColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) async {
                    setState(() => _pageSummaryEnabled = val);
                    await _storage.savePageSummaryEnabled(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(
                color: AppInk.hairline(isDark),
                width: AppStroke.hairline,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'User-Agent 请求标识',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Builder(builder: (context) {
                  final uaText = _uaController.text.trim();
                  String? matchedPreset;
                  String matchedLabel = '自定义 User-Agent';
                  for (final entry in AppConstants.userAgentPresets.entries) {
                    if (entry.value == uaText) {
                      matchedPreset = entry.value;
                      matchedLabel = entry.key;
                      break;
                    }
                  }
                  return OperonOptionRow<String?>(
                    title: '常用设备预设',
                    padding: EdgeInsets.zero,
                    value: matchedPreset,
                    valueLabel: matchedLabel,
                    options: [
                      for (final entry in AppConstants.userAgentPresets.entries)
                        OperonOptionItem<String?>(
                          value: entry.value,
                          label: entry.key,
                          subtitle: entry.value.isEmpty ? '使用系统默认标识' : entry.value,
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        _uaController.text = val;
                        _storage.saveUserAgent(val);
                        setState(() {});
                      }
                    },
                  );
                }),
                Divider(
                  height: 12,
                  thickness: AppStroke.hairline,
                  color: AppInk.hairline(isDark),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _uaController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: '自定义 User-Agent 字符串',
                  ),
                  onChanged: (val) {
                    _storage.saveUserAgent(val.trim());
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
