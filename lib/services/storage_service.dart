import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_constants.dart';
import '../models/llm_config.dart';
import '../models/model_profile.dart';
import '../models/history_item.dart';
import '../models/bookmark_item.dart';
import '../models/agent_prompt.dart';
import 'secure_store.dart';

class SavedTabSnapshot {
  const SavedTabSnapshot({
    required this.url,
    this.title = '新标签页',
    this.isDesktopMode = false,
  });

  final String url;
  final String title;
  final bool isDesktopMode;

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'isDesktopMode': isDesktopMode,
      };

  factory SavedTabSnapshot.fromJson(Map<String, dynamic> json) =>
      SavedTabSnapshot(
        url: json['url']?.toString() ?? AppConstants.defaultHomepage,
        title: json['title']?.toString() ?? '新标签页',
        isDesktopMode: json['isDesktopMode'] as bool? ?? false,
      );
}

class SavedTabSession {
  const SavedTabSession({required this.tabs, required this.activeIndex});

  final List<SavedTabSnapshot> tabs;
  final int activeIndex;
}

class StorageService {
  static StorageService? _instance;
  late SharedPreferences _prefs;
  late SecureStore _secureStore;
  String? _cachedApiKey;
  final Map<String, String> _cachedPresetKeys = <String, String>{};

  StorageService._();

  static Future<StorageService> getInstance({SecureStore? secureStore}) async {
    if (_instance == null) {
      final instance = StorageService._();
      instance._prefs = await SharedPreferences.getInstance();
      instance._secureStore = secureStore ?? SecureStore.instance;
      await instance._hydrateSecrets();
      _instance = instance;
    }
    return _instance!;
  }

  /// Drops the cached instance so a caller can start from clean preferences.
  ///
  /// Used by tests that need two "app starts" in one process.
  static void resetForTest() => _instance = null;

  static String _presetKeySlot(String id) => 'preset_api_key_$id';

  Future<void> _hydrateSecrets() async {
    final storedKey = await _secureStore.read(AppConstants.keyApiKey);
    if (_secureStore.isSupported) {
      if (storedKey != null && storedKey.isNotEmpty) {
        _cachedApiKey = storedKey;
        if (_prefs.containsKey(AppConstants.keyApiKey)) {
          await _prefs.remove(AppConstants.keyApiKey);
        }
      } else {
        final legacy = _prefs.getString(AppConstants.keyApiKey) ?? '';
        _cachedApiKey = legacy;
        if (legacy.isNotEmpty) {
          final written =
              await _secureStore.write(AppConstants.keyApiKey, legacy);
          if (written) {
            await _prefs.remove(AppConstants.keyApiKey);
          }
        }
      }
    } else {
      _cachedApiKey = _prefs.getString(AppConstants.keyApiKey) ?? '';
    }

    final rawPresets = _readRawPresets();
    var presetsDirty = false;
    final sanitized = <LlmPreset>[];
    for (final preset in rawPresets) {
      final slot = _presetKeySlot(preset.id);
      if (_secureStore.isSupported) {
        if (preset.config.apiKey.isNotEmpty) {
          final written =
              await _secureStore.write(slot, preset.config.apiKey);
          _cachedPresetKeys[preset.id] = preset.config.apiKey;
          if (written) {
            presetsDirty = true;
            sanitized.add(
              preset.copyWith(config: preset.config.copyWith(apiKey: '')),
            );
            continue;
          }
        } else {
          final secret = await _secureStore.read(slot);
          if (secret != null && secret.isNotEmpty) {
            _cachedPresetKeys[preset.id] = secret;
          }
        }
      } else if (preset.config.apiKey.isNotEmpty) {
        _cachedPresetKeys[preset.id] = preset.config.apiKey;
      }
      sanitized.add(preset);
    }
    if (presetsDirty) {
      await _writeRawPresets(sanitized);
    }
  }

  // LLM Config
  LlmConfig getLlmConfig() {
    final baseUrl = _prefs.getString(AppConstants.keyBaseUrl) ?? '';
    final apiKey = _secureStore.isSupported
        ? (_cachedApiKey ?? '')
        : (_prefs.getString(AppConstants.keyApiKey) ?? '');
    final model = _prefs.getString(AppConstants.keyModel) ?? '';
    final temp = _prefs.getDouble(AppConstants.keyTemperature) ?? 0.1;
    final thinkingName = _prefs.getString(AppConstants.keyThinking);
    final maxTokens = _prefs.getInt(AppConstants.keyMaxOutputTokens);

    return LlmConfig(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      temperature: temp,
      thinking: ThinkingLevel.values.firstWhere(
        (level) => level.name == thinkingName,
        orElse: () => ThinkingLevel.auto,
      ),
      maxOutputTokens: maxTokens,
    );
  }

  Future<void> saveLlmConfig(LlmConfig config) async {
    await _prefs.setString(AppConstants.keyBaseUrl, config.baseUrl);
    _cachedApiKey = config.apiKey;
    final storedSecurely = config.apiKey.isEmpty
        ? await _secureStore.delete(AppConstants.keyApiKey)
        : await _secureStore.write(AppConstants.keyApiKey, config.apiKey);
    if (storedSecurely) {
      await _prefs.remove(AppConstants.keyApiKey);
    } else {
      await _prefs.setString(AppConstants.keyApiKey, config.apiKey);
    }
    await _prefs.setString(AppConstants.keyModel, config.model);
    await _prefs.setDouble(AppConstants.keyTemperature, config.temperature);
    await _prefs.setString(AppConstants.keyThinking, config.thinking.name);
    final maxTokens = config.maxOutputTokens;
    if (maxTokens == null) {
      await _prefs.remove(AppConstants.keyMaxOutputTokens);
    } else {
      await _prefs.setInt(AppConstants.keyMaxOutputTokens, maxTokens);
    }
  }

  // Named LLM presets for one-tap switching between providers/models.
  static const String _keyLlmPresets = 'pref_llm_presets';

  List<LlmPreset> _readRawPresets() {
    final raw = _prefs.getString(_keyLlmPresets);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => LlmPreset.fromJson(Map<String, dynamic>.from(item)))
          .where((preset) => preset.id.isNotEmpty && preset.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeRawPresets(List<LlmPreset> presets) async {
    await _prefs.setString(
      _keyLlmPresets,
      jsonEncode([for (final item in presets) item.toJson()]),
    );
  }

  List<LlmPreset> getLlmPresets() {
    final raw = _readRawPresets();
    if (!_secureStore.isSupported) return raw;
    return [
      for (final preset in raw)
        preset.copyWith(
          config: preset.config.copyWith(
            apiKey: _cachedPresetKeys[preset.id] ?? preset.config.apiKey,
          ),
        ),
    ];
  }

  Future<void> saveLlmPreset(LlmPreset preset) async {
    var storedPreset = preset;
    if (preset.config.apiKey.isEmpty) {
      _cachedPresetKeys.remove(preset.id);
      await _secureStore.delete(_presetKeySlot(preset.id));
    } else {
      _cachedPresetKeys[preset.id] = preset.config.apiKey;
      final storedSecurely = await _secureStore.write(
        _presetKeySlot(preset.id),
        preset.config.apiKey,
      );
      if (storedSecurely) {
        storedPreset = preset.copyWith(
          config: preset.config.copyWith(apiKey: ''),
        );
      }
    }

    final presets = List<LlmPreset>.from(_readRawPresets());
    final index = presets.indexWhere((item) => item.id == preset.id);
    if (index >= 0) {
      presets[index] = storedPreset;
    } else {
      presets.add(storedPreset);
    }
    await _writeRawPresets(presets);
  }

  Future<void> deleteLlmPreset(String id) async {
    _cachedPresetKeys.remove(id);
    await _secureStore.delete(_presetKeySlot(id));
    final presets = _readRawPresets()
        .where((item) => item.id != id)
        .toList(growable: false);
    await _writeRawPresets(presets);
  }

  // Model capability profiles, keyed by `baseUrl|model`.

  static const String _keyModelProfiles = 'pref_model_profiles';

  static String modelProfileKey(LlmConfig config) =>
      '${config.baseUrl.trim()}|${config.model.trim()}';

  Map<String, dynamic> _rawModelProfiles() {
    final raw = _prefs.getString(_keyModelProfiles);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      // A corrupt blob is not worth failing the settings page over.
      return {};
    }
  }

  /// What the user has said about this model, or the defaults.
  ModelProfile getModelProfile(LlmConfig config) {
    final entry = _rawModelProfiles()[modelProfileKey(config)];
    if (entry is Map) {
      return ModelProfile.fromJson(Map<String, dynamic>.from(entry));
    }
    return const ModelProfile();
  }

  Future<void> saveModelProfile(LlmConfig config, ModelProfile profile) async {
    final all = _rawModelProfiles();
    all[modelProfileKey(config)] = profile.toJson();
    await _prefs.setString(_keyModelProfiles, jsonEncode(all));
  }

  // User-Agent
  String getUserAgent() {
    return _prefs.getString(AppConstants.keyUserAgent) ??
        AppConstants.uaAndroidChrome;
  }

  Future<void> saveUserAgent(String ua) async {
    await _prefs.setString(AppConstants.keyUserAgent, ua);
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

  /// The three reading features, each independent.
  ///
  /// They are on by default: a fresh install should feel complete, and a user
  /// who does not care about one of them never has to touch it. Turning one off
  /// removes its entry point as well as its behaviour, so nothing silently
  /// keeps running in the background.
  bool getReadingModeEnabled() =>
      _prefs.getBool(AppConstants.keyReadingModeEnabled) ?? true;

  Future<void> saveReadingModeEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.keyReadingModeEnabled, enabled);
  }

  bool getSelectionMenuEnabled() =>
      _prefs.getBool(AppConstants.keySelectionMenuEnabled) ?? true;

  Future<void> saveSelectionMenuEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.keySelectionMenuEnabled, enabled);
  }

  bool getPageSummaryEnabled() =>
      _prefs.getBool(AppConstants.keyPageSummaryEnabled) ?? true;

  Future<void> savePageSummaryEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.keyPageSummaryEnabled, enabled);
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

  // --- Saved prompts ("shortcuts") for the composer ---

  static const String _keyAgentPrompts = 'pref_agent_prompts';

  List<AgentPrompt> getAgentPrompts() {
    final raw = _prefs.getStringList(_keyAgentPrompts) ?? const [];
    final list = <AgentPrompt>[];
    for (final entry in raw) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        final prompt = AgentPrompt.fromJson(map);
        if (prompt.goal.trim().isNotEmpty) list.add(prompt);
      } catch (_) {
        // One corrupt entry must not hide the others.
      }
    }
    return list;
  }

  Future<void> saveAgentPrompts(List<AgentPrompt> prompts) async {
    final raw = [for (final prompt in prompts) jsonEncode(prompt.toJson())];
    await _prefs.setStringList(_keyAgentPrompts, raw);
  }

  // --- What the agent should always remember ---

  static const String _keyAgentMemory = 'pref_agent_memory';

  /// A note the user wants in every task: who they are, how they like answers.
  /// Empty means nothing is sent, which is the honest default.
  String getAgentMemory() => _prefs.getString(_keyAgentMemory) ?? '';

  Future<void> saveAgentMemory(String memory) async {
    final trimmed = memory.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(_keyAgentMemory);
      return;
    }
    await _prefs.setString(_keyAgentMemory, trimmed);
  }

  // --- Per-site authorization allowlist ---
  static const String _keyAgentAllowedSites = 'agent_allowed_sites';

  /// One stored shape for a site: bare host, lower case, no `www.`, no port.
  ///
  /// Accepts whatever a user pastes (a whole URL, a host with a port) and
  /// whatever the caller has at hand, so a rule written one way still matches a
  /// page seen another way.
  String _normalizeAgentHost(String raw) {
    var host = raw.trim().toLowerCase();
    final scheme = host.indexOf('://');
    if (scheme >= 0) host = host.substring(scheme + 3);
    final slash = host.indexOf('/');
    if (slash >= 0) host = host.substring(0, slash);
    final query = host.indexOf('?');
    if (query >= 0) host = host.substring(0, query);
    final colon = host.indexOf(':');
    if (colon >= 0) host = host.substring(0, colon);
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

  // --- Per-site blocklist: the agent may not touch these at all ---
  static const String _keyAgentBlockedSites = 'agent_blocked_sites';

  List<String> getAgentBlockedSites() {
    return List<String>.from(
        _prefs.getStringList(_keyAgentBlockedSites) ?? const []);
  }

  bool isAgentSiteBlocked(String host) {
    final normalized = _normalizeAgentHost(host);
    if (normalized.isEmpty) return false;
    return getAgentBlockedSites().contains(normalized);
  }

  Future<void> addAgentBlockedSite(String host) async {
    final normalized = _normalizeAgentHost(host);
    if (normalized.isEmpty) return;
    final sites = getAgentBlockedSites();
    if (sites.contains(normalized)) return;
    sites.add(normalized);
    await _prefs.setStringList(_keyAgentBlockedSites, sites);
    // A site cannot be both: blocking is the stronger statement, and leaving it
    // on the allow list would make the next card offer to waive it again.
    await removeAgentAllowedSite(normalized);
  }

  Future<void> removeAgentBlockedSite(String host) async {
    final normalized = _normalizeAgentHost(host);
    final sites = getAgentBlockedSites()..remove(normalized);
    await _prefs.setStringList(_keyAgentBlockedSites, sites);
  }

  Future<void> clearAgentBlockedSites() async {
    await _prefs.remove(_keyAgentBlockedSites);
  }

  Future<void> clearAgentAllowedSites() async {
    await _prefs.remove(_keyAgentAllowedSites);
  }

  // --- Tab session persistence ---
  bool getRestoreTabsEnabled() =>
      _prefs.getBool(AppConstants.keyRestoreTabs) ?? true;

  Future<void> saveRestoreTabsEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.keyRestoreTabs, enabled);
    if (!enabled) {
      await _prefs.remove(AppConstants.keySavedTabs);
    }
  }

  SavedTabSession? getSavedTabSession() {
    if (!getRestoreTabsEnabled()) return null;
    final raw = _prefs.getString(AppConstants.keySavedTabs);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final list = decoded['tabs'];
      if (list is! List || list.isEmpty) return null;
      final tabs = list
          .whereType<Map>()
          .map((item) =>
              SavedTabSnapshot.fromJson(Map<String, dynamic>.from(item)))
          .where((t) => t.url.isNotEmpty)
          .toList();
      if (tabs.isEmpty) return null;
      final active = (decoded['activeIndex'] as num?)?.toInt() ?? 0;
      return SavedTabSession(
        tabs: tabs,
        activeIndex: active.clamp(0, tabs.length - 1),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTabSession(
    List<SavedTabSnapshot> tabs,
    int activeIndex,
  ) async {
    if (!getRestoreTabsEnabled()) return;
    if (tabs.isEmpty) {
      await _prefs.remove(AppConstants.keySavedTabs);
      return;
    }
    await _prefs.setString(
      AppConstants.keySavedTabs,
      jsonEncode({
        'activeIndex': activeIndex.clamp(0, tabs.length - 1),
        'tabs': [for (final t in tabs) t.toJson()],
      }),
    );
  }

  // --- Auto-Compact settings ---

  bool getAutoCompactEnabled() =>
      _prefs.getBool(AppConstants.keyAutoCompactEnabled) ?? true;

  Future<void> saveAutoCompactEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.keyAutoCompactEnabled, enabled);
  }

  int getAutoCompactTokens() {
    final stored = _prefs.getInt(AppConstants.keyAutoCompactTokens);
    if (stored == null || stored < 8000) {
      return AppConstants.defaultAutoCompactTokens;
    }
    return stored;
  }

  Future<void> saveAutoCompactTokens(int tokens) async {
    final safe = tokens < 8000 ? 8000 : tokens;
    await _prefs.setInt(AppConstants.keyAutoCompactTokens, safe);
  }
}
