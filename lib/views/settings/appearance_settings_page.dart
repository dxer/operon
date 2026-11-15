import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../config/app_tokens.dart';
import '../../services/storage_service.dart';
import '../../services/theme_service.dart';
import '../widgets/operon_list_row.dart';

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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OperonOptionRow<ThemeMode>(
                  title: '主题切换',
                  value: _themeMode,
                  options: const [
                    OperonOptionItem<ThemeMode>(
                      value: ThemeMode.system,
                      label: '跟随系统',
                      icon: Icons.brightness_auto_rounded,
                    ),
                    OperonOptionItem<ThemeMode>(
                      value: ThemeMode.light,
                      label: '浅色模式',
                      icon: Icons.light_mode_rounded,
                    ),
                    OperonOptionItem<ThemeMode>(
                      value: ThemeMode.dark,
                      label: '暗色模式',
                      icon: Icons.dark_mode_rounded,
                    ),
                  ],
                  onChanged: (selected) async {
                    setState(() => _themeMode = selected);
                    await _themeService.setThemeMode(selected);
                  },
                ),
                Divider(
                  height: 1,
                  thickness: AppStroke.hairline,
                  indent: 14,
                  endIndent: 14,
                  color: AppInk.hairline(isDark),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: const Text('强制网页夜间模式',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text('对不支持深色的网页启用内核级反色',
                      style: TextStyle(
                          fontSize: 11.5, color: AppInk.tertiary(isDark))),
                  value: _webDarkMode,
                  activeThumbColor: AppTheme.primaryOf(isDark),
                  onChanged: (val) async {
                    setState(() => _webDarkMode = val);
                    await _storage.saveWebDarkMode(val);
                  },
                ),
                Divider(
                  height: 1,
                  thickness: AppStroke.hairline,
                  indent: 14,
                  endIndent: 14,
                  color: AppInk.hairline(isDark),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('网页字体大小缩放',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                          Text('$_textZoom%',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                  color: AppTheme.primaryOf(isDark))),
                        ],
                      ),
                      const SizedBox(height: 6),
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
          ),
        ],
      ),
    );
  }
}
