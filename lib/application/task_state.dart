import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/task_repository.dart';
import 'schedule_controller.dart';

final taskRevisionProvider = StateProvider<int>((ref) => 0);
final taskRepositoryProvider = FutureProvider<TaskRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return TaskRepository(
    db.database,
    onChanged: () => ref.read(taskRevisionProvider.notifier).state++,
  );
});

class TaskReminderSettings {
  const TaskReminderSettings({this.enabled = false, this.hours = 24});
  final bool enabled;
  final int hours;
}

TaskReminderSettings taskReminderSettingsFromJson(String? raw) {
  if (raw == null) return const TaskReminderSettings();
  final value = jsonDecode(raw) as Map<String, dynamic>;
  return TaskReminderSettings(
    enabled: value['enabled'] == true,
    hours: value['hours'] as int,
  );
}

final taskReminderSettingsProvider =
    AsyncNotifierProvider<TaskReminderSettingsController, TaskReminderSettings>(
      TaskReminderSettingsController.new,
    );

class TaskReminderSettingsController
    extends AsyncNotifier<TaskReminderSettings> {
  @override
  Future<TaskReminderSettings> build() async {
    final db = await ref.watch(databaseProvider.future);
    final raw = await db.loadSetting('task_reminders');
    return taskReminderSettingsFromJson(raw);
  }

  Future<void> save(TaskReminderSettings settings) async {
    if (settings.hours < 1 || settings.hours > 8760) {
      throw ArgumentError('请输入 1–8760 的整小时数');
    }
    final db = await ref.read(databaseProvider.future);
    await db.saveSetting(
      'task_reminders',
      jsonEncode({'enabled': settings.enabled, 'hours': settings.hours}),
    );
    state = AsyncData(settings);
  }
}
