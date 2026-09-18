import 'package:flutter/services.dart';

import '../application/schedule_controller.dart';
import '../domain/schedule_engine.dart';

class NextCourseWidgetService {
  const NextCourseWidgetService();

  static const _channel = MethodChannel('offline_course_schedule/widget');

  /// [colorValue] 是小部件自己的背景色（ARGB int）；
  /// 传 null 表示未自定义，原生侧会恢复原来的浅色背景。
  /// [refreshMode] 决定倒计时的刷新频率，原生侧据此排下一次刷新。
  Future<void> sync(
    ScheduleData schedule, {
    DateTime? now,
    int? colorValue,
    WidgetRefreshMode? refreshMode,
  }) async {
    final current = now ?? DateTime.now();
    final items = buildItems(schedule, current);
    await _channel.invokeMethod<void>('update', {
      'courses': items,
      'color': colorValue,
      'refreshMode': (refreshMode ?? WidgetRefreshMode.powerSaving).name,
    });
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
      memos: schedule.memos,
      adjustments: schedule.adjustments,
      cancellations: schedule.cancellations,
    );
    final items = <Map<String, Object>>[];
    for (var offset = 0; offset < 14; offset++) {
      final date = firstDay.add(Duration(days: offset));
      for (final entry in engine.getEntriesForDate(date)) {
        if (!entry.startTime.isAfter(current)) continue;
        // 备忘录没有教师，适配成空字符串以沿用现有的小组件数据结构和 Kotlin 侧逻辑。
        items.add({
          'name': entry.title,
          'teacher': entry.teacher,
          'location': entry.location,
          'startMillis': entry.startTime.millisecondsSinceEpoch,
          'time': _time(entry.startTime),
          'month': entry.startTime.month,
          'day': entry.startTime.day,
          'weekday': _weekday(entry.startTime.weekday),
          // 供小组件区分文案：备忘录说“距离事件开始”，课程说“距离上课”。
          'isMemo': entry.isMemo,
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
