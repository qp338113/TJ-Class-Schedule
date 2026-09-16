import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_engine.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';

void main() {
  test('调休日按指定教学周和星期返回课程，但时间仍落在实际日期', () {
    final term = Term(
      id: 'term',
      name: '测试学期',
      firstWeekMonday: DateTime(2026, 9, 14),
      totalWeeks: 20,
      periodsByWeekday: {
        for (var day = 1; day <= 7; day++)
          day: const [
            LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525),
          ],
      },
    );
    final courses = [
      Course(
        id: 'tuesday',
        name: '周二课程',
        teacher: '',
        colorValue: 0,
        sessions: [
          CourseSession(
            id: 'session',
            weekday: DateTime.tuesday,
            startPeriod: 1,
            endPeriod: 1,
            weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.even),
            location: '教室',
          ),
        ],
      ),
    ];
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      adjustments: [
        ScheduleAdjustment(
          date: DateTime(2026, 9, 20),
          replacementWeek: 4,
          replacementWeekday: DateTime.tuesday,
        ),
      ],
    );

    final result = engine.getCoursesForDate(DateTime(2026, 9, 20));

    expect(result.single.course.name, '周二课程');
    expect(result.single.startTime, DateTime(2026, 9, 20, 8));
    expect(engine.getWeekForDate(DateTime(2026, 9, 20)), 1);
    expect(result.single.week, 4);
  });

  test('国家法定节假日不返回任何课程', () {
    final term = Term(
      id: 'term',
      name: '测试学期',
      firstWeekMonday: DateTime(2026, 9, 14),
      totalWeeks: 20,
      periodsByWeekday: {
        DateTime.friday: const [
          LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525),
        ],
      },
    );
    final course = Course(
      id: 'course',
      name: '周五课程',
      teacher: '',
      colorValue: 0,
      sessions: [
        CourseSession(
          id: 'session',
          weekday: DateTime.friday,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: '',
        ),
      ],
    );
    final engine = ScheduleEngine(
      term: term,
      courses: [course],
      adjustments: [
        ScheduleAdjustment(
          date: DateTime(2026, 9, 25),
          isHoliday: true,
          holidayName: '中秋节',
        ),
      ],
    );

    expect(engine.getCoursesForDate(DateTime(2026, 9, 25)), isEmpty);
    expect(engine.adjustmentForDate(DateTime(2026, 9, 25))?.holidayName, '中秋节');
  });
}
