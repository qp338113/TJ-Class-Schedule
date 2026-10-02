import '../application/task_state.dart';
import '../domain/task_record.dart';
import 'reminder_planner.dart';

List<ReminderPlan> taskReminderPlans(
  List<TaskRecord> tasks,
  TaskReminderSettings settings,
  DateTime now,
) {
  if (!settings.enabled) return const [];
  final eligible =
      tasks
          .where(
            (task) =>
                !task.completed &&
                task.dueAt != null &&
                task.dueAt!
                    .subtract(Duration(hours: settings.hours))
                    .isAfter(now),
          )
          .toList()
        ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  return [
    for (var index = 0; index < eligible.length; index++)
      ReminderPlan(
        id: 1000000 + index,
        scheduledAt: eligible[index].dueAt!.subtract(
          Duration(hours: settings.hours),
        ),
        title: '作业即将截止：${eligible[index].title}',
        body: '${eligible[index].course} · 距离截止还有 ${settings.hours} 小时',
        payload: 'task:${eligible[index].id}',
      ),
  ];
}
