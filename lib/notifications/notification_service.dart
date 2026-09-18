import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../application/schedule_controller.dart';
import '../domain/notification_settings.dart';
import 'reminder_planner.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw StateError('NotificationService 尚未初始化');
});

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _tappedDates = StreamController<DateTime>.broadcast();
  final _planner = const ReminderPlanner();

  Stream<DateTime> get tappedDates => _tappedDates.stream;

  Future<DateTime?> initialize() async {
    tz_data.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final date = _parsePayload(response.payload);
        if (date != null) _tappedDates.add(date);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp != true) return null;
    return _parsePayload(launch?.notificationResponse?.payload);
  }

  Future<void> requestAndroidPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  Future<bool> canScheduleExactNotifications() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  Future<bool> notificationsEnabled() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  Future<int> pendingNotificationCount() async =>
      (await _plugin.pendingNotificationRequests()).length;

  Future<void> sendTestNotification(NotificationSettings settings) {
    final mode = settings.alertMode;
    return _plugin.show(
      id: 900001,
      title: 'TJ Class Schedule 测试提醒',
      body: '如果你看到这条消息，通知显示功能正常。',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          // 必须换新渠道 id：Android 不允许调高已存在渠道的重要性
          'course_reminder_test_v2_${mode.name}',
          '提醒功能测试',
          channelDescription: '用于检查通知、震动和声音设置',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
          playSound: mode == ReminderAlertMode.soundAndVibration,
          enableVibration: mode != ReminderAlertMode.notificationOnly,
        ),
      ),
    );
  }

  Future<void> openNotificationSettings() =>
      _plugin.openAppNotificationSettings();

  Future<int> reschedule({
    required ScheduleData schedule,
    required NotificationSettings settings,
    DateTime? now,
  }) async {
    // 只能清"未触发"的定时通知：cancelAll() 会连已经显示在通知栏里的提醒一起删掉，
    // 导致用户刚看到的提醒莫名消失。
    await _plugin.cancelAllPendingNotifications();
    final term = schedule.term;
    if (term == null || !settings.enabled) return 0;
    if (!await canScheduleExactNotifications()) return 0;
    final currentTime = now ?? tz.TZDateTime.now(tz.local);
    final plans = _planner.createPlans(
      now: currentTime,
      term: term,
      courses: schedule.courses,
      memos: schedule.memos,
      adjustments: schedule.adjustments,
      cancellations: schedule.cancellations,
      settings: settings,
    );
    final lockScreenPlans = _planner.createLockScreenPlans(
      now: currentTime,
      term: term,
      courses: schedule.courses,
      adjustments: schedule.adjustments,
      cancellations: schedule.cancellations,
      settings: settings,
    );
    final alertMode = settings.alertMode;
    for (final plan in plans) {
      final time = plan.scheduledAt;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          // 必须换新渠道 id：Android 不允许调高已存在渠道的重要性
          'course_reminders_v2_${alertMode.name}',
          '上课提醒',
          channelDescription: '在课程开始前提醒',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
          category: AndroidNotificationCategory.reminder,
          playSound: alertMode == ReminderAlertMode.soundAndVibration,
          enableVibration: alertMode != ReminderAlertMode.notificationOnly,
          // 展开成大文本样式，让提醒在通知栏里更显眼
          styleInformation: BigTextStyleInformation(plan.body),
        ),
      );
      await _plugin.zonedSchedule(
        id: plan.id,
        title: plan.title,
        body: plan.body,
        scheduledDate: tz.TZDateTime(
          tz.local,
          time.year,
          time.month,
          time.day,
          time.hour,
          time.minute,
        ),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: plan.payload,
      );
    }
    for (final plan in lockScreenPlans) {
      final time = plan.scheduledAt;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'lock_screen_next_course',
          '锁屏下一节课',
          channelDescription: '上课前一小时在锁屏显示下一节课程',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: 'ic_notification',
          playSound: false,
          enableVibration: false,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.event,
          timeoutAfter: plan.timeoutAfterMilliseconds,
          styleInformation: BigTextStyleInformation(plan.body),
        ),
      );
      await _plugin.zonedSchedule(
        id: plan.id,
        title: plan.title,
        body: plan.body,
        scheduledDate: tz.TZDateTime(
          tz.local,
          time.year,
          time.month,
          time.day,
          time.hour,
          time.minute,
          time.second,
        ),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: plan.payload,
      );
    }
    return plans.length + lockScreenPlans.length;
  }

  Future<void> dispose() => _tappedDates.close();

  DateTime? _parsePayload(String? payload) {
    if (payload == null) return null;
    final value = DateTime.tryParse(payload);
    return value == null ? null : DateTime(value.year, value.month, value.day);
  }
}
