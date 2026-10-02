import 'package:flutter/material.dart';

import '../domain/schedule_models.dart';
import '../domain/task_record.dart';

String taskCountdown(TaskRecord task, DateTime now) {
  if (task.completed) return '已完成';
  final due = task.dueAt;
  if (due == null) return '未设置截止时间';
  final difference = due.difference(now);
  final minutes = difference.inMinutes.abs();
  final prefix = difference.isNegative ? '已逾期' : '剩余';
  if (minutes == 0) return '$prefix 不到1分钟';
  if (minutes >= 1440) {
    return '$prefix ${minutes ~/ 1440}天 ${minutes % 1440 ~/ 60}小时';
  }
  if (minutes >= 60) return '$prefix ${minutes ~/ 60}小时 ${minutes % 60}分钟';
  return '$prefix $minutes分钟';
}

Color taskCourseColor(String name, Iterable<Course> courses) {
  final key = name.trim();
  for (final course in courses) {
    if (course.name.trim() == key) return Color(course.colorValue);
  }
  const colors = [
    0xff2563eb,
    0xff7c3aed,
    0xff0891b2,
    0xff059669,
    0xffd97706,
    0xffdb2777,
    0xff4f46e5,
    0xffc2410c,
  ];
  var hash = 0;
  for (final code in key.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return Color(colors[hash % colors.length]);
}
