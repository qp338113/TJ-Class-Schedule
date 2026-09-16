import 'schedule_models.dart';

/// 唯一的日期课表查询入口。
///
/// 引擎只持有不可变快照，因此相同输入总会得到相同输出。界面层只调用本方法，
/// 不自行计算教学周或单双周。
class ScheduleEngine {
  ScheduleEngine({
    required this.term,
    required Iterable<Course> courses,
    Iterable<ScheduleAdjustment> adjustments = const [],
    Iterable<CourseCancellation> cancellations = const [],
  }) : courses = List<Course>.unmodifiable(courses),
       adjustments = List<ScheduleAdjustment>.unmodifiable(adjustments),
       cancellations = List<CourseCancellation>.unmodifiable(cancellations);

  final Term term;
  final List<Course> courses;
  final List<ScheduleAdjustment> adjustments;
  final List<CourseCancellation> cancellations;

  ScheduleAdjustment? adjustmentForDate(DateTime date) {
    for (final adjustment in adjustments) {
      if (adjustment.matches(date)) return adjustment;
    }
    return null;
  }

  int? getWeekForDate(DateTime date) {
    final elapsedDays = _calendarDay(
      date,
    ).difference(_calendarDay(term.firstWeekMonday)).inDays;
    final week = elapsedDays ~/ 7 + 1;
    return elapsedDays < 0 || week < 1 || week > term.totalWeeks ? null : week;
  }

  List<ScheduledCourse> getCoursesForDate(DateTime date) {
    final adjustment = adjustmentForDate(date);
    if (adjustment?.isHoliday == true) return const [];
    final week = adjustment?.replacementWeek ?? getWeekForDate(date);
    if (week == null) return const [];

    final effectiveWeekday = adjustment?.replacementWeekday ?? date.weekday;
    final result = <ScheduledCourse>[];
    for (final course in courses) {
      for (final session in course.sessions) {
        if (cancellations.any(
          (cancellation) => cancellation.matches(session.id, date),
        )) {
          continue;
        }
        if (session.weekday != effectiveWeekday ||
            !session.weekRule.includes(week)) {
          continue;
        }
        final start = term.periodFor(effectiveWeekday, session.startPeriod);
        final end = term.periodFor(effectiveWeekday, session.endPeriod);
        if (start == null || end == null) continue;
        result.add(
          ScheduledCourse(
            course: course,
            session: session,
            week: week,
            startTime: _atMinutes(date, start.startMinutes),
            endTime: _atMinutes(date, end.endMinutes),
          ),
        );
      }
    }
    result.sort((a, b) {
      final timeOrder = a.startTime.compareTo(b.startTime);
      return timeOrder != 0
          ? timeOrder
          : a.course.name.compareTo(b.course.name);
    });
    return List<ScheduledCourse>.unmodifiable(result);
  }

  // 用 UTC 仅表示“公历日序号”，避免夏令时造成两个本地午夜不足 24 小时。
  DateTime _calendarDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  DateTime _atMinutes(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
}
