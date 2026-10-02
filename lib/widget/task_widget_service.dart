import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';

import '../domain/task_record.dart';

class TaskWidgetService {
  const TaskWidgetService();
  static const channel = MethodChannel('offline_course_schedule/widget');

  List<Map<String, Object>> _payload(List<TaskRecord> tasks) => [
    for (final task in tasks)
      if (!task.completed && task.dueAt != null && task.source != 'demo')
        {
          'id': task.id,
          'title': task.title,
          'course': task.course,
          'dueMillis': task.dueAt!.millisecondsSinceEpoch,
        },
  ];

  Future<void> sync(List<TaskRecord> tasks) =>
      channel.invokeMethod<void>('updateTasks', {'tasks': _payload(tasks)});

  Future<void> syncBackground(List<TaskRecord> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('task_widget_tasks', jsonEncode(_payload(tasks)));
    await const AndroidIntent(
      action: 'com.offlinecourse.offline_course_schedule.REFRESH_TASK_WIDGET',
      package: 'com.offlinecourse.offline_course_schedule',
      componentName:
          'com.offlinecourse.offline_course_schedule.TaskDeadlineWidget',
    ).sendBroadcast();
  }

  Future<String?> initialTask() => channel.invokeMethod<String>('initialTask');
}
