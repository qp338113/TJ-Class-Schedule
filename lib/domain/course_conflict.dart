import 'schedule_models.dart';

class CourseConflict {
  const CourseConflict({
    required this.firstCourse,
    required this.secondCourse,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.week,
  });

  final String firstCourse;
  final String secondCourse;
  final int weekday;
  final int startPeriod;
  final int endPeriod;
  final int week;
}

List<CourseConflict> findCourseConflicts(Iterable<Course> source) {
  final entries = [
    for (final course in source)
      for (final session in course.sessions) (course: course, session: session),
  ];
  final result = <CourseConflict>[];
  for (var first = 0; first < entries.length; first++) {
    for (var second = first + 1; second < entries.length; second++) {
      final a = entries[first];
      final b = entries[second];
      if (a.session.weekday != b.session.weekday) continue;
      final start = a.session.startPeriod > b.session.startPeriod
          ? a.session.startPeriod
          : b.session.startPeriod;
      final end = a.session.endPeriod < b.session.endPeriod
          ? a.session.endPeriod
          : b.session.endPeriod;
      if (start > end) continue;
      final firstWeek =
          a.session.weekRule.startWeek > b.session.weekRule.startWeek
          ? a.session.weekRule.startWeek
          : b.session.weekRule.startWeek;
      final lastWeek = a.session.weekRule.endWeek < b.session.weekRule.endWeek
          ? a.session.weekRule.endWeek
          : b.session.weekRule.endWeek;
      for (var week = firstWeek; week <= lastWeek; week++) {
        if (a.session.weekRule.includes(week) &&
            b.session.weekRule.includes(week)) {
          result.add(
            CourseConflict(
              firstCourse: a.course.name,
              secondCourse: b.course.name,
              weekday: a.session.weekday,
              startPeriod: start,
              endPeriod: end,
              week: week,
            ),
          );
          break;
        }
      }
    }
  }
  return List<CourseConflict>.unmodifiable(result);
}
