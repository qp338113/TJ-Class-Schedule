import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/presentation/course_detail_sheet.dart';

void main() {
  Term term() => Term(
    id: 'term',
    name: '测试学期',
    firstWeekMonday: DateTime(2026, 9, 14),
    totalWeeks: 16,
    periodsByWeekday: {
      for (var day = 1; day <= 7; day++)
        day: [
          const LessonPeriod(number: 5, startMinutes: 780, endMinutes: 825),
          const LessonPeriod(number: 6, startMinutes: 830, endMinutes: 875),
        ],
    },
  );

  Course course() => Course(
    id: 'course-1',
    name: 'Auto CAD工程制图',
    teacher: '徐俊、张博珊、徐骁青',
    colorValue: 0xFF7D9DCE,
    sessions: [
      CourseSession(
        id: 'session-1',
        weekday: 4,
        startPeriod: 5,
        endPeriod: 6,
        weekRule: WeekRule(
          startWeek: 1,
          endWeek: 12,
          type: WeekType.custom,
          explicitWeeks: const {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12},
        ),
        location: '土木学院机房',
        teacherOverride: '徐俊',
      ),
    ],
  );

  Future<void> open(
    WidgetTester tester, {
    CourseSession? session,
    DateTime? date,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCourseDetailSheet(
                context,
                term: term(),
                course: course(),
                session: session,
                date: date,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('详情逐项列出 App 实际存储的字段，便于与 1 系统对照', (tester) async {
    await open(tester, session: course().sessions.single, date: DateTime(2026, 10, 1));

    // 课程名与关键字段都在，且是「存储值」而不是推算值。
    expect(find.text('Auto CAD工程制图'), findsWidgets);
    expect(find.text('土木学院机房'), findsWidgets);
    expect(find.text('周四'), findsWidgets);
    expect(find.text('第 5-6 节'), findsWidgets);
    // 节次对应的钟点也要给出（第5节 13:00-13:45，第6节 13:50-14:35）。
    expect(find.text('13:00-14:35'), findsOneWidget);
    // 上课周要能看出实际是哪几周，用于发现周次解析错误。
    expect(find.text('1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12'), findsOneWidget);
    // 具体日期与教学周。
    expect(find.textContaining('2026年10月1日'), findsOneWidget);
    // 该时间段自己的教师覆盖值要显示出来，而不是只显示课程级教师。
    expect(find.text('徐俊'), findsWidgets);
  });

  testWidgets('不传某一节时也能打开，并列出全部时间段', (tester) async {
    await open(tester);

    expect(find.textContaining('这门课的全部时间段（1 条）'), findsOneWidget);
    expect(find.textContaining('Auto CAD工程制图'), findsWidgets);
  });

  group('周次展开', () {
    test('单双周只列出实际会上的周次', () {
      final rule = WeekRule(startWeek: 2, endWeek: 16, type: WeekType.even);
      expect(weeksOf(rule, 16), [2, 4, 6, 8, 10, 12, 14, 16]);
      expect(weekCount(rule, 16), 8);
    });

    test('自定义周次按升序列出', () {
      final rule = WeekRule(
        startWeek: 1,
        endWeek: 16,
        type: WeekType.custom,
        explicitWeeks: const {15, 1, 3},
      );
      expect(weeksText(rule, 16), '1, 3, 15');
    });

    test('学期总周数限制展开范围', () {
      final rule = WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every);
      expect(weekCount(rule, 16), 16);
    });
  });

  test('教师取该时间段的覆盖值，没有覆盖时回落到课程级', () {
    final course = Course(
      id: 'c',
      name: '某课',
      teacher: '课程级老师',
      colorValue: 0xFF000000,
      sessions: [
        CourseSession(
          id: 's1',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
          location: 'A101',
          teacherOverride: '时间段老师',
        ),
        CourseSession(
          id: 's2',
          weekday: 2,
          startPeriod: 1,
          endPeriod: 2,
          weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
          location: 'A102',
        ),
      ],
    );

    expect(effectiveTeacher(course, course.sessions[0]), '时间段老师');
    expect(effectiveTeacher(course, course.sessions[1]), '课程级老师');
  });
}
