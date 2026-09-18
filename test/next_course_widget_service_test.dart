import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/widget/next_course_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('offline_course_schedule/widget');

  final term = Term(
    id: 'term',
    name: '测试',
    firstWeekMonday: DateTime(2026, 9, 14),
    totalWeeks: 1,
    periodsByWeekday: {
      1: const [LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525)],
    },
  );
  final course = Course(
    id: 'course',
    name: '高等数学',
    teacher: '张老师',
    colorValue: 0,
    sessions: [
      CourseSession(
        id: 'session',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 1,
        weekRule: WeekRule(startWeek: 1, endWeek: 1, type: WeekType.every),
        location: '北129',
      ),
    ],
  );

  test('小组件只保留尚未开始的课程并按时间排序', () {
    final items = const NextCourseWidgetService().buildItems(
      ScheduleData(term: term, courses: [course]),
      DateTime(2026, 9, 14, 7, 30),
    );

    expect(items.single['name'], '高等数学');
    expect(items.single['location'], '北129');
    expect(items.single['teacher'], '张老师');
    expect(items.single['time'], '08:00');
  });

  test('小组件在课程与备忘录混合时挑出下一个未开始的安排', () {
    final memo = Memo(
      id: 'memo',
      title: '交作业',
      location: '图书馆',
      colorValue: 0,
      date: DateTime(2026, 9, 14),
      startMinutes: 450,
      endMinutes: 470,
    );

    final items = const NextCourseWidgetService().buildItems(
      ScheduleData(term: term, courses: [course], memos: [memo]),
      DateTime(2026, 9, 14, 7),
    );

    expect(items.map((item) => item['name']), ['交作业', '高等数学']);
    expect(items.first['time'], '07:30');
    expect(items.first['location'], '图书馆');
    // 备忘录没有教师，用空字符串适配现有数据结构，Kotlin 侧据 isMemo 隐藏教师行。
    expect(items.first['teacher'], '');
    // 备忘录要标出来，小组件才能说“距离事件开始”而不是“距离上课”。
    expect(items.first['isMemo'], isTrue);
    expect(items.last['name'], '高等数学');
    expect(items.last['isMemo'], isFalse);
  });

  test('已经开始的备忘录不会再出现在小组件里', () {
    final memo = Memo(
      id: 'memo',
      title: '交作业',
      colorValue: 0,
      date: DateTime(2026, 9, 14),
      startMinutes: 450,
      endMinutes: 470,
    );

    final items = const NextCourseWidgetService().buildItems(
      ScheduleData(term: term, courses: [course], memos: [memo]),
      DateTime(2026, 9, 14, 7, 45),
    );

    expect(items.map((item) => item['name']), ['高等数学']);
  });

  test('按周重复的备忘录也会进入小组件数据', () {
    final memo = Memo(
      id: 'memo-recurring',
      title: '英语角',
      location: '外语楼',
      colorValue: 0,
      weekday: 2,
      startPeriod: 1,
      endPeriod: 1,
      weekRule: WeekRule(startWeek: 1, endWeek: 1, type: WeekType.every),
    );

    final items = const NextCourseWidgetService().buildItems(
      ScheduleData(term: term, courses: const [], memos: [memo]),
      DateTime(2026, 9, 14, 7),
    );

    expect(items.single['name'], '英语角');
    expect(items.single['time'], '08:00');
    expect(items.single['location'], '外语楼');
    expect(items.single['isMemo'], isTrue);
  });

  test('课程条目带 isMemo = false', () {
    final items = const NextCourseWidgetService().buildItems(
      ScheduleData(term: term, courses: [course]),
      DateTime(2026, 9, 14, 7),
    );

    expect(items.single['isMemo'], isFalse);
  });

  test('调休日小组件显示被补那一天的课，而不是当天实际星期', () {
    // 2026-09-19 是第 1 周周六，本来没有课；调休后要按第 1 周周一上课。
    final plain = const NextCourseWidgetService().buildItems(
      ScheduleData(term: term, courses: [course]),
      DateTime(2026, 9, 19, 7),
    );
    expect(plain, isEmpty);

    final items = const NextCourseWidgetService().buildItems(
      ScheduleData(
        term: term,
        courses: [course],
        adjustments: [
          ScheduleAdjustment(
            date: DateTime(2026, 9, 19),
            replacementWeek: 1,
            replacementWeekday: DateTime.monday,
          ),
        ],
      ),
      DateTime(2026, 9, 19, 7),
    );

    expect(items.single['name'], '高等数学');
    expect(items.single['time'], '08:00');
  });

  test('同步小组件时把颜色一并传给原生侧', () async {
    Map<Object?, Object?>? payload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'update');
          payload = call.arguments as Map<Object?, Object?>?;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final schedule = ScheduleData(term: term, courses: [course]);
    const service = NextCourseWidgetService();

    await service.sync(
      schedule,
      now: DateTime(2026, 9, 14, 7),
      colorValue: 0xFF1B4332,
    );
    // Kotlin 侧按 int 读这个键，所以必须原样传 ARGB 值。
    expect(payload?['color'], 0xFF1B4332);
    expect(payload?['courses'], isA<List<Object?>>());

    // 未自定义时传 null，原生侧据此删掉颜色键、恢复默认外观。
    await service.sync(schedule, now: DateTime(2026, 9, 14, 7));
    expect(payload?['color'], isNull);
  });
}
