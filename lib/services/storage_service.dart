import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_constants.dart';
import '../models/llm_config.dart';
import '../models/history_item.dart';
import '../models/bookmark_item.dart';
import '../models/agent_task_record.dart';
import '../models/skill_run.dart';

class StorageService {
  static StorageService? _instance;
  late SharedPreferences _prefs;

  StorageService._();

  static Future<StorageService> getInstance() async {
    if (_instance == null) {
      _instance = StorageService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  // LLM Config
  LlmConfig getLlmConfig() {
    final baseUrl = _prefs.getString(AppConstants.keyBaseUrl) ??
        'https://api.deepseek.com/v1';
    final apiKey = _prefs.getString(AppConstants.keyApiKey) ?? '';
    final model = _prefs.getString(AppConstants.keyModel) ?? 'deepseek-chat';
    final temp = _prefs.getDouble(AppConstants.keyTemperature) ?? 0.1;

    return LlmConfig(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      temperature: temp,
    );
  }

  Future<void> saveLlmConfig(LlmConfig config) async {
    await _prefs.setString(AppConstants.keyBaseUrl, config.baseUrl);
    await _prefs.setString(AppConstants.keyApiKey, config.apiKey);
    await _prefs.setString(AppConstants.keyModel, config.model);
    await _prefs.setDouble(AppConstants.keyTemperature, config.temperature);
  }

  // User-Agent
  String getUserAgent() {
    return _prefs.getString(AppConstants.keyUserAgent) ??
        AppConstants.uaAndroidChrome;
  }

  Future<void> saveUserAgent(String ua) async {
    await _prefs.setString(AppConstants.keyUserAgent, ua);
  }

  // Max Steps
  int getMaxSteps() {
    return _prefs.getInt(AppConstants.keyMaxSteps) ?? 15;
  }

  Future<void> saveMaxSteps(int steps) async {
    await _prefs.setInt(AppConstants.keyMaxSteps, steps);
  }

  // Safe Mode (Human confirmation before post/tweet)
  bool getSafeMode() {
    return _prefs.getBool(AppConstants.keySafeMode) ?? true;
  }

  Future<void> saveSafeMode(bool enabled) async {
    await _prefs.setBool(AppConstants.keySafeMode, enabled);
  }

  // Homepage
  String getHomepage() {
    return _prefs.getString(AppConstants.keyHomepage) ??
        AppConstants.defaultHomepage;
  }

  Future<void> saveHomepage(String url) async {
    await _prefs.setString(AppConstants.keyHomepage, url);
  }

  // Theme Mode ('system', 'light', 'dark')
  String getThemeMode() {
    return _prefs.getString(AppConstants.keyThemeMode) ?? 'dark';
  }

  Future<void> saveThemeMode(String mode) async {
    await _prefs.setString(AppConstants.keyThemeMode, mode);
  }

  // Search Engine Name
  String getSearchEngine() {
    return _prefs.getString(AppConstants.keySearchEngine) ??
        AppConstants.defaultSearchEngine;
  }

  Future<void> saveSearchEngine(String name) async {
    await _prefs.setString(AppConstants.keySearchEngine, name);
  }

  // Web Dark Mode (force dark on web pages)
  bool getWebDarkMode() {
    return _prefs.getBool(AppConstants.keyWebDarkMode) ?? false;
  }

  Future<void> saveWebDarkMode(bool enabled) async {
    await _prefs.setBool(AppConstants.keyWebDarkMode, enabled);
  }

  // Block Images / Save Data Mode
  bool getBlockImages() {
    return _prefs.getBool(AppConstants.keyBlockImages) ?? false;
  }

  Future<void> saveBlockImages(bool blocked) async {
    await _prefs.setBool(AppConstants.keyBlockImages, blocked);
  }

  // JavaScript Enabled
  bool getJavaScriptEnabled() {
    return _prefs.getBool(AppConstants.keyJavaScriptEnabled) ?? true;
  }

  Future<void> saveJavaScriptEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.keyJavaScriptEnabled, enabled);
  }

  // Default Desktop Mode
  bool getDesktopMode() {
    return _prefs.getBool(AppConstants.keyDesktopMode) ?? false;
  }

  Future<void> saveDesktopMode(bool desktop) async {
    await _prefs.setBool(AppConstants.keyDesktopMode, desktop);
  }

  // UI Haptics
  bool getHapticsEnabled() {
    return _prefs.getBool(AppConstants.keyHapticsEnabled) ?? true;
  }

  Future<void> saveHapticsEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.keyHapticsEnabled, enabled);
  }

  // Text Zoom (percentage: 100 is default)
  int getTextZoom() {
    return _prefs.getInt(AppConstants.keyTextZoom) ?? 100;
  }

  Future<void> saveTextZoom(int zoom) async {
    await _prefs.setInt(AppConstants.keyTextZoom, zoom);
  }

  // --- History Management ---
  static const String _keyHistory = 'browser_history_list';
  static const int _maxHistoryCount = 300;

  List<HistoryItem> getHistory() {
    final raw = _prefs.getStringList(_keyHistory) ?? [];
    final list = <HistoryItem>[];
    for (final s in raw) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        list.add(HistoryItem.fromJson(map));
      } catch (_) {}
    }
    return list;
  }

  Future<void> addHistoryItem(HistoryItem item) async {
    final list = getHistory();
    // Remove existing with same URL to bump to top
    list.removeWhere((h) => h.url == item.url);
    list.insert(0, item);
    if (list.length > _maxHistoryCount) {
      list.removeRange(_maxHistoryCount, list.length);
    }
    final raw = list.map((h) => jsonEncode(h.toJson())).toList();
    await _prefs.setStringList(_keyHistory, raw);
  }

  Future<void> removeHistoryItem(String id) async {
    final list = getHistory();
    list.removeWhere((h) => h.id == id);
    final raw = list.map((h) => jsonEncode(h.toJson())).toList();
    await _prefs.setStringList(_keyHistory, raw);
  }

  Future<void> clearHistory() async {
    await _prefs.remove(_keyHistory);
  }

  // --- Bookmarks Management ---
  static const String _keyBookmarks = 'browser_bookmarks_list';

  List<BookmarkItem> getBookmarks() {
    final raw = _prefs.getStringList(_keyBookmarks) ?? [];
    final list = <BookmarkItem>[];
    for (final s in raw) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        list.add(BookmarkItem.fromJson(map));
      } catch (_) {}
    }
    return list;
  }

  Future<void> addBookmark(BookmarkItem item) async {
    final list = getBookmarks();
    list.removeWhere((b) => b.url == item.url);
    list.insert(0, item);
    final raw = list.map((b) => jsonEncode(b.toJson())).toList();
    await _prefs.setStringList(_keyBookmarks, raw);
  }

  Future<void> removeBookmark(String urlOrId) async {
    final list = getBookmarks();
    list.removeWhere((b) => b.id == urlOrId || b.url == urlOrId);
    final raw = list.map((b) => jsonEncode(b.toJson())).toList();
    await _prefs.setStringList(_keyBookmarks, raw);
  }

  bool isBookmarked(String url) {
    if (url.isEmpty || url == 'about:blank') return false;
    final list = getBookmarks();
    return list.any((b) => b.url == url);
  }

  // --- Shortcuts Management (Via-Style Start Page) ---
  static const String _keyShortcuts = 'browser_custom_shortcuts';

  static final List<Map<String, String>> _defaultShortcuts = [
    {'title': 'X', 'url': 'https://x.com'},
    {'title': 'Google', 'url': 'https://www.google.com'},
    {'title': 'GitHub', 'url': 'https://github.com'},
    {'title': 'Bilibili', 'url': 'https://www.bilibili.com'},
    {'title': 'Wikipedia', 'url': 'https://wikipedia.org'},
    {'title': 'Reddit', 'url': 'https://reddit.com'},
    {'title': 'Bing', 'url': 'https://www.bing.com'},
  ];

  List<Map<String, String>> getShortcuts() {
    final raw = _prefs.getStringList(_keyShortcuts);
    if (raw == null || raw.isEmpty) return List.from(_defaultShortcuts);
    final list = <Map<String, String>>[];
    for (final s in raw) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        list.add({
          'title': map['title']?.toString() ?? '',
          'url': map['url']?.toString() ?? '',
        });
      } catch (_) {}
    }
    return list.isEmpty ? List.from(_defaultShortcuts) : list;
  }

  Future<void> saveShortcuts(List<Map<String, String>> list) async {
    final raw = list.map((m) => jsonEncode(m)).toList();
    await _prefs.setStringList(_keyShortcuts, raw);
  }

  // --- Agent Task History & Audit ---
  static const String _keyAgentTaskHistory = 'agent_task_history';
  static const int _maxAgentTaskRecords = 50;

  List<AgentTaskRecord> getAgentTaskHistory() {
    final raw = _prefs.getStringList(_keyAgentTaskHistory) ?? [];
    final list = <AgentTaskRecord>[];
    for (final s in raw) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        list.add(AgentTaskRecord.fromJson(map));
      } catch (_) {}
    }
    return list;
  }

  Future<void> addAgentTaskRecord(AgentTaskRecord record) async {
    final list = getAgentTaskHistory();
    list.removeWhere((r) => r.id == record.id);
    list.insert(0, record);
    if (list.length > _maxAgentTaskRecords) {
      list.removeRange(_maxAgentTaskRecords, list.length);
    }
    final raw = list.map((r) => jsonEncode(r.toJson())).toList();
    await _prefs.setStringList(_keyAgentTaskHistory, raw);
  }

  Future<void> removeAgentTaskRecord(String id) async {
    final list = getAgentTaskHistory()..removeWhere((r) => r.id == id);
    final raw = list.map((r) => jsonEncode(r.toJson())).toList();
    await _prefs.setStringList(_keyAgentTaskHistory, raw);
  }

  Future<void> clearAgentTaskHistory() async {
    await _prefs.remove(_keyAgentTaskHistory);
  }

  // --- Per-site authorization allowlist ---
  static const String _keyAgentAllowedSites = 'agent_allowed_sites';

  String _normalizeAgentHost(String raw) {
    var host = raw.trim().toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  List<String> getAgentAllowedSites() {
    return List<String>.from(
        _prefs.getStringList(_keyAgentAllowedSites) ?? const []);
  }

  bool isAgentSiteAllowed(String host) {
    final normalized = _normalizeAgentHost(host);
    if (normalized.isEmpty) return false;
    return getAgentAllowedSites().contains(normalized);
  }

  Future<void> addAgentAllowedSite(String host) async {
    final normalized = _normalizeAgentHost(host);
    if (normalized.isEmpty) return;
    final sites = getAgentAllowedSites();
    if (!sites.contains(normalized)) {
      sites.add(normalized);
      await _prefs.setStringList(_keyAgentAllowedSites, sites);
    }
  }

  Future<void> removeAgentAllowedSite(String host) async {
    final normalized = _normalizeAgentHost(host);
    final sites = getAgentAllowedSites()..remove(normalized);
    await _prefs.setStringList(_keyAgentAllowedSites, sites);
  }

  Future<void> clearAgentAllowedSites() async {
    await _prefs.remove(_keyAgentAllowedSites);
  }

  // --- Skill Run History ---
  static const String _keySkillRuns = 'skill_run_history';
  static const int _maxSkillRuns = 50;

  List<SkillRunRecord> getSkillRuns() {
    final raw = _prefs.getStringList(_keySkillRuns) ?? [];
    final list = <SkillRunRecord>[];
    for (final entry in raw) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        list.add(SkillRunRecord.fromJson(map));
      } catch (_) {}
    }
    return list;
  }

  Future<void> addSkillRun(SkillRunRecord record) async {
    final list = getSkillRuns();
    list.removeWhere((item) => item.id == record.id);
    list.insert(0, record);
    if (list.length > _maxSkillRuns) {
      list.removeRange(_maxSkillRuns, list.length);
    }
    final raw = list.map((item) => jsonEncode(item.toJson())).toList();
    await _prefs.setStringList(_keySkillRuns, raw);
  }

  Future<void> removeSkillRun(String id) async {
    final list = getSkillRuns()..removeWhere((item) => item.id == id);
    final raw = list.map((item) => jsonEncode(item.toJson())).toList();
    await _prefs.setStringList(_keySkillRuns, raw);
  }

  Future<void> clearSkillRuns() async {
    await _prefs.remove(_keySkillRuns);
  }
}
