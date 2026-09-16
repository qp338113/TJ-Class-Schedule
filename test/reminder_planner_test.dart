import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/notifications/reminder_planner.dart';

void main() {
  const planner = ReminderPlanner();
  final periods = [
    const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580),
  ];
  final term = Term(
    id: 'term',
    name: '测试学期',
    firstWeekMonday: DateTime(2026, 9, 7),
    totalWeeks: 20,
    periodsByWeekday: {for (var day = 1; day <= 7; day++) day: periods},
  );
  final courses = [
    Course(
      id: 'monday',
      name: '数学',
      teacher: '张老师',
      colorValue: 0,
      sessions: [
        CourseSession(
          id: 'monday-session',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: 'A101',
        ),
      ],
    ),
    Course(
      id: 'tuesday',
      name: '英语',
      teacher: '李老师',
      colorValue: 0,
      sessions: [
        CourseSession(
          id: 'tuesday-session',
          weekday: 2,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: 'B202',
        ),
      ],
    ),
  ];

  test('按设置提前 30 分钟生成未来七天提醒', () {
    final plans = planner.createPlans(
      now: DateTime(2026, 9, 7, 7),
      term: term,
      courses: courses,
      settings: const NotificationSettings(),
    );
    expect(plans, hasLength(2));
    expect(plans.first.scheduledAt, DateTime(2026, 9, 7, 7, 30));
    expect(plans.first.title, '数学 即将上课');
    expect(plans.first.body, '08:00 · A101');
    expect(plans.first.payload, '2026-09-07');
  });

  test('已经错过提醒时间的课程不会排程', () {
    final plans = planner.createPlans(
      now: DateTime(2026, 9, 7, 7, 45),
      term: term,
      courses: courses,
      settings: const NotificationSettings(),
    );
    expect(plans.map((plan) => plan.title), ['英语 即将上课']);
  });

  test('仅下一节模式只保留最近一条', () {
    final plans = planner.createPlans(
      now: DateTime(2026, 9, 7, 7),
      term: term,
      courses: courses,
      settings: const NotificationSettings(onlyNextCourse: true),
    );
    expect(plans, hasLength(1));
    expect(plans.single.title, '数学 即将上课');
  });

  test('关闭总开关时没有提醒', () {
    final plans = planner.createPlans(
      now: DateTime(2026, 9, 7, 7),
      term: term,
      courses: courses,
      settings: const NotificationSettings(enabled: false),
    );
    expect(plans, isEmpty);
  });

  test('原提醒时间正在上课时延后到下课三分钟', () {
    final busyTerm = Term(
      id: 'busy-term',
      name: '连续课程',
      firstWeekMonday: DateTime(2026, 9, 7),
      totalWeeks: 1,
      periodsByWeekday: {
        1: const [
          LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580),
          LessonPeriod(number: 2, startMinutes: 600, endMinutes: 700),
        ],
      },
    );
    final busyCourses = [
      Course(
        id: 'current',
        name: '正在上的课',
        teacher: '',
        colorValue: 0,
        sessions: [
          CourseSession(
            id: 'current-session',
            weekday: 1,
            startPeriod: 1,
            endPeriod: 1,
            weekRule: WeekRule(startWeek: 1, endWeek: 1, type: WeekType.every),
            location: '',
          ),
        ],
      ),
      Course(
        id: 'next',
        name: '下一节课',
        teacher: '',
        colorValue: 0,
        sessions: [
          CourseSession(
            id: 'next-session',
            weekday: 1,
            startPeriod: 2,
            endPeriod: 2,
            weekRule: WeekRule(startWeek: 1, endWeek: 1, type: WeekType.every),
            location: '',
          ),
        ],
      ),
    ];

    final plans = planner.createPlans(
      now: DateTime(2026, 9, 7, 9, 35),
      term: busyTerm,
      courses: busyCourses,
      settings: const NotificationSettings(advanceMinutes: 60),
    );

    final nextPlan = plans.singleWhere((plan) => plan.title.startsWith('下一节课'));
    expect(nextPlan.scheduledAt, DateTime(2026, 9, 7, 9, 43));
  });

  test('关闭上课中延后选项后仍使用原提醒时间', () {
    final plans = planner.createPlans(
      now: DateTime(2026, 9, 7, 7),
      term: term,
      courses: courses,
      settings: const NotificationSettings(delayWhenInClass: false),
    );

    expect(plans.first.scheduledAt, DateTime(2026, 9, 7, 7, 30));
  });

  test('锁屏课程默认关闭，开启后在上课前一小时显示并在上课时消失', () {
    final disabled = planner.createLockScreenPlans(
      now: DateTime(2026, 9, 7, 6),
      term: term,
      courses: courses,
      settings: const NotificationSettings(),
    );
    final enabled = planner.createLockScreenPlans(
      now: DateTime(2026, 9, 7, 6),
      term: term,
      courses: courses,
      settings: const NotificationSettings(showNextCourseOnLockScreen: true),
    );

    expect(disabled, isEmpty);
    expect(enabled.first.scheduledAt, DateTime(2026, 9, 7, 7));
    expect(
      enabled.first.timeoutAfterMilliseconds,
      const Duration(hours: 1).inMilliseconds,
    );
    expect(enabled.first.title, '下一节课：数学');
    expect(enabled.first.body, '08:00 · A101 · 张老师');
  });
}
