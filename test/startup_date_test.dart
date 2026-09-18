import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/startup_date.dart';
import 'package:offline_course_schedule/domain/schedule_engine.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';

void main() {
  // 第一周周一固定为 2026-09-07，第 1 节 08:00-08:45。
  final periods = [
    const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525),
    const LessonPeriod(number: 2, startMinutes: 530, endMinutes: 575),
  ];
  final term = Term(
    id: 'term-1',
    name: '2026 秋季',
    firstWeekMonday: DateTime(2026, 9, 7),
    totalWeeks: 20,
    periodsByWeekday: {for (var day = 1; day <= 7; day++) day: periods},
  );

  Course courseOn(int weekday, {String id = 'course-1'}) => Course(
    id: id,
    name: '课程 $id',
    teacher: '张老师',
    colorValue: 0xFF7D9DCE,
    sessions: [
      CourseSession(
        id: '$id-session',
        weekday: weekday,
        startPeriod: 1,
        endPeriod: 1,
        weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
        location: 'A101',
      ),
    ],
  );

  group('startupSelectedDate', () {
    test('今天有课且最后一节已结束 → 返回明天', () {
      final engine = ScheduleEngine(term: term, courses: [courseOn(1)]);
      expect(
        startupSelectedDate(engine, DateTime(2026, 9, 7, 12)),
        DateTime(2026, 9, 8),
      );
    });

    test('下课时间正好等于当前时刻也算上完课 → 返回明天', () {
      final engine = ScheduleEngine(term: term, courses: [courseOn(1)]);
      expect(
        startupSelectedDate(engine, DateTime(2026, 9, 7, 8, 45)),
        DateTime(2026, 9, 8),
      );
    });

    test('今天有课但最后一节尚未结束 → 不跳转', () {
      final engine = ScheduleEngine(term: term, courses: [courseOn(1)]);
      expect(startupSelectedDate(engine, DateTime(2026, 9, 7, 8, 30)), isNull);
      expect(startupSelectedDate(engine, DateTime(2026, 9, 7, 8, 44)), isNull);
    });

    test('今天没有任何安排 → 不跳转', () {
      final engine = ScheduleEngine(term: term, courses: [courseOn(1)]);
      // 9-08 是周二，课表里只有周一的课。
      expect(engine.getEntriesForDate(DateTime(2026, 9, 8)), isEmpty);
      expect(startupSelectedDate(engine, DateTime(2026, 9, 8, 23)), isNull);
    });

    test('学期之外（同样没有任何安排）→ 不跳转', () {
      final engine = ScheduleEngine(term: term, courses: [courseOn(1)]);
      expect(startupSelectedDate(engine, DateTime(2026, 9, 6, 23)), isNull);
      expect(startupSelectedDate(engine, DateTime(2027, 1, 25, 23)), isNull);
    });

    test('多个安排时以最后一项的结束时间为准', () {
      // 周二的课 08:00-08:45，另有一条当天 18:00-19:00 的一次性备忘录。
      final memo = Memo(
        id: 'memo-1',
        title: '交作业',
        colorValue: 0xFF123456,
        date: DateTime(2026, 9, 8),
        startMinutes: 18 * 60,
        endMinutes: 19 * 60,
      );
      final engine = ScheduleEngine(
        term: term,
        courses: [courseOn(2)],
        memos: [memo],
      );
      // 课已结束，但更晚的备忘录还没开始 → 不跳。
      expect(startupSelectedDate(engine, DateTime(2026, 9, 8, 12)), isNull);
      expect(startupSelectedDate(engine, DateTime(2026, 9, 8, 18)), isNull);
      // 备忘录结束后才算当天全部结束。
      expect(
        startupSelectedDate(engine, DateTime(2026, 9, 8, 19)),
        DateTime(2026, 9, 9),
      );
    });

    test('跨月边界：9 月 30 日结束 → 10 月 1 日', () {
      final engine = ScheduleEngine(term: term, courses: [courseOn(3)]);
      expect(DateTime(2026, 9, 30).weekday, DateTime.wednesday);
      expect(
        startupSelectedDate(engine, DateTime(2026, 9, 30, 23, 59)),
        DateTime(2026, 10, 1),
      );
    });

    test('跨年边界：12 月 31 日结束 → 次年 1 月 1 日', () {
      final engine = ScheduleEngine(term: term, courses: [courseOn(4)]);
      expect(DateTime(2026, 12, 31).weekday, DateTime.thursday);
      expect(
        startupSelectedDate(engine, DateTime(2026, 12, 31, 23, 59)),
        DateTime(2027, 1, 1),
      );
    });

    test('第二天就是下一天，即使那天没课也不顺延', () {
      // 周一（9-07）上完课 → 显示周二；周二没课也照常显示。
      final engine = ScheduleEngine(term: term, courses: [courseOn(1)]);
      final result = startupSelectedDate(engine, DateTime(2026, 9, 7, 12));
      expect(result, DateTime(2026, 9, 8));
      expect(engine.getEntriesForDate(result!), isEmpty);
    });

    test('不跳过周末：周五上完课 → 显示周六', () {
      final engine = ScheduleEngine(term: term, courses: [courseOn(5)]);
      expect(DateTime(2026, 9, 11).weekday, DateTime.friday);
      final result = startupSelectedDate(engine, DateTime(2026, 9, 11, 20));
      expect(result, DateTime(2026, 9, 12));
      expect(result!.weekday, DateTime.saturday);
      expect(engine.getEntriesForDate(result), isEmpty);
    });

    test('返回值只保留年月日，时分秒为 0', () {
      final engine = ScheduleEngine(term: term, courses: [courseOn(1)]);
      final result = startupSelectedDate(engine, DateTime(2026, 9, 7, 23, 59, 59));
      expect(result, isNotNull);
      expect(result!.hour, 0);
      expect(result.minute, 0);
      expect(result.second, 0);
      expect(result.millisecond, 0);
      expect(result.microsecond, 0);
    });
  });

  group('启动接线', () {
    // 已结束的今日课程：周一 08:00-08:45，判定时刻 12:00。
    final fixtureData = ScheduleData(
      term: term,
      courses: [courseOn(1)],
    );

    testWidgets('启动后把选中日期设为第二天', (tester) async {
      final themeController = _FakeThemeSeedColorController();
      await tester.pumpWidget(
        _app(
          fixtureData,
          now: DateTime(2026, 9, 7, 12),
          themeController: themeController,
        ),
      );
      await tester.pumpAndSettle();

      expect(_selectedDate(tester), DateTime(2026, 9, 8));
    });

    testWidgets('只判定一次：重建不会把用户手动选的日期抢回来', (tester) async {
      final themeController = _FakeThemeSeedColorController();
      await tester.pumpWidget(
        _app(
          fixtureData,
          now: DateTime(2026, 9, 7, 12),
          themeController: themeController,
        ),
      );
      await tester.pumpAndSettle();
      expect(_selectedDate(tester), DateTime(2026, 9, 8));

      // 模拟用户手动滑到别的日期。
      final container = _container(tester);
      final userDate = DateTime(2026, 9, 20);
      container.read(selectedDateProvider.notifier).state = userDate;
      await tester.pump();

      // 触发一次真正的重建（主题色变化会让 CourseScheduleApp 重新 build）。
      themeController.set(0xFF112233);
      await tester.pumpAndSettle();

      expect(container.read(selectedDateProvider), userDate);
    });

    testWidgets('今天还没上完课时不改变选中日期', (tester) async {
      await tester.pumpWidget(
        _app(fixtureData, now: DateTime(2026, 9, 7, 7)),
      );
      await tester.pumpAndSettle();

      expect(_selectedDate(tester), isNot(DateTime(2026, 9, 8)));
    });

    testWidgets('学期未配置时静默不处理', (tester) async {
      await tester.pumpWidget(
        _app(const ScheduleData(), now: DateTime(2026, 9, 7, 12)),
      );
      await tester.pumpAndSettle();

      expect(find.text('先设置你的学期'), findsOneWidget);
      expect(_selectedDate(tester), isNot(DateTime(2026, 9, 8)));
    });
  });
}

Widget _app(
  ScheduleData data, {
  required DateTime now,
  ThemeSeedColorController? themeController,
}) {
  return ProviderScope(
    overrides: [
      scheduleControllerProvider.overrideWith(
        () => _FakeScheduleController(data),
      ),
      clockProvider.overrideWith((ref) => Stream<DateTime>.value(now)),
      if (themeController != null)
        themeSeedColorProvider.overrideWith(() => themeController),
    ],
    child: const CourseScheduleApp(),
  );
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(CourseScheduleApp)),
      listen: false,
    );

DateTime _selectedDate(WidgetTester tester) =>
    _container(tester).read(selectedDateProvider);

class _FakeScheduleController extends ScheduleController {
  _FakeScheduleController(this.data);

  final ScheduleData data;

  @override
  Future<ScheduleData> build() async => data;
}

class _FakeThemeSeedColorController extends ThemeSeedColorController {
  @override
  Future<int> build() async => ThemeSeedColorController.defaultColorValue;

  /// 直接改状态，用来触发一次重建。
  void set(int colorValue) => state = AsyncData(colorValue);
}
