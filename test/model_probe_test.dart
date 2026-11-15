import 'package:flutter_test/flutter_test.dart';
import 'package:operon/services/model_probe.dart';

import 'support/fake_openai.dart';

/// A model is only usable by the agent if it calls tools. These tests pin the
/// one request that decides it.
void main() {
  test('a model that calls ping passes', () async {
    final model = await FakeOpenAi.start([call('ping', {'name': 'ok'})]);
    addTearDown(model.close);

    final result = await probeModel(config: model.config);

    expect(result.calledTool, isTrue);
    // The probe asks with the tool schema, not just a text question.
    final tools = model.requests.single['tools'] as List;
    expect((tools.single as Map)['function'], containsPair('name', 'ping'));
  });

  test('a text answer alone does not pass', () async {
    final model = await FakeOpenAi.start([say('pong')]);
    addTearDown(model.close);

    final result = await probeModel(config: model.config);

    expect(result.calledTool, isFalse);
    expect(result.content, 'pong');
  });

  test('a wrong tool name does not count as the probe', () async {
    final model = await FakeOpenAi.start([call('other_tool')]);
    addTearDown(model.close);

    final result = await probeModel(config: model.config);

    expect(result.calledTool, isFalse);
  });
}
