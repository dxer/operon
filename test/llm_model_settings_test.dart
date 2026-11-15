import 'package:flutter_test/flutter_test.dart';
import 'package:operon/models/llm_config.dart';
import 'package:operon/services/llm_service.dart';
import 'package:operon/services/llm_tools.dart';

import 'support/fake_openai.dart';

/// The model endpoint is the one place a user both configures and is configured
/// by: the list it offers, the level of thinking asked for, and the ceiling on
/// the answer. All three travel through the same request, so they are tested
/// together.

void main() {
  group('fetching the model list', () {
    test('reads the ids a compatible endpoint offers', () async {
      final model = await FakeOpenAi.start(const []);
      addTearDown(model.close);

      final models = await LlmService().fetchModels(model.config);
      expect(models, ['fake-model', 'fake-model-mini', 'o3-mini']);
      expect(model.authHeaders.single, 'Bearer sk-test-token');
    });

    test('a rejected key is reported with the server\'s own words', () async {
      final model = await FakeOpenAi.start(const []);
      addTearDown(model.close);
      model.modelsStatus = 401;

      await expectLater(
        LlmService().fetchModels(model.config),
        throwsA(predicate((error) => '$error'.contains('invalid api key'))),
      );
      await expectLater(
        LlmService().fetchModels(model.config),
        throwsA(predicate((error) => '$error'.contains('401'))),
      );
    });

    test('an empty base url fails before a request is made', () async {
      const config = LlmConfig(baseUrl: '', apiKey: 'k', model: 'm');
      await expectLater(
        LlmService().fetchModels(config),
        throwsA(predicate((error) => '$error'.contains('Base URL'))),
      );
    });

    test('the models url is derived from whatever base the user typed', () async {
      // Same rule as /chat/completions: full endpoint, trailing slash or plain
      // base all have to end up at one place.
      final model = await FakeOpenAi.start(const []);
      addTearDown(model.close);
      for (final suffix in ['/v1', '/v1/', '/v1/models']) {
        final config = LlmConfig(
          baseUrl: 'http://127.0.0.1:${Uri.parse(model.baseUrl).port}$suffix',
          apiKey: 'sk-test-token',
          model: 'm',
        );
        expect(await LlmService().fetchModels(config), isNotEmpty, reason: suffix);
      }
    });
  });

  group('what the request says about thinking', () {
    Future<Map<String, Object?>> bodyFor(
      String model, {
      ThinkingLevel thinking = ThinkingLevel.auto,
      int? maxTokens,
    }) async {
      final fake = await FakeOpenAi.start([say('ok')]);
      addTearDown(fake.close);
      await LlmService().chatWithTools(
        config: LlmConfig(
          baseUrl: fake.baseUrl,
          apiKey: 'sk-test-token',
          model: model,
          thinking: thinking,
          maxOutputTokens: maxTokens,
        ),
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        tools: const [],
      );
      return fake.requests.single;
    }

    test('自动 sends no reasoning or temperature field at all', () async {
      final body = await bodyFor('gpt-4o');
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('max_tokens'), isFalse);
    });

    test('深度思考 asks for high effort', () async {
      final body = await bodyFor('gpt-4o', thinking: ThinkingLevel.deep);
      expect(body['reasoning_effort'], 'high');
    });

    test('快速响应 asks for low effort', () async {
      final body = await bodyFor('gpt-4o', thinking: ThinkingLevel.fast);
      expect(body['reasoning_effort'], 'low');
    });

    test('a ceiling is sent as max_tokens on ordinary models', () async {
      final body = await bodyFor('deepseek-chat', maxTokens: 2048);
      expect(body['max_tokens'], 2048);
      expect(body.containsKey('max_completion_tokens'), isFalse);
    });

    test('a ceiling is sent as max_completion_tokens where that is the field', () async {
      final body = await bodyFor('o3-mini', maxTokens: 2048);
      expect(body['max_completion_tokens'], 2048);
      expect(body.containsKey('max_tokens'), isFalse);
    });
  });

  group('an endpoint that refuses the thinking level', () {
    test('is asked once without it, and never asked again', () async {
      forgetUnsupportedEffort();
      addTearDown(forgetUnsupportedEffort);
      final fake = await FakeOpenAi.start([say('ok'), say('ok')]);
      addTearDown(fake.close);
      fake.rejectReasoningEffort = true;

      final service = LlmService();
      final config = fake.config.copyWith(thinking: ThinkingLevel.deep);
      final first = await service.chatWithTools(
        config: config,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        tools: const [],
      );
      expect(first.effortDropped, isTrue);
      expect(first.content, 'ok');
      expect(fake.requests.length, 2);
      expect(fake.requests.first['reasoning_effort'], 'high');
      expect(fake.requests[1].containsKey('reasoning_effort'), isFalse);

      // The second call goes straight through: the doomed round trip is paid
      // once per endpoint, not every turn.
      final second = await service.chatWithTools(
        config: config,
        messages: const [
          {'role': 'user', 'content': 'again'},
        ],
        tools: const [],
      );
      expect(second.effortDropped, isFalse);
      expect(fake.requests.length, 3);
      expect(fake.requests[2].containsKey('reasoning_effort'), isFalse);
    });

    test('a real 400 is still a failure, not a retry', () async {
      forgetUnsupportedEffort();
      final fake = await FakeOpenAi.start([say('ok')]);
      addTearDown(fake.close);
      fake.failWith = 'messages is required';

      await expectLater(
        LlmService().chatWithTools(
          config: fake.config.copyWith(thinking: ThinkingLevel.fast),
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
          tools: const [],
        ),
        throwsA(predicate((error) => '$error'.contains('messages is required'))),
      );
      // One request: a rejection unrelated to the field must not be retried.
      expect(fake.requests.length, 1);
    });
  });

  group('the config itself', () {
    test('survives a round trip through json', () {
      const config = LlmConfig(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-x',
        model: 'some-model',
        temperature: 0.3,
        thinking: ThinkingLevel.deep,
        maxOutputTokens: 4096,
      );
      final back = LlmConfig.fromJson(Map<String, dynamic>.from(config.toJson()));
      expect(back.baseUrl, config.baseUrl);
      expect(back.thinking, ThinkingLevel.deep);
      expect(back.maxOutputTokens, 4096);
    });

    test('an old config without the new fields still loads', () {
      final back = LlmConfig.fromJson({
        'baseUrl': 'https://api.example.com/v1',
        'apiKey': 'sk-x',
        'model': 'm',
        'temperature': 0.1,
      });
      expect(back.thinking, ThinkingLevel.auto);
      expect(back.maxOutputTokens, isNull);
    });

    test('a ceiling can be cleared again', () {
      const config = LlmConfig(
        baseUrl: 'b',
        apiKey: 'k',
        model: 'm',
        maxOutputTokens: 100,
      );
      expect(config.copyWith(clearMaxOutputTokens: true).maxOutputTokens, isNull);
      expect(config.copyWith(maxOutputTokens: 200).maxOutputTokens, 200);
    });

    test('the field name follows the model family', () {
      expect(LlmConfig.usesMaxCompletionTokens('o1-preview'), isTrue);
      expect(LlmConfig.usesMaxCompletionTokens('o3-mini'), isTrue);
      expect(LlmConfig.usesMaxCompletionTokens('gpt-5.1'), isTrue);
      expect(LlmConfig.usesMaxCompletionTokens('gpt-4o'), isFalse);
      expect(LlmConfig.usesMaxCompletionTokens('deepseek-chat'), isFalse);
    });

    test('reasoning series omit temperature', () async {
      final fake = await FakeOpenAi.start([say('ok')]);
      addTearDown(fake.close);
      await LlmService().chatWithTools(
        config: LlmConfig(
          baseUrl: fake.baseUrl,
          apiKey: 'sk-test-token',
          model: 'o3-mini',
        ),
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        tools: const [],
      );
      expect(fake.requests.single.containsKey('temperature'), isFalse);
    });

    test('an empty default is not valid, so the app asks instead of guessing', () {
      expect(LlmConfig.defaultConfig().isValid, isFalse);
    });

    test('preset round trips through json', () {
      const preset = LlmPreset(
        id: 'p1',
        name: 'DeepSeek',
        config: LlmConfig(
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: 'sk-ds',
          model: 'deepseek-chat',
        ),
      );
      final back = LlmPreset.fromJson(Map<String, dynamic>.from(preset.toJson()));
      expect(back.id, 'p1');
      expect(back.name, 'DeepSeek');
      expect(back.config.model, 'deepseek-chat');
    });
  });
}
