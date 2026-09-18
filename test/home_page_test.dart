import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('没有学期时显示首次设置入口', (tester) async {
    await tester.pumpWidget(_appWith(const ScheduleData()));
    await tester.pumpAndSettle();

    expect(find.text('先设置你的学期'), findsOneWidget);
    expect(find.text('开始设置'), findsOneWidget);
  });

  testWidgets('今日课程可见，横向拖动不再切换标签页', (tester) async {
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

    // 左右滑动已改为切换日期，不再切换标签页；这里断言仍停留在“今日”视图
    // （“没有安排”只出现在“本周”视图里没有安排的那几天）。
    await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('没有安排'), findsNothing);
    expect(find.text('高等数学'), findsOneWidget);

    // 切“今日/本周”仍可通过点顶部标签完成。
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(find.text('没有安排'), findsWidgets);
    expect(find.text('高等数学'), findsOneWidget);
  });

  testWidgets('滑一天模式下向左滑一天、向右退一天', (tester) async {
    final fixture = _scheduleFixture();
    final swipeController = _FakeSwipeAdvancesWeekController(false);
    await tester.pumpWidget(
      _appWith(
        fixture.data,
        swipeController: () => swipeController,
      ),
    );
    await tester.pumpAndSettle();
    final container = _containerOf(tester);
    expect(container.read(selectedDateProvider), fixture.today);

    await tester.fling(find.byType(TabBarView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(
      container.read(selectedDateProvider),
      fixture.today.add(const Duration(days: 1)),
    );

    await tester.fling(find.byType(TabBarView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(container.read(selectedDateProvider), fixture.today);
  });

  testWidgets('滑一周模式下向左滑一次前进一周', (tester) async {
    final fixture = _scheduleFixture();
    final swipeController = _FakeSwipeAdvancesWeekController(true);
    await tester.pumpWidget(
      _appWith(
        fixture.data,
        swipeController: () => swipeController,
      ),
    );
    await tester.pumpAndSettle();
    final container = _containerOf(tester);
    expect(container.read(selectedDateProvider), fixture.today);

    await tester.fling(find.byType(TabBarView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(
      container.read(selectedDateProvider),
      fixture.today.add(const Duration(days: 7)),
    );
  });

  testWidgets('菜单项反映当前滑动模式并可切换', (tester) async {
    final fixture = _scheduleFixture();
    final swipeController = _FakeSwipeAdvancesWeekController(false);
    await tester.pumpWidget(
      _appWith(
        fixture.data,
        swipeController: () => swipeController,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('滑动切换：一天'), findsOneWidget);

    await tester.tap(find.text('滑动切换：一天'));
    await tester.pumpAndSettle();
    expect(swipeController.saved, isTrue);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('滑动切换：一周'), findsOneWidget);
  });

  test('滑动模式可持久化到本机设置', () async {
    final database = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final container = _rawContainer(database);
    addTearDown(container.dispose);
    expect(await container.read(swipeAdvancesWeekProvider.future), isFalse);

    await container.read(swipeAdvancesWeekProvider.notifier).saveSettings(true);
    expect(await container.read(swipeAdvancesWeekProvider.future), isTrue);

    // 新容器重新读取同一个数据库，确认设置已落盘。
    final reloaded = _rawContainer(database);
    addTearDown(reloaded.dispose);
    expect(await reloaded.read(swipeAdvancesWeekProvider.future), isTrue);
  });
}

Widget _appWith(
  ScheduleData data, {
  SwipeAdvancesWeekController Function()? swipeController,
}) {
  return ProviderScope(
    overrides: [
      scheduleControllerProvider.overrideWith(
        () => _FakeScheduleController(data),
      ),
      // 固定“现在”为当天 00:00。课表 fixture 的日期跟着真实今天走，若放任真实时刻，
      // 傍晚之后运行测试会触发“课上完自动跳到第二天”，让“今日”视图的断言随运行
      // 时刻变化。固定到当天开始即可稳定显示今天。
      clockProvider.overrideWith((ref) => Stream.value(_startOfToday())),
      if (swipeController != null)
        swipeAdvancesWeekProvider.overrideWith(swipeController),
    ],
    child: const CourseScheduleApp(),
  );
}

DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(CourseScheduleApp)),
      listen: false,
    );

ProviderContainer _rawContainer(ScheduleDatabase database) {
  return ProviderContainer(
    overrides: [databaseProvider.overrideWith((ref) async => database)],
  );
}

({ScheduleData data, DateTime today}) _scheduleFixture() {
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
  return (data: ScheduleData(term: term, courses: [course]), today: today);
}

class _FakeScheduleController extends ScheduleController {
  _FakeScheduleController(this.data);

  final ScheduleData data;

  @override
  Future<ScheduleData> build() async => data;

  @override
  Future<void> changeCourseColor(String courseId, int colorValue) async {}
}

class _FakeSwipeAdvancesWeekController extends SwipeAdvancesWeekController {
  _FakeSwipeAdvancesWeekController(this.initial);

  final bool initial;
  bool? saved;

  @override
  Future<bool> build() async => initial;

  @override
  Future<void> saveSettings(bool advancesWeek) async {
    saved = advancesWeek;
    state = AsyncData(advancesWeek);
  }
}
