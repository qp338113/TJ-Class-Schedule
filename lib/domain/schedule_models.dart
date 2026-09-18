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

  /// 展示用文本，例如 `1-16周`、`1-16周(单)`、`1,3,5-9周`。只看不改判定逻辑。
  String get displayText {
    if (type != WeekType.custom) {
      final suffix = switch (type) {
        WeekType.odd => '(单)',
        WeekType.even => '(双)',
        WeekType.every || WeekType.custom => '',
      };
      return '$startWeek-$endWeek周$suffix';
    }
    final weeks = (explicitWeeks ?? const <int>{}).toList()..sort();
    final parts = <String>[];
    var index = 0;
    while (index < weeks.length) {
      var end = index;
      while (end + 1 < weeks.length && weeks[end + 1] == weeks[end] + 1) {
        end++;
      }
      // 连续三段以上才合并成区间，否则逐个列出更好读。
      parts.add(end - index >= 2
          ? '${weeks[index]}-${weeks[end]}'
          : weeks.sublist(index, end + 1).join(','));
      index = end + 1;
    }
    return '${parts.join(',')}周';
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

  /// 学期最后一天，即最后一周的周日。
  DateTime get lastDay =>
      firstWeekMonday.add(Duration(days: totalWeeks * 7 - 1));

  /// 第 [week] 周 [weekday] 对应的真实日期。
  ///
  /// 与 [weekOf] 互为逆运算，调休设置界面靠它把「补哪一天的课」显示出来。
  DateTime dateOf(int week, int weekday) =>
      firstWeekMonday.add(Duration(days: (week - 1) * 7 + weekday - 1));

  /// [date] 落在第几教学周；学期开始前或结束后返回 null。
  ///
  /// 用 UTC 只表示“公历日序号”，避免夏令时让两个本地午夜之间不足 24 小时。
  int? weekOf(DateTime date) {
    final elapsed = DateTime.utc(date.year, date.month, date.day)
        .difference(
          DateTime.utc(
            firstWeekMonday.year,
            firstWeekMonday.month,
            firstWeekMonday.day,
          ),
        )
        .inDays;
    final week = elapsed ~/ 7 + 1;
    return elapsed < 0 || week < 1 || week > totalWeeks ? null : week;
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

/// 用户自建的备忘录，与课程无关，可以自己设置标题、地点和时间。
///
/// 一条备忘录只描述一个时间，因此两种时间类型有且只有一种生效：按周重复时使用
/// [weekday]、[startPeriod]、[endPeriod] 和 [weekRule]；一次性时使用 [date]、
/// [startMinutes] 和 [endMinutes]。混用或都不填都会抛出 [ArgumentError]。
class Memo {
  Memo({
    required this.id,
    required this.title,
    this.location = '',
    required this.colorValue,
    this.weekday,
    this.startPeriod,
    this.endPeriod,
    this.weekRule,
    DateTime? date,
    this.startMinutes,
    this.endMinutes,
  }) : date = date == null
           ? null
           : DateTime(date.year, date.month, date.day) {
    if (title.trim().isEmpty) {
      throw ArgumentError('备忘录标题不能为空');
    }
    final hasRepeat =
        weekday != null ||
        startPeriod != null ||
        endPeriod != null ||
        weekRule != null;
    final hasMoment = startMinutes != null || endMinutes != null;
    if (this.date == null) {
      if (hasMoment) {
        throw ArgumentError('按周重复的备忘录不能设置具体时刻');
      }
      if (!hasRepeat) {
        throw ArgumentError('备忘录必须提供按周重复或一次性时间');
      }
      if (weekday == null ||
          startPeriod == null ||
          endPeriod == null ||
          weekRule == null) {
        throw ArgumentError('按周重复的备忘录必须同时提供星期、起止节次和周次规则');
      }
      if (weekday! < 1 || weekday! > 7) {
        throw ArgumentError('备忘录星期必须在 1-7 之间');
      }
      if (startPeriod! < 1) {
        throw ArgumentError('备忘录起始节次必须大于 0');
      }
      if (endPeriod! < startPeriod!) {
        throw ArgumentError('备忘录结束节次不能早于起始节次');
      }
    } else {
      if (hasRepeat) {
        throw ArgumentError('一次性备忘录不能设置星期、节次或周次规则');
      }
      if (startMinutes == null || endMinutes == null) {
        throw ArgumentError('一次性备忘录必须同时提供起止时刻');
      }
      if (startMinutes! < 0 || startMinutes! >= 24 * 60) {
        throw ArgumentError('备忘录起始时刻必须在 0 到 1439 分钟之间');
      }
      if (endMinutes! <= startMinutes! || endMinutes! > 24 * 60) {
        throw ArgumentError('备忘录结束时刻必须晚于起始时刻且不超过 1440 分钟');
      }
    }
  }

  final String id;
  final String title;
  final String location;
  final int colorValue;

  /// 按周重复时使用，此时 [date]、[startMinutes]、[endMinutes] 必为 null。
  final int? weekday;
  final int? startPeriod;
  final int? endPeriod;
  final WeekRule? weekRule;

  /// 一次性时使用，此时 [weekday]、[startPeriod]、[endPeriod]、[weekRule]
  /// 必为 null；[date] 只保留年月日。
  final DateTime? date;
  final int? startMinutes;
  final int? endMinutes;

  bool get isRecurring => date == null;
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

/// 某一天里的一条安排：统一表达“课程”和“用户自建的备忘录”。
///
/// 界面、提醒和小组件只依赖 [startTime]、[endTime]、[title]、[location]、
/// [teacher] 与 [isMemo]，因此不必为两种类型各写一套排序与筛选逻辑。
sealed class ScheduleEntry {
  const ScheduleEntry();

  DateTime get startTime;
  DateTime get endTime;
  String get title;
  String get location;
  String get teacher;

  /// 这条安排是否为备忘录（用于区分提醒的提前时间与文案）。
  bool get isMemo;
}

class CourseEntry extends ScheduleEntry {
  const CourseEntry(this.course);

  final ScheduledCourse course;

  @override
  DateTime get startTime => course.startTime;
  @override
  DateTime get endTime => course.endTime;
  @override
  String get title => course.course.name;
  @override
  String get location => course.session.location;
  @override
  String get teacher => course.teacher;
  @override
  bool get isMemo => false;
}

class MemoEntry extends ScheduleEntry {
  const MemoEntry({
    required this.memo,
    required this.startTime,
    required this.endTime,
  });

  final Memo memo;

  @override
  final DateTime startTime;
  @override
  final DateTime endTime;
  @override
  String get title => memo.title;
  @override
  String get location => memo.location;

  /// 备忘录没有教师，统一返回空字符串。
  @override
  String get teacher => '';
  @override
  bool get isMemo => true;
}
