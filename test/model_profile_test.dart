import 'package:flutter_test/flutter_test.dart';
import 'package:operon/agent/context.dart';
import 'package:operon/models/llm_config.dart';
import 'package:operon/models/model_profile.dart';
import 'package:operon/services/llm_service.dart';
import 'package:operon/services/llm_tools.dart';
import 'package:operon/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_openai.dart';

/// A model profile is the app's only source of truth about what a model can do.
/// Before it existed every one of those answers was a guess baked into code.

void main() {
  group('the profile itself', () {
    test('a fresh profile says nothing it does not know', () {
      const profile = ModelProfile();
      expect(profile.contextWindow, 32000);
      expect(profile.vision, ModelTrait.auto);
      expect(profile.reasoning, ModelTrait.auto);
      expect(profile.supportsTools, isTrue);
      expect(profile.isDefault, isTrue);
    });

    test('auto keeps the name heuristic, and the user can override both ways', () {
      const auto = ModelProfile();
      expect(auto.visionFor('gpt-4o'), isTrue);
      expect(auto.visionFor('deepseek-chat'), isFalse);

      const yes = ModelProfile(vision: ModelTrait.yes);
      expect(yes.visionFor('some-local-model'), isTrue,
          reason: 'the user knows their own model');

      const no = ModelProfile(vision: ModelTrait.no);
      expect(no.visionFor('gpt-4o'), isFalse,
          reason: 'an explicit no beats the name heuristic');
    });

    test('only an explicit no forbids reasoning_effort', () {
      expect(const ModelProfile().reasoningAllowed, isTrue);
      expect(const ModelProfile(reasoning: ModelTrait.yes).reasoningAllowed, isTrue);
      expect(const ModelProfile(reasoning: ModelTrait.no).reasoningAllowed, isFalse);
    });

    test('survives json, including a nonsense window', () {
      const profile = ModelProfile(
        contextWindow: 200000,
        vision: ModelTrait.yes,
        reasoning: ModelTrait.no,
        supportsTools: false,
      );
      final back = ModelProfile.fromJson(Map<String, dynamic>.from(profile.toJson()));
      expect(back.contextWindow, 200000);
      expect(back.vision, ModelTrait.yes);
      expect(back.reasoning, ModelTrait.no);
      expect(back.supportsTools, isFalse);

      // A window of 0 or 12 would make every conversation "too long".
      final broken = ModelProfile.fromJson({'contextWindow': 12});
      expect(broken.contextWindow, ModelProfile.defaultContextWindow);
    });

    test('a profile is stored per endpoint and model', () async {
      SharedPreferences.setMockInitialValues({});
      StorageService.resetForTest();
      final storage = await StorageService.getInstance();

      const a = LlmConfig(baseUrl: 'https://a.example/v1', apiKey: 'k', model: 'm');
      const b = LlmConfig(baseUrl: 'https://a.example/v1', apiKey: 'k', model: 'other');

      expect(storage.getModelProfile(a).isDefault, isTrue);

      await storage.saveModelProfile(a, const ModelProfile(contextWindow: 8000));
      expect(storage.getModelProfile(a).contextWindow, 8000);
      expect(storage.getModelProfile(b).contextWindow, 32000,
          reason: 'a capability belongs to one model, not to the app');
    });

    test('a corrupt store reads as defaults rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'pref_model_profiles': '{not json'});
      StorageService.resetForTest();
      final storage = await StorageService.getInstance();
      const config = LlmConfig(baseUrl: 'https://a.example/v1', apiKey: 'k', model: 'm');
      expect(storage.getModelProfile(config).isDefault, isTrue);
    });
  });

  group('what the profile changes in a request', () {
    test('a model marked as not taking reasoning_effort never receives it', () async {
      forgetUnsupportedEffort();
      final fake = await FakeOpenAi.start([say('ok')]);
      addTearDown(fake.close);

      await LlmService().chatWithTools(
        config: fake.config.copyWith(thinking: ThinkingLevel.deep),
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        tools: const [],
        profile: const ModelProfile(reasoning: ModelTrait.no),
      );

      expect(fake.requests.single.containsKey('reasoning_effort'), isFalse);
      expect(fake.requests.length, 1,
          reason: 'the answer is decided before sending, not learned by failing');
    });

    test('a model marked as taking it receives it', () async {
      forgetUnsupportedEffort();
      final fake = await FakeOpenAi.start([say('ok')]);
      addTearDown(fake.close);

      await LlmService().chatWithTools(
        config: fake.config.copyWith(thinking: ThinkingLevel.fast),
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        tools: const [],
        profile: const ModelProfile(reasoning: ModelTrait.yes),
      );

      expect(fake.requests.single['reasoning_effort'], 'low');
    });
  });

  group('the context window the profile declares', () {
    /// Enough turns of bulky tool results to overflow a small window.
    List<Map<String, Object?>> conversation(int turns) {
      final messages = <Map<String, Object?>>[
        {'role': 'system', 'content': 'sys'},
        {'role': 'user', 'content': '把这几页都读完'},
      ];
      for (var i = 0; i < turns; i++) {
        messages
          ..add({
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'call_$i',
                'type': 'function',
                'function': {'name': 'read', 'arguments': '{}'},
              },
            ],
          })
          ..add({
            'role': 'tool',
            'tool_call_id': 'call_$i',
            'content': '正文' * 400,
          });
      }
      return messages;
    }

    test('a small window compacts where a large one does not', () {
      final messages = conversation(4);
      final small = ContextManager(
        limits: const ContextLimits(windowTokens: 2000),
      ).prepare(messages);
      final large = ContextManager(
        limits: const ContextLimits(windowTokens: 200000),
      ).prepare(messages);

      expect(small.changed, isTrue, reason: 'a 2k window has to give something up');
      expect(large.changed, isFalse);
      // The user's own words survive both.
      expect(
        small.messages.where((m) => m['role'] == 'user').length,
        1,
      );
    });

    test('a window too small even for the task stops instead of failing the request', () {
      // The user's own words are never shortened, so they are what can overflow
      // an undersized window. Sending the request anyway is a guaranteed 400.
      final messages = <Map<String, Object?>>[
        {'role': 'system', 'content': 'sys'},
        {'role': 'user', 'content': '要求' * 3000},
      ];
      final plan = ContextManager(
        limits: const ContextLimits(windowTokens: 600),
      ).prepare(messages);
      expect(plan.stop, isNotNull);
    });
  });
}
