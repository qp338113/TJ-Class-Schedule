import 'schedule_models.dart';

/// 唯一的日期课表查询入口。
///
/// 引擎只持有不可变快照，因此相同输入总会得到相同输出。界面层只调用本方法，
/// 不自行计算教学周或单双周。
class ScheduleEngine {
  ScheduleEngine({
    required this.term,
    required Iterable<Course> courses,
    Iterable<Memo> memos = const [],
    Iterable<ScheduleAdjustment> adjustments = const [],
    Iterable<CourseCancellation> cancellations = const [],
  }) : courses = List<Course>.unmodifiable(courses),
       memos = List<Memo>.unmodifiable(memos),
       adjustments = List<ScheduleAdjustment>.unmodifiable(adjustments),
       cancellations = List<CourseCancellation>.unmodifiable(cancellations);

  final Term term;
  final List<Course> courses;
  final List<Memo> memos;
  final List<ScheduleAdjustment> adjustments;
  final List<CourseCancellation> cancellations;

  ScheduleAdjustment? adjustmentForDate(DateTime date) {
    for (final adjustment in adjustments) {
      if (adjustment.matches(date)) return adjustment;
    }
    return null;
  }

  int? getWeekForDate(DateTime date) => term.weekOf(date);

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

  /// 某一天的全部安排：课程与备忘录的合并结果，按开始时间升序。
  ///
  /// 课程部分直接复用 [getCoursesForDate]，保证两者永不漂移；备忘录遵守同一套
  /// 周次、调休与节假日规则，但不受临时停课影响。开始时间相同时课程排在备忘录
  /// 之前，再按标题排序以保持稳定。
  List<ScheduleEntry> getEntriesForDate(DateTime date) {
    final adjustment = adjustmentForDate(date);
    if (adjustment?.isHoliday == true) return const [];
    final week = adjustment?.replacementWeek ?? getWeekForDate(date);
    if (week == null) return const [];
    final effectiveWeekday = adjustment?.replacementWeekday ?? date.weekday;
    final entries = <ScheduleEntry>[
      for (final course in getCoursesForDate(date)) CourseEntry(course),
      for (final memo in memos)
        if (_scheduleMemo(memo, date, week, effectiveWeekday) case final entry?)
          entry,
    ];
    entries.sort((a, b) {
      final timeOrder = a.startTime.compareTo(b.startTime);
      if (timeOrder != 0) return timeOrder;
      if (a.isMemo != b.isMemo) return a.isMemo ? 1 : -1;
      return a.title.compareTo(b.title);
    });
    return List<ScheduleEntry>.unmodifiable(entries);
  }

  /// 把一条备忘录映射到 [date] 这一天；当天不生效时返回 null。
  MemoEntry? _scheduleMemo(
    Memo memo,
    DateTime date,
    int week,
    int effectiveWeekday,
  ) {
    final memoDate = memo.date;
    if (memoDate != null) {
      // 一次性备忘录只在同年月日出现，时刻由 startMinutes/endMinutes 换算。
      final sameDay =
          memoDate.year == date.year &&
          memoDate.month == date.month &&
          memoDate.day == date.day;
      if (!sameDay) return null;
      return MemoEntry(
        memo: memo,
        startTime: _atMinutes(date, memo.startMinutes!),
        endTime: _atMinutes(date, memo.endMinutes!),
      );
    }
    if (memo.weekday != effectiveWeekday || !memo.weekRule!.includes(week)) {
      return null;
    }
    final start = term.periodFor(effectiveWeekday, memo.startPeriod!);
    final end = term.periodFor(effectiveWeekday, memo.endPeriod!);
    if (start == null || end == null) return null;
    return MemoEntry(
      memo: memo,
      startTime: _atMinutes(date, start.startMinutes),
      endTime: _atMinutes(date, end.endMinutes),
    );
  }

  DateTime _atMinutes(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
}
