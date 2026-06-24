import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 轻量的本地通知封装：负责初始化、调度与取消任务的「闹钟提醒」。
///
/// 所有调用都包了 try/catch，确保在不支持的平台（或权限缺失）时静默降级，
/// 绝不影响主流程。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'things_reminders',
    '任务提醒',
    channelDescription: '到点提醒你去做某件事',
    importance: Importance.max,
    priority: Priority.high,
  );

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      // 自动检测设备时区；失败时回退东八区。
      var tzName = 'Asia/Shanghai';
      try {
        final detected = await FlutterTimezone.getLocalTimezone();
        if (detected.identifier.isNotEmpty) tzName = detected.identifier;
      } catch (_) {}
      try {
        tz.setLocalLocation(tz.getLocation(tzName));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
      }

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      const settings =
          InitializationSettings(android: android, iOS: darwin, macOS: darwin);
      await _plugin.initialize(settings: settings);

      final android13 = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android13?.requestNotificationsPermission();
      await android13?.requestExactAlarmsPermission();

      _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      _ready = true;
    } catch (e) {
      debugPrint('NotificationService init failed: $e');
    }
  }

  int _idOf(String itemId) => itemId.hashCode & 0x7fffffff;

  /// 在 [when] 调度一条提醒。过去的时间会被忽略。
  Future<void> schedule({
    required String itemId,
    required String title,
    required DateTime when,
  }) async {
    if (!_ready) return;
    await cancel(itemId);
    if (when.isBefore(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: _idOf(itemId),
        title: title,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(
            android: _channel, iOS: DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: itemId,
      );
    } catch (e) {
      debugPrint('schedule reminder failed: $e');
    }
  }

  Future<void> cancel(String itemId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _idOf(itemId));
    } catch (_) {}
  }
}
