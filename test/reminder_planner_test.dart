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

  test('备忘录使用 memoAdvanceMinutes 而不是课程的 advanceMinutes', () {
    final memos = [
      Memo(
        id: 'memo-monday',
        title: '交作业',
        location: '图书馆',
        colorValue: 0,
        date: DateTime(2026, 9, 8),
        startMinutes: 600,
        endMinutes: 660,
      ),
    ];

    final plans = planner.createPlans(
      now: DateTime(2026, 9, 8, 8),
      term: term,
      courses: const [],
      memos: memos,
      // 课程提前 5 分钟、备忘录提前 15 分钟，用不同取值证明用了正确那个。
      settings: const NotificationSettings(
        advanceMinutes: 5,
        memoAdvanceMinutes: 15,
      ),
    );

    expect(plans, hasLength(1));
    expect(plans.single.scheduledAt, DateTime(2026, 9, 8, 9, 45));
  });

  test('课程仍使用 advanceMinutes，与备忘录互不影响', () {
    final memos = [
      Memo(
        id: 'memo-monday',
        title: '交作业',
        colorValue: 0,
        date: DateTime(2026, 9, 7),
        startMinutes: 720,
        endMinutes: 780,
      ),
    ];

    final plans = planner.createPlans(
      now: DateTime(2026, 9, 7, 7),
      term: term,
      courses: courses,
      memos: memos,
      settings: const NotificationSettings(
        advanceMinutes: 10,
        memoAdvanceMinutes: 20,
        delayWhenInClass: false,
      ),
    );

    expect(
      plans.map((plan) => (plan.title, plan.scheduledAt)),
      [
        ('数学 即将上课', DateTime(2026, 9, 7, 7, 50)),
        ('交作业 即将开始', DateTime(2026, 9, 7, 11, 40)),
        ('英语 即将上课', DateTime(2026, 9, 8, 7, 50)),
      ],
    );
  });

  test('备忘录文案用“即将开始”并带上时间与地点', () {
    final memos = [
      Memo(
        id: 'memo-location',
        title: '开班会',
        location: 'B202',
        colorValue: 0,
        date: DateTime(2026, 9, 8),
        startMinutes: 600,
        endMinutes: 660,
      ),
      Memo(
        id: 'memo-no-location',
        title: '取快递',
        colorValue: 0,
        date: DateTime(2026, 9, 8),
        startMinutes: 800,
        endMinutes: 830,
      ),
    ];

    final plans = planner.createPlans(
      now: DateTime(2026, 9, 8, 8),
      term: term,
      courses: const [],
      memos: memos,
      settings: const NotificationSettings(memoAdvanceMinutes: 0),
    );

    expect(plans.map((plan) => plan.title), ['开班会 即将开始', '取快递 即将开始']);
    expect(plans.first.body, '10:00 · B202');
    expect(plans.last.body, '13:20');
    // 备忘录不显示教师，正文里也不会出现“上课”。
    expect(plans.first.body.contains('上课'), isFalse);
  });

  test('仅提醒最近一件事时对课程与备忘录合并结果生效', () {
    final memos = [
      // 09:00 开始，提前 30 分钟 => 08:30 提醒，比两门课都早。
      Memo(
        id: 'memo-early',
        title: '交作业',
        colorValue: 0,
        date: DateTime(2026, 9, 9),
        startMinutes: 540,
        endMinutes: 570,
      ),
    ];

    final plans = planner.createPlans(
      now: DateTime(2026, 9, 9, 7),
      term: term,
      courses: courses,
      memos: memos,
      settings: const NotificationSettings(
        onlyNextCourse: true,
        delayWhenInClass: false,
      ),
    );

    expect(plans, hasLength(1));
    expect(plans.single.title, '交作业 即将开始');
    expect(plans.single.scheduledAt, DateTime(2026, 9, 9, 8, 30));
  });

  test('关闭总开关时备忘录也不排程', () {
    final plans = planner.createPlans(
      now: DateTime(2026, 9, 8, 8),
      term: term,
      courses: const [],
      memos: [
        Memo(
          id: 'memo-monday',
          title: '交作业',
          colorValue: 0,
          date: DateTime(2026, 9, 8),
          startMinutes: 600,
          endMinutes: 660,
        ),
      ],
      settings: const NotificationSettings(enabled: false),
    );

    expect(plans, isEmpty);
  });

  test('锁屏计划仍然只包含课程，不出现备忘录', () {
    final plans = planner.createLockScreenPlans(
      now: DateTime(2026, 9, 7, 6),
      term: term,
      courses: courses,
      settings: const NotificationSettings(showNextCourseOnLockScreen: true),
    );

    expect(plans.map((plan) => plan.title), ['下一节课：数学', '下一节课：英语']);
  });
}
