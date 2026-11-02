import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_script.dart';

class UserScriptService {
  static const String _keyScripts = 'pref_saved_user_scripts';
  static UserScriptService? _instance;
  late SharedPreferences _prefs;

  UserScriptService._();

  static Future<UserScriptService> getInstance() async {
    if (_instance == null) {
      _instance = UserScriptService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  /// Default starter script presets for instant utility
  static List<UserScript> getDefaultScripts() {
    return [
      UserScript(
        id: 'preset_zhihu_unlock',
        name: '知乎免登录与自动展开全文',
        description: '自动隐藏知乎移动端登录拦截浮层并展开被折叠的回答内容',
        matchPattern: '*zhihu.com*',
        code: '''
(() => {
  try {
    const cleanZhihu = () => {
      document.querySelectorAll('.Modal-wrapper, .signflow-modal, [class*="Modal-backdrop"]').forEach(el => el.remove());
      document.querySelectorAll('.ContentItem-expandButton, [class*="expandButton"]').forEach(btn => btn.click());
      document.documentElement.style.overflow = 'auto';
      document.body.style.overflow = 'auto';
    };
    cleanZhihu();
    setTimeout(cleanZhihu, 1000);
    setTimeout(cleanZhihu, 2500);
  } catch (e) {
    console.error('[UserScript: 知乎免登录]', e);
  }
})();
''',
        isEnabled: true,
        createdAt: DateTime.now(),
      ),
      UserScript(
        id: 'preset_general_anti_jump',
        name: '移动网页通用去遮挡',
        description: '自动移除常见的 app 下载浮条、遮罩并解除网页滚动锁定',
        matchPattern: '*',
        code: '''
(() => {
  try {
    const selectors = [
      '.openApp', '.open-app', '[class*="openApp"]', '[class*="download-app"]',
      '.bottom-bar-download', '.guide-app', '[class*="scheme-box"]'
    ];
    document.querySelectorAll(selectors.join(',')).forEach(el => el.remove());
    if (document.body) {
      document.body.style.overflow = 'auto';
    }
  } catch (e) {
    console.error('[UserScript: 通用去遮挡]', e);
  }
})();
''',
        isEnabled: false,
        createdAt: DateTime.now(),
      ),
      UserScript(
        id: 'preset_x_clean_sidebar',
        name: 'X (Twitter) 简化视图',
        description: '隐藏侧边栏的“推荐关注”等冗余卡片，保持推特界面纯净',
        matchPattern: '*twitter.com*, *x.com*',
        code: '''
(() => {
  try {
    const hideWidgets = () => {
      document.querySelectorAll('[aria-label*="Who to follow"], [aria-label*="推荐关注"], [data-testid="sidebarColumn"]').forEach(el => {
        el.style.display = 'none';
      });
    };
    hideWidgets();
    setTimeout(hideWidgets, 1200);
  } catch (e) {
    console.error('[UserScript: X 简化视图]', e);
  }
})();
''',
        isEnabled: false,
        createdAt: DateTime.now(),
      ),
    ];
  }

  /// Get all user scripts (initializes with defaults if empty)
  List<UserScript> getScripts() {
    final raw = _prefs.getStringList(_keyScripts);
    if (raw == null || raw.isEmpty) {
      final defaults = getDefaultScripts();
      saveScripts(defaults);
      return defaults;
    }

    return raw
        .map((item) {
          try {
            return UserScript.fromJson(jsonDecode(item));
          } catch (_) {
            return null;
          }
        })
        .whereType<UserScript>()
        .toList();
  }

  /// Save full list of user scripts
  Future<void> saveScripts(List<UserScript> scripts) async {
    final raw = scripts.map((s) => jsonEncode(s.toJson())).toList();
    await _prefs.setStringList(_keyScripts, raw);
  }

  /// Toggle single script enabled / disabled
  Future<void> toggleScript(String id, bool isEnabled) async {
    final scripts = getScripts();
    final index = scripts.indexWhere((s) => s.id == id);
    if (index != -1) {
      scripts[index] = scripts[index].copyWith(
        isEnabled: isEnabled,
        updatedAt: DateTime.now(),
      );
      await saveScripts(scripts);
    }
  }

  /// Save or update a single script
  Future<void> saveScript(UserScript script) async {
    final scripts = getScripts();
    final index = scripts.indexWhere((s) => s.id == script.id);
    if (index != -1) {
      scripts[index] = script.copyWith(updatedAt: DateTime.now());
    } else {
      scripts.insert(0, script);
    }
    await saveScripts(scripts);
  }

  /// Delete a single script
  Future<void> deleteScript(String id) async {
    final scripts = getScripts();
    scripts.removeWhere((s) => s.id == id);
    await saveScripts(scripts);
  }

  /// Reset to factory default scripts
  Future<void> resetToDefaults() async {
    final defaults = getDefaultScripts();
    await saveScripts(defaults);
  }
}
