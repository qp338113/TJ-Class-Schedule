import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../application/schedule_controller.dart';
import '../domain/notification_settings.dart';
import '../application/task_state.dart';
import '../domain/task_record.dart';
import 'reminder_planner.dart';
import 'task_reminder_planner.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw StateError('NotificationService 尚未初始化');
});

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _tappedDates = StreamController<DateTime>.broadcast();
  final _tappedTasks = StreamController<String>.broadcast();
  String? initialTaskId;
  final _planner = const ReminderPlanner();

  Stream<DateTime> get tappedDates => _tappedDates.stream;
  Stream<String> get tappedTasks => _tappedTasks.stream;

  Future<DateTime?> initialize() async {
    tz_data.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final taskId = _taskPayload(response.payload);
        if (taskId != null) {
          _tappedTasks.add(taskId);
          return;
        }
        final date = _parsePayload(response.payload);
        if (date != null) _tappedDates.add(date);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp != true) return null;
    initialTaskId = _taskPayload(launch?.notificationResponse?.payload);
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

  Future<void> showTaskNotice({
    required int id,
    required String title,
    required String body,
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    payload: 'task:',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'task_sync_updates',
        '作业同步与连接提醒',
        channelDescription: '作业更新、连接失效与通知测试',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
      ),
    ),
  );

  Future<bool> sendTaskTestNotification() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    if (!await notificationsEnabled()) return false;
    await showTaskNotice(
      id: 910001,
      title: '作业通知测试',
      body: '通知显示正常。点击此通知会打开作业；截止提醒与后台同步提醒使用系统通知权限。',
    );
    return true;
  }

  Future<void> openNotificationSettings() =>
      _plugin.openAppNotificationSettings();

  Future<int> reschedule({
    required ScheduleData schedule,
    required NotificationSettings settings,
    DateTime? now,
  }) async {
    // 课表重排只取消待触发的课程通知，保留作业的预约。
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (_parsePayload(pending.payload) != null) {
        await _plugin.cancel(id: pending.id);
      }
    }
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

  Future<int> rescheduleTasks({
    required List<TaskRecord> tasks,
    required TaskReminderSettings settings,
    DateTime? now,
  }) async {
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (_taskPayload(pending.payload) != null) {
        await _plugin.cancel(id: pending.id);
      }
    }
    if (!settings.enabled || !await notificationsEnabled()) return 0;
    final mode = await canScheduleExactNotifications()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    final plans = taskReminderPlans(tasks, settings, now ?? DateTime.now());
    for (final plan in plans) {
      await _plugin.zonedSchedule(
        id: plan.id,
        title: plan.title,
        body: plan.body,
        scheduledDate: tz.TZDateTime.from(plan.scheduledAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_deadline_v1',
            '作业截止提醒',
            channelDescription: '在自选提前时间提醒未完成作业',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notification',
            category: AndroidNotificationCategory.reminder,
          ),
        ),
        androidScheduleMode: mode,
        payload: plan.payload,
      );
    }
    return plans.length;
  }

  Future<void> dispose() async {
    await _tappedDates.close();
    await _tappedTasks.close();
  }

  String? _taskPayload(String? payload) =>
      payload != null && payload.startsWith('task:')
      ? payload.substring(5)
      : null;

  DateTime? _parsePayload(String? payload) {
    if (payload == null) return null;
    final value = DateTime.tryParse(payload);
    return value == null ? null : DateTime(value.year, value.month, value.day);
  }
}
