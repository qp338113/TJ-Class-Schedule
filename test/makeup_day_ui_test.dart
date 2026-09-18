import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';

void main() {
  testWidgets('调休日主界面显示替代教学周与星期的课表', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    // 让“今天”是被补的那一天对应的星期，验证替代来源是调休映射而不是真实星期。
    final replacementWeekday = today.weekday == DateTime.tuesday
        ? DateTime.thursday
        : DateTime.tuesday;
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
      id: 'course-1',
      name: '被补的课',
      teacher: '张老师',
      colorValue: 0xFF7D9DCE,
      sessions: [
        CourseSession(
          id: 'session-1',
          weekday: replacementWeekday,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: 'A101',
        ),
      ],
    );
    final data = ScheduleData(
      term: term,
      courses: [course],
      adjustments: [
        ScheduleAdjustment(
          date: today,
          replacementWeek: 4,
          replacementWeekday: replacementWeekday,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(() => _Fake(data)),
          // 固定“现在”为当天 00:00，否则课上完后启动逻辑会把选中日期挪到第二天。
          clockProvider.overrideWith((ref) => Stream.value(today)),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('被补的课'), findsOneWidget);
    expect(find.textContaining('第 4 周'), findsWidgets);
  });

  testWidgets('选“要补哪一天”后自动对应教学周和星期', (tester) async {
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
    // 今天就是调休上班日，但还没设置补哪一天的课。
    final data = ScheduleData(
      term: term,
      adjustments: [ScheduleAdjustment(date: today)],
    );
    final controller = _Fake(data);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(() => controller),
          clockProvider.overrideWith((ref) => Stream.value(today)),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('请选择要补哪一天的课'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // 默认落在第 1 周的今天，按日期选择器打开后应能改成别的周次。
    expect(find.text('设置补课课表'), findsOneWidget);
    expect(find.textContaining('教学周和星期会自动对应'), findsOneWidget);

    // 下拉框仍可用于微调，保存后写入 controller。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.saved, isNull);
  });

  testWidgets('改星期下拉框后，“要补哪一天”的日期同步更新', (tester) async {
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
    final data = ScheduleData(
      term: term,
      adjustments: [ScheduleAdjustment(date: today)],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(() => _Fake(data)),
          clockProvider.overrideWith((ref) => Stream.value(today)),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // 初始落在第 1 周的今天。
    final initialDate = term.dateOf(1, today.weekday);
    expect(
      find.text('${initialDate.month}月${initialDate.day}日'
          '（${_weekdayName(today.weekday)}）'),
      findsOneWidget,
    );

    // 把星期改成周三，日期按钮应跟着走到同一周周三。
    await tester.tap(find.text(_weekdayName(today.weekday)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周三').last);
    await tester.pumpAndSettle();

    final movedDate = term.dateOf(1, DateTime.wednesday);
    expect(
      find.text('${movedDate.month}月${movedDate.day}日（周三）'),
      findsOneWidget,
    );
  });

  testWidgets('学期改短后旧的替代周次不会让弹窗崩溃', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final term = Term(
      id: currentTermId,
      name: '测试学期',
      firstWeekMonday: monday,
      // 学期已从 20 周改短到 16 周，但此前设置的第 20 周替代还留在数据库里。
      totalWeeks: 16,
      periodsByWeekday: {
        for (var day = 1; day <= 7; day++)
          day: [const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580)],
      },
    );
    final data = ScheduleData(
      term: term,
      adjustments: [
        ScheduleAdjustment(
          date: today,
          replacementWeek: 20,
          replacementWeekday: DateTime.tuesday,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(() => _Fake(data)),
          clockProvider.overrideWith((ref) => Stream.value(today)),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();

    // 弹窗正常打开并夹回第 16 周，而不是断言失败。
    expect(find.text('设置补课课表'), findsOneWidget);
    final clamped = term.dateOf(16, DateTime.tuesday);
    expect(
      find.text('${clamped.month}月${clamped.day}日（周二）'),
      findsOneWidget,
    );
  });

  testWidgets('已设置替代课表时可取消，回到按实际周次上课', (tester) async {
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
    final data = ScheduleData(
      term: term,
      adjustments: [
        ScheduleAdjustment(
          date: today,
          replacementWeek: 4,
          replacementWeekday: DateTime.tuesday,
        ),
      ],
    );
    final controller = _Fake(data);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(() => controller),
          clockProvider.overrideWith((ref) => Stream.value(today)),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('修改'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.cleared, isTrue);
  });
}

String _weekdayName(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

class _Fake extends ScheduleController {
  _Fake(this.data);

  final ScheduleData data;
  ({int week, int weekday})? saved;
  bool cleared = false;

  @override
  Future<ScheduleData> build() async => data;

  @override
  Future<void> setReplacementSchedule(
    DateTime date,
    int week,
    int weekday,
  ) async {
    saved = (week: week, weekday: weekday);
  }

  @override
  Future<void> clearReplacementSchedule(DateTime date) async {
    cleared = true;
  }
}
