import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  /// Initialize notifications plugin and load timezone database.
  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    
    tz.initializeTimeZones();
    
    // Set local timezone location to UTC or device timezone if needed
    // By default, we use UTC or fallback to local
    tz.setLocalLocation(tz.getLocation('UTC'));
    
    await _plugin.initialize(
      initSettings,
    );
  }

  /// Schedule a local notification at the designated [scheduledTime].
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    final utcTime = scheduledTime.toUtc();
    final tzTime = tz.TZDateTime.from(utcTime, tz.local);
    
    if (tzTime.isBefore(tz.TZDateTime.now(tz.local))) {
      // Cannot schedule in the past
      return;
    }
    
    const androidDetails = AndroidNotificationDetails(
      'mind_flow_reminders',
      'Напоминания MIND FLOW',
      channelDescription: 'Канал для отправки напоминаний о задачах',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const platformDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancel scheduled notification by ID.
  static Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }
}
