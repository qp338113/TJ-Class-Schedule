import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_engine.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';

void main() {
  final periods = [
    const LessonPeriod(
      number: 1,
      startMinutes: 8 * 60,
      endMinutes: 8 * 60 + 45,
    ),
    const LessonPeriod(
      number: 2,
      startMinutes: 8 * 60 + 55,
      endMinutes: 9 * 60 + 40,
    ),
    const LessonPeriod(
      number: 3,
      startMinutes: 10 * 60,
      endMinutes: 10 * 60 + 45,
    ),
  ];
  final term = Term(
    id: 'term-1',
    name: '2026 秋季',
    firstWeekMonday: DateTime(2026, 9, 7),
    totalWeeks: 20,
    periodsByWeekday: {for (var day = 1; day <= 7; day++) day: periods},
  );
  final courses = [
    Course(
      id: 'math',
      name: '数学',
      teacher: '张老师',
      colorValue: 0xFF7D9DCE,
      sessions: [
        CourseSession(
          id: 'math-odd',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.odd),
          location: 'A101',
        ),
      ],
    ),
    Course(
      id: 'english',
      name: '英语',
      teacher: '李老师',
      colorValue: 0xFF7FB69D,
      sessions: [
        CourseSession(
          id: 'english-every',
          weekday: 1,
          startPeriod: 3,
          endPeriod: 3,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: 'B202',
        ),
      ],
    ),
  ];

  late ScheduleEngine engine;
  setUp(() => engine = ScheduleEngine(term: term, courses: courses));

  test('第一周周一是单周，按开始时间排序', () {
    final result = engine.getCoursesForDate(DateTime(2026, 9, 7, 23, 30));
    expect(result.map((item) => item.course.name), ['数学', '英语']);
    expect(result.first.week, 1);
    expect(result.first.startTime, DateTime(2026, 9, 7, 8));
    expect(result.first.endTime, DateTime(2026, 9, 7, 9, 40));
  });

  test('第二周周一不返回单周课程', () {
    final result = engine.getCoursesForDate(DateTime(2026, 9, 14));
    expect(result.map((item) => item.course.name), ['英语']);
    expect(result.single.week, 2);
  });

  test('学期开始前和结束后都不显示课程', () {
    expect(engine.getCoursesForDate(DateTime(2026, 9, 6)), isEmpty);
    expect(engine.getCoursesForDate(DateTime(2027, 1, 25)), isEmpty);
  });

  test('统一周次函数返回教学周，学期外返回空', () {
    expect(engine.getWeekForDate(DateTime(2026, 9, 7)), 1);
    expect(engine.getWeekForDate(DateTime(2026, 9, 20)), 2);
    expect(engine.getWeekForDate(DateTime(2026, 9, 6)), isNull);
  });

  test('学期最后一天仍在范围内', () {
    final sundayCourse = Course(
      id: 'sunday',
      name: '周日课程',
      teacher: '',
      colorValue: 0,
      sessions: [
        CourseSession(
          id: 'sunday-session',
          weekday: 7,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 20, endWeek: 20, type: WeekType.every),
          location: '',
        ),
      ],
    );
    final lastDayEngine = ScheduleEngine(term: term, courses: [sundayCourse]);
    final result = lastDayEngine.getCoursesForDate(DateTime(2027, 1, 24));
    expect(result.single.week, 20);
  });

  test('临时停课只隐藏指定日期的指定时间段', () {
    final cancelled = ScheduleEngine(
      term: term,
      courses: courses,
      cancellations: [
        CourseCancellation(
          sessionId: 'english-every',
          date: DateTime(2026, 9, 7),
        ),
      ],
    );
    expect(
      cancelled
          .getCoursesForDate(DateTime(2026, 9, 7))
          .map((item) => item.course.name),
      ['数学'],
    );
    expect(
      cancelled
          .getCoursesForDate(DateTime(2026, 9, 14))
          .map((item) => item.course.name),
      ['英语'],
    );
  });
}
