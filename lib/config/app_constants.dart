class AppConstants {
  static const String appName = 'Operon Browser';
  static const String appSlogan = 'Don\'t just browse. Operate.';

  // Default User-Agents
  static const String uaAndroidChrome =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UD1A.231105.004) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.6613.127 Mobile Safari/537.36';

  static const String uaiOSSafari =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1';

  static const String uaDesktopChrome =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  static const Map<String, String> userAgentPresets = {
    'Android Chrome (Pixel 8) [推荐]': uaAndroidChrome,
    'iOS Safari (iPhone)': uaiOSSafari,
    'Desktop Chrome (PC)': uaDesktopChrome,
  };

  // Search Engine Presets
  static const Map<String, String> searchEngines = {
    'Baidu (百度)': 'https://www.baidu.com/s?wd=',
    'Google (谷歌)': 'https://www.google.com/search?q=',
    'Bing (必应)': 'https://www.bing.com/search?q=',
    'DuckDuckGo': 'https://duckduckgo.com/?q=',
  };
  static const String defaultSearchEngine = 'Google (谷歌)';

  // SharedPreferences Keys
  static const String keyBaseUrl = 'pref_llm_base_url';
  static const String keyApiKey = 'pref_llm_api_key';
  static const String keyModel = 'pref_llm_model';
  static const String keyTemperature = 'pref_llm_temp';
  static const String keyThinking = 'pref_llm_thinking';
  static const String keyMaxOutputTokens = 'pref_llm_max_tokens';
  static const String keyUserAgent = 'pref_user_agent';
  static const String keySafeMode = 'pref_safe_mode';
  static const String keyBackgroundTaskMode = 'pref_background_task_mode';
  static const String keyHomepage = 'pref_homepage';
  static const String keyThemeMode =
      'pref_theme_mode'; // 'system', 'light', 'dark'
  static const String keySearchEngine = 'pref_search_engine';
  static const String keyWebDarkMode = 'pref_web_dark_mode';
  static const String keyBlockImages = 'pref_block_images';
  static const String keyJavaScriptEnabled = 'pref_js_enabled';
  static const String keyDesktopMode = 'pref_desktop_mode';
  static const String keyTextZoom = 'pref_text_zoom';
  static const String keyHapticsEnabled = 'pref_haptics_enabled';
  static const String keyReadingModeEnabled = 'pref_reading_mode';
  static const String keySelectionMenuEnabled = 'pref_selection_menu';
  static const String keyPageSummaryEnabled = 'pref_page_summary';
  static const String keyRestoreTabs = 'pref_restore_tabs';
  static const String keySavedTabs = 'pref_saved_tabs';
  static const String keyAutoCompactEnabled = 'pref_auto_compact_enabled';
  static const String keyAutoCompactTokens = 'pref_auto_compact_tokens';

  /// First-run guidance has been completed or explicitly skipped.
  static const String keyOnboardingDone = 'pref_onboarding_done';
  static const int defaultAutoCompactTokens = 200000;

  // Default Homepage
  static const String defaultHomepage = 'operon://newtab';
}
