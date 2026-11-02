import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_constants.dart';
import '../models/llm_config.dart';

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
    final baseUrl = _prefs.getString(AppConstants.keyBaseUrl) ?? 'https://api.deepseek.com/v1';
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
    return _prefs.getString(AppConstants.keyUserAgent) ?? AppConstants.uaAndroidChrome;
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
    return _prefs.getString(AppConstants.keyHomepage) ?? AppConstants.defaultHomepage;
  }

  Future<void> saveHomepage(String url) async {
    await _prefs.setString(AppConstants.keyHomepage, url);
  }
}
