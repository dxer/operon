import 'package:flutter_test/flutter_test.dart';
import 'package:operon/services/llm_tools.dart';

// Two shapes of the same reply. Getting this wrong is invisible in a log and
// very visible in the panel: the answer turns into an internal note.

LlmToolResponse reply(Map<String, Object?> message) =>
    LlmToolResponse(message: message);

void main() {
  test('content as a string is the answer', () {
    expect(reply({'content': '你好！'}).content, '你好！');
    expect(reply({'content': '你好！'}).reasoningOnly, isFalse);
  });

  test('content as a list of parts is still the answer', () {
    final response = reply({
      'content': [
        {'type': 'text', 'text': '第一段'},
        {'type': 'text', 'text': '第二段'},
      ],
    });
    expect(response.content, '第一段第二段');
  });

  test('a null content with reasoning is named as such', () {
    final response = reply({'content': null, 'reasoning_content': '让我想想…'});
    expect(response.content, isNull);
    expect(response.reasoningOnly, isTrue);
  });

  test('neither text nor reasoning is just empty', () {
    final response = reply({'content': null});
    expect(response.content, isNull);
    expect(response.reasoningOnly, isFalse);
  });
}
