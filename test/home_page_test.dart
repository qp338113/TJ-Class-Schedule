import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';

void main() {
  testWidgets('没有学期时显示首次设置入口', (tester) async {
    await tester.pumpWidget(_appWith(const ScheduleData()));
    await tester.pumpAndSettle();

    expect(find.text('先设置你的学期'), findsOneWidget);
    expect(find.text('开始设置'), findsOneWidget);
  });

  testWidgets('今日课程可见，并能左右滑到本周视图', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final periods = [
      const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580),
    ];
    final term = Term(
      id: currentTermId,
      name: '测试学期',
      firstWeekMonday: monday,
      totalWeeks: 20,
      periodsByWeekday: {for (var day = 1; day <= 7; day++) day: periods},
    );
    final course = Course(
      id: 'course-1',
      name: '高等数学',
      teacher: '张老师',
      colorValue: 0xFF7D9DCE,
      sessions: [
        CourseSession(
          id: 'session-1',
          weekday: today.weekday,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: 'A101',
        ),
      ],
    );

    await tester.pumpWidget(
      _appWith(ScheduleData(term: term, courses: [course])),
    );
    await tester.pumpAndSettle();
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('A101 · 张老师'), findsOneWidget);
    expect(find.textContaining('第 1 周'), findsOneWidget);
    expect(find.text('添加课程'), findsOneWidget);
    expect(find.text('Powered by Algernon'), findsOneWidget);

    await tester.tap(find.text('高等数学'));
    await tester.pumpAndSettle();
    expect(find.text('修改课程'), findsNothing);

    await tester.longPress(find.text('高等数学'));
    await tester.pumpAndSettle();
    expect(find.text('修改课程'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('第 1 周 ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 3 周'));
    await tester.pumpAndSettle();
    expect(find.text('第 3 周 ▾'), findsOneWidget);

    await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('本周'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
  });
}

Widget _appWith(ScheduleData data) {
  return ProviderScope(
    overrides: [
      scheduleControllerProvider.overrideWith(
        () => _FakeScheduleController(data),
      ),
    ],
    child: const CourseScheduleApp(),
  );
}

class _FakeScheduleController extends ScheduleController {
  _FakeScheduleController(this.data);

  final ScheduleData data;

  @override
  Future<ScheduleData> build() async => data;

  @override
  Future<void> changeCourseColor(String courseId, int colorValue) async {}
}
