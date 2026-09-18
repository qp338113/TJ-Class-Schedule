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

  group('教学周与日期互换', () {
    final term = Term(
      id: 'term',
      name: '测试学期',
      firstWeekMonday: DateTime(2026, 9, 14),
      totalWeeks: 18,
      periodsByWeekday: {
        1: const [LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525)],
      },
    );

    test('9月20日补第 4 周周二：日期能算出周次和星期', () {
      // 第 4 周周二是 10 月 6 日；9 月 20 日是第 1 周周日。
      expect(term.dateOf(4, DateTime.tuesday), DateTime(2026, 10, 6));
      expect(term.weekOf(DateTime(2026, 10, 6)), 4);
      expect(DateTime(2026, 10, 6).weekday, DateTime.tuesday);
    });

    test('任意日期都能还原成周次加星期', () {
      for (var week = 1; week <= term.totalWeeks; week++) {
        for (var weekday = 1; weekday <= 7; weekday++) {
          final date = term.dateOf(week, weekday);
          expect(term.weekOf(date), week, reason: '第 $week 周$weekday 无法还原');
          expect(date.weekday, weekday);
        }
      }
    });

    test('学期开始前与结束后返回 null', () {
      expect(term.weekOf(DateTime(2026, 9, 13)), isNull);
      expect(term.weekOf(term.firstWeekMonday), 1);
      expect(term.lastDay, DateTime(2027, 1, 17));
      expect(term.weekOf(term.lastDay), term.totalWeeks);
      expect(term.weekOf(term.lastDay.add(const Duration(days: 1))), isNull);
    });
  });
}
