import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/app_constants.dart';
import 'package:operon/models/llm_config.dart';
import 'package:operon/services/secure_store.dart';
import 'package:operon/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('operon/secure_storage');
  late Map<String, String> vault;

  setUp(() {
    StorageService.resetForTest();
    vault = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? const {});
      final key = args['key'] as String? ?? '';
      switch (call.method) {
        case 'read':
          return vault[key];
        case 'write':
          vault[key] = args['value'] as String? ?? '';
          return true;
        case 'delete':
          vault.remove(key);
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    StorageService.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('migrates legacy plaintext API keys into SecureStore and strips prefs',
      () async {
    const legacyPreset = LlmPreset(
      id: 'p_1',
      name: 'DeepSeek',
      config: LlmConfig(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-preset-secret',
        model: 'deepseek-chat',
      ),
    );
    SharedPreferences.setMockInitialValues({
      AppConstants.keyBaseUrl: 'https://api.openai.com/v1',
      AppConstants.keyApiKey: 'sk-main-secret',
      AppConstants.keyModel: 'gpt-4o',
      'pref_llm_presets': jsonEncode([legacyPreset.toJson()]),
    });

    final storage = await StorageService.getInstance(
      secureStore: SecureStore(channel: channel, forceSupportedForTest: true),
    );

    // Keys remain seamlessly readable through StorageService.
    expect(storage.getLlmConfig().apiKey, 'sk-main-secret');
    final presets = storage.getLlmPresets();
    expect(presets, hasLength(1));
    expect(presets.first.config.apiKey, 'sk-preset-secret');

    // Vault holds both keys while SharedPreferences no longer stores plaintext.
    expect(vault[AppConstants.keyApiKey], 'sk-main-secret');
    expect(vault['preset_api_key_p_1'], 'sk-preset-secret');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(AppConstants.keyApiKey), false);
    final rawPresets = jsonDecode(prefs.getString('pref_llm_presets')!) as List;
    expect((rawPresets.first as Map)['config']['apiKey'], '');

    // Cold restart reloads from SecureStore.
    StorageService.resetForTest();
    final restarted = await StorageService.getInstance(
      secureStore: SecureStore(channel: channel, forceSupportedForTest: true),
    );
    expect(restarted.getLlmConfig().apiKey, 'sk-main-secret');
    expect(restarted.getLlmPresets().first.config.apiKey, 'sk-preset-secret');
  });

  test('persists and restores tab sessions while honoring restore toggle',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.getInstance(
      secureStore: SecureStore(channel: channel, forceSupportedForTest: true),
    );

    expect(storage.getRestoreTabsEnabled(), true);
    expect(storage.getSavedTabSession(), isNull);

    await storage.saveTabSession(
      const [
        SavedTabSnapshot(url: 'https://example.com', title: 'Example'),
        SavedTabSnapshot(
          url: 'https://flutter.dev',
          title: 'Flutter',
          isDesktopMode: true,
        ),
      ],
      1,
    );

    final restored = storage.getSavedTabSession();
    expect(restored, isNotNull);
    expect(restored!.activeIndex, 1);
    expect(restored.tabs, hasLength(2));
    expect(restored.tabs[0].url, 'https://example.com');
    expect(restored.tabs[1].isDesktopMode, true);

    await storage.saveRestoreTabsEnabled(false);
    expect(storage.getRestoreTabsEnabled(), false);
    expect(storage.getSavedTabSession(), isNull);
  });
}
