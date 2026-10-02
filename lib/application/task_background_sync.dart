import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import '../data/schedule_database.dart';
import '../data/task_repository.dart';
import '../notifications/notification_service.dart';
import '../notifications/task_sync_notifications.dart';
import 'task_state.dart';
import '../widget/task_widget_service.dart';
import 'task_sync_controller.dart';

@pragma('vm:entry-point')
void taskSyncDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = await ScheduleDatabase.open(singleInstance: false);
    final notifications = NotificationService();
    TaskSyncService? service;
    try {
      if (await db.loadSetting('task_auto_sync') != 'true') return true;
      await notifications.initialize();
      final notifier = TaskSyncNotifications(db, notifications);
      service = TaskSyncService(
        db,
        onAutomaticUpdate: notifier.updated,
        onAuthRequired: notifier.authRequired,
      );
      await service.refresh();
      final raw = await db.loadSetting('task_reminders');
      final settings = taskReminderSettingsFromJson(raw);
      final tasks = await TaskRepository(db.database).loadVisible();
      await const TaskWidgetService().syncBackground(tasks);
      await notifications.rescheduleTasks(tasks: tasks, settings: settings);
      return true;
    } catch (_) {
      // 网络失败已由同步服务记录；不以高频重试绕过自动同步窗口。
      return true;
    } finally {
      service?.close();
      await notifications.dispose();
      await db.close();
    }
  });
}

Future<void> configureTaskBackgroundSync(bool enabled) async {
  if (!Platform.isAndroid) return;
  if (!enabled) {
    await Workmanager().cancelByUniqueName('task-background-sync');
    return;
  }
  await Workmanager().registerPeriodicTask(
    'task-background-sync',
    'sync-tasks',
    frequency: const Duration(minutes: 30),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> initializeTaskBackgroundSync() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(taskSyncDispatcher);
  final db = await ScheduleDatabase.open(singleInstance: false);
  try {
    await configureTaskBackgroundSync(
      await db.loadSetting('task_auto_sync') == 'true',
    );
  } finally {
    await db.close();
  }
}
