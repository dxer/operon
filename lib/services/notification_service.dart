import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static NotificationService? _instance;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  NotificationService._();

  static NotificationService getInstance() {
    _instance ??= NotificationService._();
    return _instance!;
  }

  Future<void> init() async {
    if (_initialized || kIsWeb) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('[Notification] User tapped notification: ${response.payload}');
        },
      );

      // Request notification permission for Android 13+ (API 33+)
      final androidImplementation = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      _initialized = true;
    } catch (e) {
      debugPrint('[Notification] Init error: $e');
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'operon_agent_channel',
      'Operon 智能体任务通知',
      channelDescription: '推送智能体任务完成、验证码拦截与敏感操作授权提醒',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(android: androidDetails),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[Notification] Show error: $e');
    }
  }

  Future<void> notifyTaskCompleted(String summary) async {
    await showNotification(
      id: 1001,
      title: '🎉 Operon 任务已完成',
      body: summary.isNotEmpty ? summary : '您下达的网页自动化任务已成功达成！',
    );
  }

  Future<void> notifyConfirmationNeeded(String action) async {
    await showNotification(
      id: 1002,
      title: '⚠️ Operon 等待安全授权',
      body: 'AI 准备执行敏感操作: $action，请点击返回 App 授权',
    );
  }

  Future<void> notifyCaptchaDetected(String captchaType) async {
    await showNotification(
      id: 1003,
      title: '🛡️ 检测到人机验证码',
      body: '页面弹出了 $captchaType，请手动滑动通过后 AI 将继续运行',
    );
  }
}
