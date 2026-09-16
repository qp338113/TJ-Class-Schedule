import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/course_conflict.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';

void main() {
  Course course(String id, WeekType type, int start, int end) => Course(
    id: id,
    name: id,
    teacher: '',
    colorValue: 0,
    sessions: [
      CourseSession(
        id: '$id-session',
        weekday: DateTime.monday,
        startPeriod: start,
        endPeriod: end,
        weekRule: WeekRule(startWeek: 1, endWeek: 16, type: type),
        location: '',
      ),
    ],
  );

  test('同一天同周且节次重叠会报告冲突', () {
    final conflicts = findCourseConflicts([
      course('数学', WeekType.every, 1, 2),
      course('英语', WeekType.every, 2, 3),
    ]);
    expect(conflicts, hasLength(1));
    expect(conflicts.single.week, 1);
    expect(conflicts.single.startPeriod, 2);
  });

  test('单周课程和双周课程不冲突', () {
    expect(
      findCourseConflicts([
        course('数学', WeekType.odd, 1, 2),
        course('英语', WeekType.even, 1, 2),
      ]),
      isEmpty,
    );
  });
}
