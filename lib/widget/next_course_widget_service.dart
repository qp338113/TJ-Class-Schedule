import 'package:flutter/services.dart';

import '../application/schedule_controller.dart';
import '../domain/schedule_engine.dart';

class NextCourseWidgetService {
  const NextCourseWidgetService();

  static const _channel = MethodChannel('offline_course_schedule/widget');

  Future<void> sync(ScheduleData schedule, {DateTime? now}) async {
    final current = now ?? DateTime.now();
    final items = buildItems(schedule, current);
    await _channel.invokeMethod<void>('update', {'courses': items});
  }

  List<Map<String, Object>> buildItems(
    ScheduleData schedule,
    DateTime current,
  ) {
    final term = schedule.term;
    if (term == null) return const [];
    final firstDay = DateTime(current.year, current.month, current.day);
    final engine = ScheduleEngine(
      term: term,
      courses: schedule.courses,
      adjustments: schedule.adjustments,
      cancellations: schedule.cancellations,
    );
    final items = <Map<String, Object>>[];
    for (var offset = 0; offset < 14; offset++) {
      final date = firstDay.add(Duration(days: offset));
      for (final item in engine.getCoursesForDate(date)) {
        if (!item.startTime.isAfter(current)) continue;
        items.add({
          'name': item.course.name,
          'teacher': item.teacher,
          'location': item.session.location,
          'startMillis': item.startTime.millisecondsSinceEpoch,
          'time': _time(item.startTime),
          'month': item.startTime.month,
          'day': item.startTime.day,
          'weekday': _weekday(item.startTime.weekday),
        });
      }
    }
    items.sort(
      (a, b) => (a['startMillis'] as int).compareTo(b['startMillis'] as int),
    );
    return List<Map<String, Object>>.unmodifiable(items);
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String _weekday(int value) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][value - 1];
}
