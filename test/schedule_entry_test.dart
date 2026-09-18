import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_engine.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';

void main() {
  final periods = [
    const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525),
    const LessonPeriod(number: 2, startMinutes: 535, endMinutes: 580),
    const LessonPeriod(number: 3, startMinutes: 600, endMinutes: 645),
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
      colorValue: 0,
      sessions: [
        CourseSession(
          id: 'math-monday',
          weekday: DateTime.monday,
          startPeriod: 2,
          endPeriod: 2,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: 'A101',
        ),
      ],
    ),
  ];
  // 一次性：第一周周一 08:00-08:30
  final onceMemo = Memo(
    id: 'memo-once',
    title: '交作业',
    location: '图书馆',
    colorValue: 0,
    date: DateTime(2026, 9, 7),
    startMinutes: 480,
    endMinutes: 510,
  );
  // 按周重复：单周周一第 3 节
  final repeatMemo = Memo(
    id: 'memo-repeat',
    title: '英语角',
    colorValue: 0,
    weekday: DateTime.monday,
    startPeriod: 3,
    endPeriod: 3,
    weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.odd),
  );

  test('某天的课程与备忘录合并后按开始时间排序', () {
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      memos: [repeatMemo, onceMemo],
    );

    final entries = engine.getEntriesForDate(DateTime(2026, 9, 7, 23, 30));

    expect(entries.map((entry) => entry.title), ['交作业', '数学', '英语角']);
    expect(entries.map((entry) => entry.isMemo), [true, false, true]);
    expect(entries.first.startTime, DateTime(2026, 9, 7, 8));
    expect(entries.first.endTime, DateTime(2026, 9, 7, 8, 30));
    expect(entries.first.location, '图书馆');
    expect(entries.first.teacher, '');
    expect(entries[1].startTime, DateTime(2026, 9, 7, 8, 55));
    expect(entries[1].endTime, DateTime(2026, 9, 7, 9, 40));
    expect(entries[1].teacher, '张老师');
    expect(entries[2].startTime, DateTime(2026, 9, 7, 10));
    expect(entries[2].endTime, DateTime(2026, 9, 7, 10, 45));
    expect(entries[2].location, '');
  });

  test('开始时间相同时课程排在备忘录前面', () {
    final tieMemo = Memo(
      id: 'memo-tie',
      title: '班会',
      colorValue: 0,
      date: DateTime(2026, 9, 7),
      startMinutes: 535,
      endMinutes: 540,
    );
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      memos: [tieMemo],
    );

    final entries = engine.getEntriesForDate(DateTime(2026, 9, 7));

    expect(entries.map((entry) => entry.title), ['数学', '班会']);
    expect(entries.first.isMemo, isFalse);
  });

  test('一次性备忘录只在当天出现', () {
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      memos: [onceMemo],
    );

    expect(engine.getEntriesForDate(DateTime(2026, 9, 7)).first.title, '交作业');
    expect(
      engine.getEntriesForDate(DateTime(2026, 9, 8)).map((e) => e.title),
      isEmpty,
    );
    expect(
      engine.getEntriesForDate(DateTime(2026, 9, 14)).map((e) => e.title),
      ['数学'],
    );
  });

  test('按周重复的备忘录遵守周次规则', () {
    final engine = ScheduleEngine(
      term: term,
      courses: const [],
      memos: [repeatMemo],
    );

    expect(
      engine.getEntriesForDate(DateTime(2026, 9, 7)).map((e) => e.title),
      ['英语角'],
    );
    expect(engine.getEntriesForDate(DateTime(2026, 9, 14)), isEmpty);
    expect(
      engine.getEntriesForDate(DateTime(2026, 9, 21)).map((e) => e.title),
      ['英语角'],
    );
  });

  test('调休日按替代星期返回备忘录，时间落在实际日期', () {
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      memos: [onceMemo, repeatMemo],
      adjustments: [
        ScheduleAdjustment(
          date: DateTime(2026, 9, 19),
          replacementWeek: 3,
          replacementWeekday: DateTime.monday,
        ),
      ],
    );

    final entries = engine.getEntriesForDate(DateTime(2026, 9, 19));

    expect(entries.map((entry) => entry.title), ['数学', '英语角']);
    expect(entries.first.startTime, DateTime(2026, 9, 19, 8, 55));
    expect(entries.last.startTime, DateTime(2026, 9, 19, 10));
    expect(entries.last.endTime, DateTime(2026, 9, 19, 10, 45));
    expect(engine.getWeekForDate(DateTime(2026, 9, 19)), 2);
  });

  test('节假日不返回任何课程与备忘录', () {
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      memos: [onceMemo, repeatMemo],
      adjustments: [
        ScheduleAdjustment(
          date: DateTime(2026, 9, 7),
          isHoliday: true,
          holidayName: '中秋节',
        ),
      ],
    );

    expect(engine.getEntriesForDate(DateTime(2026, 9, 7)), isEmpty);
  });

  test('临时停课只隐藏课程，不影响当天的备忘录', () {
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      memos: [onceMemo, repeatMemo],
      cancellations: [
        CourseCancellation(sessionId: 'math-monday', date: DateTime(2026, 9, 7)),
      ],
    );

    final entries = engine.getEntriesForDate(DateTime(2026, 9, 7));

    expect(entries.map((entry) => entry.title), ['交作业', '英语角']);
    expect(entries.every((entry) => entry.isMemo), isTrue);
  });

  test('传入备忘录后 getCoursesForDate 行为完全不变', () {
    final before = ScheduleEngine(term: term, courses: courses);
    final after = ScheduleEngine(
      term: term,
      courses: courses,
      memos: [onceMemo, repeatMemo],
    );

    for (final date in [
      DateTime(2026, 9, 7),
      DateTime(2026, 9, 14),
      DateTime(2026, 9, 21),
      DateTime(2026, 9, 6),
    ]) {
      final expected = before.getCoursesForDate(date);
      final actual = after.getCoursesForDate(date);
      expect(actual.length, expected.length);
      for (var index = 0; index < expected.length; index++) {
        expect(actual[index].course.id, expected[index].course.id);
        expect(actual[index].startTime, expected[index].startTime);
        expect(actual[index].endTime, expected[index].endTime);
        expect(actual[index].week, expected[index].week);
      }
    }
    expect(after.getCoursesForDate(DateTime(2026, 9, 7)).length, 1);
  });

  test('合并结果里的课程部分与 getCoursesForDate 一致', () {
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      memos: [onceMemo, repeatMemo],
    );
    final date = DateTime(2026, 9, 7);

    final courseEntries = engine
        .getEntriesForDate(date)
        .where((entry) => !entry.isMemo)
        .toList();

    final coursesOnly = engine.getCoursesForDate(date);
    expect(courseEntries.length, coursesOnly.length);
    expect(courseEntries.first.title, coursesOnly.first.course.name);
    expect(courseEntries.first.startTime, coursesOnly.first.startTime);
  });
}
