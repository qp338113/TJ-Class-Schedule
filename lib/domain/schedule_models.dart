enum WeekType { every, odd, even, custom }

/// 一组可判定的教学周规则。
///
/// 连续单双周使用 [startWeek]、[endWeek] 和 [type]；不连续周次额外保存在
/// [explicitWeeks]，因此不会把“1,3,5-9周”错误扩展成每周。
class WeekRule {
  WeekRule({
    required this.startWeek,
    required this.endWeek,
    required this.type,
    Set<int>? explicitWeeks,
  }) : explicitWeeks = explicitWeeks == null
           ? null
           : Set<int>.unmodifiable(explicitWeeks) {
    if (startWeek < 1 || endWeek < startWeek) {
      throw ArgumentError('教学周范围无效：$startWeek-$endWeek');
    }
    if (type == WeekType.custom && this.explicitWeeks == null) {
      throw ArgumentError('自定义周次必须提供 explicitWeeks');
    }
  }

  final int startWeek;
  final int endWeek;
  final WeekType type;
  final Set<int>? explicitWeeks;

  bool includes(int week) {
    if (week < startWeek || week > endWeek) return false;
    final selected = explicitWeeks;
    if (selected != null && !selected.contains(week)) return false;
    return switch (type) {
      WeekType.odd => week.isOdd,
      WeekType.even => week.isEven,
      WeekType.every || WeekType.custom => true,
    };
  }
}

class LessonPeriod {
  const LessonPeriod({
    required this.number,
    required this.startMinutes,
    required this.endMinutes,
  }) : assert(number > 0),
       assert(startMinutes >= 0 && startMinutes < 24 * 60),
       assert(endMinutes > startMinutes && endMinutes <= 24 * 60);

  final int number;
  final int startMinutes;
  final int endMinutes;
}

/// 国家调休上班日；补哪一个星期的课由用户确认后保存在本机。
class ScheduleAdjustment {
  ScheduleAdjustment({
    required DateTime date,
    this.replacementWeek,
    this.replacementWeekday,
    this.isHoliday = false,
    this.holidayName,
  }) : date = DateTime(date.year, date.month, date.day) {
    if (replacementWeek != null && replacementWeek! < 1) {
      throw ArgumentError('替代教学周必须大于 0');
    }
    if (replacementWeekday != null &&
        (replacementWeekday! < DateTime.monday ||
            replacementWeekday! > DateTime.sunday)) {
      throw ArgumentError('替代星期必须在 1-7 之间');
    }
  }

  final DateTime date;
  final int? replacementWeek;
  final int? replacementWeekday;
  final bool isHoliday;
  final String? holidayName;

  bool matches(DateTime other) =>
      date.year == other.year &&
      date.month == other.month &&
      date.day == other.day;
}

class CourseCancellation {
  CourseCancellation({required this.sessionId, required DateTime date})
    : date = DateTime(date.year, date.month, date.day);

  final String sessionId;
  final DateTime date;

  bool matches(String otherSessionId, DateTime otherDate) =>
      sessionId == otherSessionId &&
      date.year == otherDate.year &&
      date.month == otherDate.month &&
      date.day == otherDate.day;
}

class Term {
  Term({
    required this.id,
    required this.name,
    required DateTime firstWeekMonday,
    required this.totalWeeks,
    required Map<int, List<LessonPeriod>> periodsByWeekday,
  }) : firstWeekMonday = DateTime(
         firstWeekMonday.year,
         firstWeekMonday.month,
         firstWeekMonday.day,
       ),
       periodsByWeekday = Map<int, List<LessonPeriod>>.unmodifiable({
         for (final entry in periodsByWeekday.entries)
           entry.key: List<LessonPeriod>.unmodifiable(entry.value),
       }) {
    if (this.firstWeekMonday.weekday != DateTime.monday) {
      throw ArgumentError('开学日期必须是第一周的周一');
    }
    if (totalWeeks < 1) throw ArgumentError('总周数必须大于 0');
    if (periodsByWeekday.keys.any((day) => day < 1 || day > 7)) {
      throw ArgumentError('星期必须在 1-7 之间');
    }
  }

  final String id;
  final String name;
  final DateTime firstWeekMonday;
  final int totalWeeks;
  final Map<int, List<LessonPeriod>> periodsByWeekday;

  LessonPeriod? periodFor(int weekday, int number) {
    final periods =
        periodsByWeekday[weekday] ?? periodsByWeekday[1] ?? const [];
    for (final period in periods) {
      if (period.number == number) return period;
    }
    return null;
  }
}

class Course {
  Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.colorValue,
    required List<CourseSession> sessions,
  }) : sessions = List<CourseSession>.unmodifiable(sessions);

  final String id;
  final String name;
  final String teacher;
  final int colorValue;
  final List<CourseSession> sessions;
}

/// 课程与上课时间一对多；地点和教师放在时间段上，支持单双周换教室/教师。
class CourseSession {
  const CourseSession({
    required this.id,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.weekRule,
    required this.location,
    this.teacherOverride,
  }) : assert(weekday >= 1 && weekday <= 7),
       assert(startPeriod > 0),
       assert(endPeriod >= startPeriod);

  final String id;
  final int weekday;
  final int startPeriod;
  final int endPeriod;
  final WeekRule weekRule;
  final String location;
  final String? teacherOverride;
}

class ScheduledCourse {
  const ScheduledCourse({
    required this.course,
    required this.session,
    required this.week,
    required this.startTime,
    required this.endTime,
  });

  final Course course;
  final CourseSession session;
  final int week;
  final DateTime startTime;
  final DateTime endTime;

  String get teacher => session.teacherOverride?.trim().isNotEmpty == true
      ? session.teacherOverride!.trim()
      : course.teacher;
}
