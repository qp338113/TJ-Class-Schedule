import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/task_state.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/notifications/notification_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class FakePlugin implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final pending = <PendingNotificationRequest>[
    const PendingNotificationRequest(1000, '课', '课', '2026-10-02'),
    const PendingNotificationRequest(1000000, '作业', '作业', 'task:manual:one'),
  ];
  @override
  Future<List<PendingNotificationRequest>>
  pendingNotificationRequests() async => List.of(pending);
  @override
  Future<void> cancel({required int id, String? tag}) async =>
      pending.removeWhere((p) => p.id == id);
  @override
  Future<void> cancelAllPendingNotifications() async => pending.clear();
  final scheduled = <tz.TZDateTime>[];
  final modes = <AndroidScheduleMode>[];
  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduled.add(scheduledDate);
    modes.add(androidScheduleMode);
    pending.add(PendingNotificationRequest(id, title, body, payload));
  }
}

class FakeService extends NotificationService {
  FakeService(FakePlugin plugin, {this.allowed = true, this.exact = false})
    : super(plugin: plugin);
  final bool allowed, exact;
  @override
  Future<bool> notificationsEnabled() async => allowed;
  @override
  Future<bool> canScheduleExactNotifications() async => exact;
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
  });
  test('重排课表不会清除作业的预约通知', () async {
    final plugin = FakePlugin();
    final service = NotificationService(plugin: plugin);
    await service.reschedule(
      schedule: const ScheduleData(),
      settings: const NotificationSettings(enabled: false),
    );
    expect(plugin.pending.map((p) => p.payload), ['task:manual:one']);
    await service.dispose();
  });
  test('自定义提前时间按同一时刻预约，无精确闹钟权限仍调度；完成后取消且保留课程', () async {
    final plugin = FakePlugin();
    final service = FakeService(plugin);
    final now = DateTime.utc(2026, 10, 1, 8);
    final task = TaskRecord(
      id: 'manual:new',
      title: '数学作业',
      course: '数学',
      platform: 'manual',
      source: 'manual',
      accountId: '',
      createdAt: now,
      dueAt: now.add(const Duration(hours: 10)),
    );
    const settings = TaskReminderSettings(enabled: true, hours: 3);
    expect(
      await service.rescheduleTasks(
        tasks: [task],
        settings: settings,
        now: now,
      ),
      1,
    );
    expect(plugin.pending.map((p) => p.payload), [
      '2026-10-02',
      'task:manual:new',
    ]);
    expect(plugin.scheduled.single.toUtc(), now.add(const Duration(hours: 7)));
    expect(plugin.modes.single, AndroidScheduleMode.inexactAllowWhileIdle);
    await service.rescheduleTasks(
      tasks: [task.copyWith(completed: true)],
      settings: settings,
      now: now,
    );
    expect(plugin.pending.map((p) => p.payload), ['2026-10-02']);
    await service.dispose();
  });
  test('禁用提醒或系统拒绝通知，清除旧作业预约而不影响课程', () async {
    for (final allowed in [true, false]) {
      final plugin = FakePlugin();
      final service = FakeService(plugin, allowed: allowed);
      expect(
        await service.rescheduleTasks(
          tasks: [],
          settings: TaskReminderSettings(enabled: !allowed),
        ),
        0,
      );
      expect(plugin.pending.map((p) => p.payload), ['2026-10-02']);
      expect(plugin.scheduled, isEmpty);
      await service.dispose();
    }
  });
}
