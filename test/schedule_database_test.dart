import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('学期、节次、课程及多个时间段可完整往返数据库', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);

    final term = Term(
      id: 'term-1',
      name: '测试学期',
      firstWeekMonday: DateTime(2026, 9, 7),
      totalWeeks: 20,
      periodsByWeekday: {
        1: [
          const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525),
          const LessonPeriod(number: 2, startMinutes: 535, endMinutes: 580),
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
          id: 'session-odd',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weekRule: WeekRule(startWeek: 1, endWeek: 15, type: WeekType.odd),
          location: 'A101',
        ),
        CourseSession(
          id: 'session-custom',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weekRule: WeekRule(
            startWeek: 2,
            endWeek: 8,
            type: WeekType.custom,
            explicitWeeks: {2, 4, 8},
          ),
          location: 'B202',
          teacherOverride: '李老师',
        ),
      ],
    );

    await db.replaceTermSchedule(term, [course]);
    final loaded = await db.loadTermSchedule('term-1');

    expect(loaded, isNotNull);
    expect(loaded!.term.name, '测试学期');
    expect(loaded.term.periodsByWeekday[1], hasLength(2));
    expect(loaded.courses.single.name, '高等数学');
    expect(loaded.courses.single.sessions, hasLength(2));
    expect(loaded.courses.single.sessions.last.location, 'B202');
    expect(loaded.courses.single.sessions.last.teacherOverride, '李老师');
    expect(loaded.courses.single.sessions.last.weekRule.explicitWeeks, {
      2,
      4,
      8,
    });
  });

  test('通知设置可完整往返数据库', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    const settings = NotificationSettings(
      enabled: false,
      advanceMinutes: 15,
      onlyNextCourse: true,
      delayWhenInClass: false,
      showNextCourseOnLockScreen: true,
      alertMode: ReminderAlertMode.vibration,
      magicOsGuideCompleted: true,
      tutorialPromptCompleted: true,
    );
    await db.saveNotificationSettings(settings);
    final loaded = await db.loadNotificationSettings();
    expect(loaded.enabled, isFalse);
    expect(loaded.advanceMinutes, 15);
    expect(loaded.onlyNextCourse, isTrue);
    expect(loaded.delayWhenInClass, isFalse);
    expect(loaded.showNextCourseOnLockScreen, isTrue);
    expect(loaded.alertMode, ReminderAlertMode.vibration);
    expect(loaded.magicOsGuideCompleted, isTrue);
    expect(loaded.tutorialPromptCompleted, isTrue);
  });

  test('国家调休日与用户选择的目标教学周、星期可保存', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);

    await db.setReplacementSchedule(DateTime(2026, 9, 20), 4, DateTime.tuesday);
    final adjustments = await db.loadScheduleAdjustments();
    final target = adjustments.singleWhere(
      (item) => item.matches(DateTime(2026, 9, 20)),
    );

    expect(target.replacementWeek, 4);
    expect(target.replacementWeekday, DateTime.tuesday);
  });

  test('临时停课和导入撤销快照可保存', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);

    await db.saveCourseCancellation('session-1', DateTime(2026, 9, 8));
    await db.saveSetting('last_import_snapshot', '[1,2,3]');

    final cancellation = (await db.loadCourseCancellations()).single;
    expect(cancellation.sessionId, 'session-1');
    expect(cancellation.date, DateTime(2026, 9, 8));
    expect(await db.loadSetting('last_import_snapshot'), '[1,2,3]');
    await db.deleteSetting('last_import_snapshot');
    expect(await db.loadSetting('last_import_snapshot'), isNull);
  });

  test('内置国家法定节假日带有节日名称', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);

    final adjustments = await db.loadScheduleAdjustments();
    final holiday = adjustments.singleWhere(
      (item) => item.matches(DateTime(2026, 10, 1)),
    );
    expect(holiday.isHoliday, isTrue);
    expect(holiday.holidayName, '国庆节');
  });
}
