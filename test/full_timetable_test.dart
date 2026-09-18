import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';
import 'package:offline_course_schedule/presentation/full_timetable_page.dart';

void main() {
  group('周次展示文本', () {
    test('每周、单周、双周各带后缀', () {
      expect(
        WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every).displayText,
        '1-16周',
      );
      expect(
        WeekRule(startWeek: 1, endWeek: 16, type: WeekType.odd).displayText,
        '1-16周(单)',
      );
      expect(
        WeekRule(startWeek: 2, endWeek: 18, type: WeekType.even).displayText,
        '2-18周(双)',
      );
    });

    test('不连续周次把连续三段以上合并成区间', () {
      expect(
        WeekRule(
          startWeek: 1,
          endWeek: 16,
          type: WeekType.custom,
          explicitWeeks: const {1, 3, 5, 6, 7, 8, 9},
        ).displayText,
        '1,3,5-9周',
      );
    });

    test('零散周次逐个列出、升序', () {
      expect(
        WeekRule(
          startWeek: 1,
          endWeek: 16,
          type: WeekType.custom,
          explicitWeeks: const {4, 2, 6},
        ).displayText,
        '2,4,6周',
      );
    });
  });

  group('整周课表网格', () {
    testWidgets('渲染课程名、7 个周几标题与节次标签', (tester) async {
      final fixture = _gridFixture();
      await tester.pumpWidget(
        _gridApp(term: fixture.term, courses: fixture.courses),
      );
      await tester.pumpAndSettle();

      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('A101'), findsOneWidget);
      expect(find.text('张老师'), findsOneWidget);
      expect(find.text('1-16周'), findsOneWidget);
      for (final label in ['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('第1节'), findsOneWidget);
      expect(find.text('第2节'), findsOneWidget);
    });

    testWidgets('同一格内重叠的两门课并排显示且互不遮挡', (tester) async {
      final term = _term();
      final base = WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every);
      final courses = [
        Course(
          id: 'a',
          name: '重叠课甲',
          teacher: '甲老师',
          colorValue: 0xFF7D9DCE,
          sessions: [
            CourseSession(
              id: 'sa',
              weekday: 3,
              startPeriod: 1,
              endPeriod: 2,
              weekRule: base,
              location: '甲楼',
            ),
          ],
        ),
        Course(
          id: 'b',
          name: '重叠课乙',
          teacher: '乙老师',
          colorValue: 0xFFB497C9,
          sessions: [
            CourseSession(
              id: 'sb',
              weekday: 3,
              startPeriod: 2,
              endPeriod: 3,
              weekRule: base,
              location: '乙楼',
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        _gridApp(term: term, courses: courses),
      );
      await tester.pumpAndSettle();

      final left = tester.getTopLeft(find.text('重叠课甲')).dx;
      final right = tester.getTopLeft(find.text('重叠课乙')).dx;
      expect(left, isNot(equals(right)), reason: '重叠课程应并排而非叠在同一位置');
    });

    testWidgets('互不重叠的课程各占满整列宽度', (tester) async {
      final base = WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every);
      final courses = [
        Course(
          id: 'a',
          name: '上午课',
          teacher: '甲老师',
          colorValue: 0xFF7D9DCE,
          sessions: [
            CourseSession(
              id: 'sa',
              weekday: 1,
              startPeriod: 1,
              endPeriod: 1,
              weekRule: base,
              location: '甲楼',
            ),
          ],
        ),
        Course(
          id: 'b',
          name: '下午课',
          teacher: '乙老师',
          colorValue: 0xFFB497C9,
          sessions: [
            CourseSession(
              id: 'sb',
              weekday: 1,
              startPeriod: 2,
              endPeriod: 2,
              weekRule: base,
              location: '乙楼',
            ),
          ],
        ),
      ];

      await tester.pumpWidget(_gridApp(term: _term(), courses: courses));
      await tester.pumpAndSettle();

      // 不重叠时应左对齐、无并排收缩。
      expect(
        tester.getTopLeft(find.text('上午课')).dx,
        tester.getTopLeft(find.text('下午课')).dx,
      );
    });

    testWidgets('本学期没有课程时给出提示', (tester) async {
      await tester.pumpWidget(_gridApp(term: _term(), courses: const []));
      await tester.pumpAndSettle();

      expect(find.text('本学期还没有课程'), findsOneWidget);
    });
  });

  group('主界面入口', () {
    testWidgets('左下角有整周课表按钮，点击可打开网格页，且备忘录不进入网格', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final term = Term(
        id: currentTermId,
        name: '测试学期',
        firstWeekMonday: monday,
        totalWeeks: 20,
        periodsByWeekday: {
          for (var day = 1; day <= 7; day++)
            day: [
              const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580),
              const LessonPeriod(number: 2, startMinutes: 580, endMinutes: 680),
            ],
        },
      );
      final course = Course(
        id: 'course-1',
        name: '高等数学',
        teacher: '张老师',
        colorValue: 0xFF7D9DCE,
        sessions: [
          CourseSession(
            id: 'session-1',
            weekday: 1,
            startPeriod: 1,
            endPeriod: 1,
            weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
            location: 'A101',
          ),
        ],
      );
      final memo = Memo(
        id: 'memo-1',
        title: '小组会议',
        colorValue: 0xFFD0B36C,
        weekday: 1,
        startPeriod: 2,
        endPeriod: 2,
        weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
      );

      await tester.pumpWidget(
        _homeApp(
          ScheduleData(term: term, courses: [course], memos: [memo]),
        ),
      );
      await tester.pumpAndSettle();

      // 两个悬浮按钮同时存在，且不因并排而溢出。
      expect(find.text('整周课表'), findsOneWidget);
      expect(find.text('添加课程'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('整周课表'));
      await tester.pumpAndSettle();

      expect(find.byType(FullTimetablePage), findsOneWidget);
      expect(find.text('高等数学'), findsOneWidget);
      // 整周课表只显示课程。
      expect(find.text('小组会议'), findsNothing);
    });
  });
}

Widget _gridApp({required Term term, required List<Course> courses}) {
  return MaterialApp(
    home: FullTimetablePage(term: term, courses: courses),
  );
}

Widget _homeApp(ScheduleData data) {
  return ProviderScope(
    overrides: [
      scheduleControllerProvider.overrideWith(() => _FakeScheduleController(data)),
      // 固定“现在”为当天 00:00，避免傍晚运行测试时触发“课上完跳到第二天”。
      clockProvider.overrideWith((ref) {
        final now = DateTime.now();
        return Stream.value(DateTime(now.year, now.month, now.day));
      }),
    ],
    child: const CourseScheduleApp(),
  );
}

Term _term() => Term(
      id: currentTermId,
      name: '测试学期',
      firstWeekMonday: DateTime(2026, 9, 7),
      totalWeeks: 20,
      periodsByWeekday: {
        for (var day = 1; day <= 7; day++)
          day: [
            const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580),
            const LessonPeriod(number: 2, startMinutes: 580, endMinutes: 680),
            const LessonPeriod(number: 3, startMinutes: 680, endMinutes: 780),
          ],
      },
    );

({Term term, List<Course> courses}) _gridFixture() {
  final term = _term();
  final courses = [
    Course(
      id: 'course-1',
      name: '高等数学',
      teacher: '张老师',
      colorValue: 0xFF7D9DCE,
      sessions: [
        CourseSession(
          id: 'session-1',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
          location: 'A101',
        ),
      ],
    ),
  ];
  return (term: term, courses: courses);
}

class _FakeScheduleController extends ScheduleController {
  _FakeScheduleController(this.data);

  final ScheduleData data;

  @override
  Future<ScheduleData> build() async => data;
}
