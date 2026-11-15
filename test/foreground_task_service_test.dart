import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operon/services/foreground_task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ForegroundTaskService.instance;
  final calls = <MethodCall>[];

  void mockPlatform({bool present = true}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      ForegroundTaskService.channel,
      present
          ? (call) async {
              calls.add(call);
              return true;
            }
          : null,
    );
  }

  setUp(() {
    calls.clear();
    service.resetForTest();
    mockPlatform();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForegroundTaskService.channel, null);
  });

  group('task notification', () {
    test('the goal becomes the body, on one line', () async {
      await service.start(goal: '  打开\n订单页面  ');

      final call = calls.single;
      expect(call.method, 'start');
      expect(call.arguments['body'], '打开 订单页面');
      expect(call.arguments['title'], 'Operon 正在执行');
      expect(call.arguments['paused'], isFalse);
      expect(call.arguments['canPause'], isTrue);
    });

    test('a long goal is cut to what the shade can show', () async {
      await service.start(goal: 'a' * 120);
      final body = calls.single.arguments['body'] as String;
      expect(body.length, 80);
      expect(body.endsWith('…'), isTrue);
    });

    test('unchanged updates are dropped, changed ones are sent', () async {
      await service.start(goal: '发布一条动态');
      calls.clear();

      await service.update(detail: '正在思考下一步', paused: false);
      await service.update(detail: '正在思考下一步', paused: false);
      expect(calls, hasLength(1));

      await service.update(detail: '正在思考下一步', paused: true);
      expect(calls, hasLength(2));
      // A paused task says so, and remains resumable.
      expect(calls.last.arguments['title'], '任务已暂停');
      expect(calls.last.arguments['paused'], isTrue);
      expect(calls.last.arguments['canPause'], isTrue);
    });

    test('waiting for a person says so and cannot be paused', () async {
      await service.start(goal: '提交表单');
      calls.clear();

      await service.update(
        detail: '等待你授权敏感操作',
        paused: false,
        canPause: false,
      );

      expect(calls.single.arguments['title'], 'Operon 需要你');
      expect(calls.single.arguments['canPause'], isFalse);
    });

    test('an update before a start does nothing', () async {
      await service.update(detail: '正在观察页面', paused: false);
      expect(calls, isEmpty);
    });

    test('a run that ended cannot bring the notification back', () async {
      await service.start(goal: '查一下天气');
      calls.clear();

      await service.stop();
      await service.update(detail: '正在观察页面', paused: false);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'stop');
    });

    test('without a platform side the calls stay quiet', () async {
      mockPlatform(present: false);

      await expectLater(service.start(goal: 'x'), completes);
      await expectLater(service.update(detail: 'y', paused: true), completes);
      await expectLater(service.stop(), completes);
    });
  });

  group('notification actions', () {
    test('a tap reaches the run as pause, resume and stop', () async {
      await service.init();
      final actions = <String>[];
      service.onAction = actions.add;

      Future<void> tap(String action) {
        return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          ForegroundTaskService.channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('onTaskAction', action)),
          (_) {},
        );
      }

      await tap('pause');
      await tap('resume');
      await tap('stop');
      await tap('');

      expect(actions, ['pause', 'resume', 'stop']);
    });
  });
}
