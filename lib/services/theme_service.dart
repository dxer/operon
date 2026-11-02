import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_constants.dart';
import '../config/app_theme.dart';
import 'storage_service.dart';

class ThemeService extends ChangeNotifier {
  static ThemeService? _instance;
  ThemeMode _themeMode = ThemeMode.system;

  ThemeService._();

  static Future<ThemeService> getInstance() async {
    if (_instance == null) {
      _instance = ThemeService._();
      await _instance!._loadTheme();
    }
    return _instance!;
  }

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    // System
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  Future<void> _loadTheme() async {
    final storage = await StorageService.getInstance();
    final modeStr = storage.getThemeMode();
    switch (modeStr) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      default:
        _themeMode = ThemeMode.system;
        break;
    }
    _updateSystemOverlay();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final storage = await StorageService.getInstance();
    String modeStr = 'system';
    if (mode == ThemeMode.light) modeStr = 'light';
    if (mode == ThemeMode.dark) modeStr = 'dark';
    await storage.saveThemeMode(modeStr);

    _updateSystemOverlay();
    notifyListeners();
  }

  void _updateSystemOverlay() {
    final dark = isDarkMode;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: dark ? AppTheme.darkBg : AppTheme.lightBg,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
    );
  }
}
