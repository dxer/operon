import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../services/storage_service.dart';
import '../../services/theme_service.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  late StorageService _storage;
  late ThemeService _themeService;
  bool _isLoading = true;

  ThemeMode _themeMode = ThemeMode.system;
  bool _webDarkMode = false;
  int _textZoom = 100;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    _themeService = await ThemeService.getInstance();

    _themeMode = _themeService.themeMode;
    _webDarkMode = _storage.getWebDarkMode();
    _textZoom = _storage.getTextZoom();
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
        title: const Text('外观与个性化'),
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
                  '应用主题模式',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '控制浏览器外壳、主页及菜单色彩',
                  style: TextStyle(fontSize: 12, color: AppTheme.neutralOf(isDark)),
                ),
                const SizedBox(height: 14),
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
                  onSelectionChanged: (Set<ThemeMode> newSelection) async {
                    final selected = newSelection.first;
                    setState(() => _themeMode = selected);
                    await _themeService.setThemeMode(selected);
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
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text('强制网页夜间模式 (Force Dark)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('对不支持深色主题的网页进行内核级智能反色渲染',
                  style: TextStyle(fontSize: 12, color: AppTheme.neutralOf(isDark))),
              value: _webDarkMode,
              activeThumbColor: AppTheme.primaryOf(isDark),
              onChanged: (val) async {
                setState(() => _webDarkMode = val);
                await _storage.saveWebDarkMode(val);
              },
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('网页字体大小缩放',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text('$_textZoom%',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryOf(isDark))),
                  ],
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _textZoom.toDouble(),
                  min: 50,
                  max: 200,
                  divisions: 15,
                  label: '$_textZoom%',
                  activeColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) {
                    setState(() => _textZoom = val.round());
                  },
                  onChangeEnd: (val) async {
                    await _storage.saveTextZoom(val.round());
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
