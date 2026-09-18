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
      memoAdvanceMinutes: 90,
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
    expect(loaded.memoAdvanceMinutes, 90);
    expect(loaded.onlyNextCourse, isTrue);
    expect(loaded.delayWhenInClass, isFalse);
    expect(loaded.showNextCourseOnLockScreen, isTrue);
    expect(loaded.alertMode, ReminderAlertMode.vibration);
    expect(loaded.magicOsGuideCompleted, isTrue);
    expect(loaded.tutorialPromptCompleted, isTrue);
  });

  test('未保存过备忘录提醒时间时默认为 30 分钟', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);

    final loaded = await db.loadNotificationSettings();
    expect(loaded.memoAdvanceMinutes, 30);
    expect(loaded.advanceMinutes, 30);
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

  test('取消替代课表后保留调休日记录，只是不再映射到别的教学周', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);

    // 9月20日是国家调休上班日，先设置成补第 4 周周二的课。
    await db.setReplacementSchedule(DateTime(2026, 9, 20), 4, DateTime.tuesday);
    await db.clearReplacementSchedule(DateTime(2026, 9, 20));

    final target = (await db.loadScheduleAdjustments()).singleWhere(
      (item) => item.matches(DateTime(2026, 9, 20)),
    );
    // 记录仍在，所以调休提示条不会消失，用户还能重新设置。
    expect(target.replacementWeek, isNull);
    expect(target.replacementWeekday, isNull);
    expect(target.isHoliday, isFalse);
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

  test('按周重复与一次性备忘录都能完整往返数据库', () async {
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
        1: [const LessonPeriod(number: 7, startMinutes: 800, endMinutes: 845)],
      },
    );
    await db.replaceTermSchedule(term, const []);

    final recurring = Memo(
      id: 'memo-recurring',
      title: '社团例会',
      location: 'C303',
      colorValue: 0xFF7D9DCE,
      weekday: DateTime.wednesday,
      startPeriod: 7,
      endPeriod: 8,
      weekRule: WeekRule(
        startWeek: 2,
        endWeek: 9,
        type: WeekType.custom,
        explicitWeeks: {2, 4, 9},
      ),
    );
    final once = Memo(
      id: 'memo-once',
      title: '体检',
      location: '校医院',
      colorValue: 0xFFEF6C6C,
      date: DateTime(2026, 10, 1),
      startMinutes: 14 * 60,
      endMinutes: 15 * 60 + 30,
    );

    await db.replaceTermMemos('term-1', [recurring, once]);
    final loaded = await db.loadMemos('term-1');

    expect(loaded, hasLength(2));

    final loadedRecurring = loaded.firstWhere(
      (memo) => memo.id == 'memo-recurring',
    );
    expect(loadedRecurring.title, '社团例会');
    expect(loadedRecurring.location, 'C303');
    expect(loadedRecurring.colorValue, 0xFF7D9DCE);
    expect(loadedRecurring.isRecurring, isTrue);
    expect(loadedRecurring.weekday, DateTime.wednesday);
    expect(loadedRecurring.startPeriod, 7);
    expect(loadedRecurring.endPeriod, 8);
    expect(loadedRecurring.weekRule!.type, WeekType.custom);
    expect(loadedRecurring.weekRule!.startWeek, 2);
    expect(loadedRecurring.weekRule!.endWeek, 9);
    expect(loadedRecurring.weekRule!.explicitWeeks, {2, 4, 9});
    expect(loadedRecurring.date, isNull);
    expect(loadedRecurring.startMinutes, isNull);
    expect(loadedRecurring.endMinutes, isNull);

    final loadedOnce = loaded.firstWhere((memo) => memo.id == 'memo-once');
    expect(loadedOnce.title, '体检');
    expect(loadedOnce.location, '校医院');
    expect(loadedOnce.isRecurring, isFalse);
    expect(loadedOnce.date, DateTime(2026, 10, 1));
    expect(loadedOnce.startMinutes, 14 * 60);
    expect(loadedOnce.endMinutes, 15 * 60 + 30);
    expect(loadedOnce.weekday, isNull);
    expect(loadedOnce.startPeriod, isNull);
    expect(loadedOnce.endPeriod, isNull);
    expect(loadedOnce.weekRule, isNull);
  });

  test('替换学期课程时不会删除该学期的备忘录', () async {
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
        1: [const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525)],
      },
    );
    await db.replaceTermSchedule(term, const []);
    await db.replaceTermMemos('term-1', [
      Memo(
        id: 'memo-1',
        title: '例会',
        colorValue: 1,
        weekday: 3,
        startPeriod: 7,
        endPeriod: 8,
        weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
      ),
    ]);

    // 重新保存学期与课程后，备忘录必须仍在。
    await db.replaceTermSchedule(term, const []);
    expect(await db.loadMemos('term-1'), hasLength(1));

    await db.replaceTermMemos('term-1', const []);
    expect(await db.loadMemos('term-1'), isEmpty);
  });

  test('重复替换同一学期不会残留旧的节次或时间段', () async {
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
        1: [const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525)],
        2: [const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525)],
      },
    );
    final course = Course(
      id: 'course-1',
      name: '高等数学',
      teacher: '张老师',
      colorValue: 1,
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

    await db.replaceTermSchedule(term, [course]);
    // 再次写入同样的学期与课程，不能因主键重复而失败。
    await db.replaceTermSchedule(term, [course]);

    final loaded = await db.loadTermSchedule('term-1');
    expect(loaded!.term.periodsByWeekday[1], hasLength(1));
    expect(loaded.term.periodsByWeekday[2], hasLength(1));
    expect(loaded.courses, hasLength(1));
    expect(loaded.courses.single.sessions, hasLength(1));

    // 换成没有课时间段的课程后，旧时间段必须被清掉。
    await db.replaceTermSchedule(term, [
      Course(
        id: 'course-1',
        name: '高等数学',
        teacher: '张老师',
        colorValue: 1,
        sessions: const [],
      ),
    ]);
    final updated = await db.loadTermSchedule('term-1');
    expect(updated!.courses.single.sessions, isEmpty);
  });

  test('删除学期会级联删除该学期的备忘录', () async {
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
        1: [const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525)],
      },
    );
    await db.replaceTermSchedule(term, const []);
    await db.replaceTermMemos('term-1', [
      Memo(
        id: 'memo-1',
        title: '例会',
        colorValue: 1,
        weekday: 3,
        startPeriod: 7,
        endPeriod: 8,
        weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
      ),
    ]);

    await db.database.delete('terms', where: 'id = ?', whereArgs: ['term-1']);
    expect(await db.loadMemos('term-1'), isEmpty);
  });
}
