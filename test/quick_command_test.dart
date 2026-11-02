import 'package:flutter_test/flutter_test.dart';
import 'package:operon/config/quick_command_defaults.dart';
import 'package:operon/models/quick_command.dart';

void main() {
  test('quick commands render defaults and override values', () {
    const command = QuickCommand(
      id: 'demo',
      title: 'Demo',
      description: '',
      promptTemplate: '处理 {{count}} 条，语气 {{tone}}。',
      inputs: [
        QuickCommandInput(
          key: 'count',
          label: '条数',
          type: QuickCommandInputType.number,
          defaultValue: '3',
        ),
        QuickCommandInput(
          key: 'tone',
          label: '语气',
          defaultValue: '友好',
        ),
      ],
    );

    expect(command.render(), '处理 3 条，语气 友好。');
    expect(
      command.render({'count': '5', 'tone': '专业'}),
      '处理 5 条，语气 专业。',
    );
  });

  test('default quick commands have unique ids and useful prompts', () {
    final commands = QuickCommandDefaults.all();
    expect(commands.length, greaterThanOrEqualTo(5));
    expect(commands.map((item) => item.id).toSet().length, commands.length);
    for (final command in commands) {
      expect(command.title.trim(), isNotEmpty);
      expect(command.promptTemplate.trim(), isNotEmpty);
      expect(command.render(), isNot(contains('{{')));
    }
  });

  test('batch templates enable content dedupe', () {
    final reply = QuickCommandDefaults.all()
        .firstWhere((item) => item.id == 'quick_batch_reply');
    expect(reply.policy.mode, QuickCommandMode.batch);
    expect(reply.policy.uniqueContent, isTrue);
    expect(reply.policy.maxSteps, isNotNull);
  });
}
