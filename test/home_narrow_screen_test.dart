import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';

void main() {
  testWidgets('窄屏上两个悬浮按钮不溢出', (tester) async {
    // 360x640 是常见的小屏 Android 尺寸，两个 .extended 悬浮按钮最容易在这里挤爆。
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
          day: [const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580)],
      },
    );
    final course = Course(
      id: 'c1',
      name: '高等数学',
      teacher: '张老师',
      colorValue: 0xFF7D9DCE,
      sessions: [
        CourseSession(
          id: 's1',
          weekday: today.weekday,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: 'A101',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(
            () => _FakeController(ScheduleData(term: term, courses: [course])),
          ),
          clockProvider.overrideWith((ref) => Stream.value(today)),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 溢出会以异常形式暴露；这里必须为空。
    expect(tester.takeException(), isNull);
    expect(find.text('整周课表'), findsOneWidget);
    expect(find.text('添加课程'), findsOneWidget);

    // 两个按钮的留白必须一致：Scaffold 只保证右侧 16，Row 撑满整屏时
    // 左侧会被推到屏幕外裁掉，两个按钮看起来就不对称。
    final grid = tester.getRect(find.byType(FloatingActionButton).first);
    final add = tester.getRect(find.byType(FloatingActionButton).last);
    expect(grid.left, greaterThanOrEqualTo(0));
    expect(add.right, lessThanOrEqualTo(360));
    expect(grid.left, closeTo(360 - add.right, 0.5));
  });
}

class _FakeController extends ScheduleController {
  _FakeController(this.data);

  final ScheduleData data;

  @override
  Future<ScheduleData> build() async => data;
}
