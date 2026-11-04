import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/services/share_intent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(ShareIntentService.channel, null);
  });

  test('takeInitialLink returns the text that launched the app', () async {
    messenger.setMockMethodCallHandler(ShareIntentService.channel, (call) async {
      if (call.method == 'initialShared') return '标题 https://example.com/a';
      return null;
    });

    expect(
      await ShareIntentService.instance.takeInitialLink(),
      '标题 https://example.com/a',
    );
  });

  test('takeInitialLink is null without a native handler', () async {
    // No mock registered: the platform channel is missing in this environment.
    expect(await ShareIntentService.instance.takeInitialLink(), isNull);
  });

  test('shares that arrive while running reach the stream', () async {
    final service = ShareIntentService.instance;
    service.init();
    final received = <String>[];
    final sub = service.links.listen(received.add);

    await messenger.handlePlatformMessage(
      'operon/share',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('shared', 'https://example.com/b'),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, ['https://example.com/b']);
    await sub.cancel();
  });

  test('shareText forwards the url to the system sheet', () async {
    String? sent;
    messenger.setMockMethodCallHandler(ShareIntentService.channel, (call) async {
      if (call.method == 'shareText') {
        sent = (call.arguments as Map)['text'] as String?;
        return true;
      }
      return null;
    });

    expect(
      await ShareIntentService.instance.shareText('https://example.com/a'),
      isTrue,
    );
    expect(sent, 'https://example.com/a');
  });

  test('shareText refuses blank text without calling native', () async {
    var called = false;
    messenger.setMockMethodCallHandler(ShareIntentService.channel, (call) async {
      called = true;
      return true;
    });

    expect(await ShareIntentService.instance.shareText('   '), isFalse);
    expect(called, isFalse);
  });

  test('shareText reports false when the platform cannot share', () async {
    // No mock registered: the channel is missing, as on desktop/web.
    expect(
      await ShareIntentService.instance.shareText('https://example.com/a'),
      isFalse,
    );
  });
}
