import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/schedule_models.dart';
import '../domain/notification_settings.dart';

class ScheduleDatabase {
  ScheduleDatabase._(this.database);

  final Database database;

  static Future<ScheduleDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final selectedFactory = factory ?? databaseFactory;
    final databasePath =
        path ?? p.join(await getDatabasesPath(), 'schedule.db');
    final database = await selectedFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 7,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createTables,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createSettingsTable(db);
          if (oldVersion < 3) await _createMakeupDaysTable(db);
          if (oldVersion >= 3 && oldVersion < 4) {
            await db.execute(
              'ALTER TABLE national_makeup_days ADD COLUMN replacement_week INTEGER',
            );
          }
          if (oldVersion < 5) await _createCourseCancellationsTable(db);
          if (oldVersion < 6) {
            await db.execute(
              'ALTER TABLE national_makeup_days ADD COLUMN is_holiday INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE national_makeup_days ADD COLUMN holiday_name TEXT',
            );
          }
          if (oldVersion < 7) await _createMemosTable(db);
        },
      ),
    );
    await _seedNationalMakeupDays(database);
    return ScheduleDatabase._(database);
  }

  static Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE terms (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        first_week_monday TEXT NOT NULL,
        total_weeks INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE lesson_periods (
        term_id TEXT NOT NULL,
        weekday INTEGER NOT NULL,
        number INTEGER NOT NULL,
        start_minutes INTEGER NOT NULL,
        end_minutes INTEGER NOT NULL,
        PRIMARY KEY (term_id, weekday, number),
        FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE courses (
        id TEXT PRIMARY KEY,
        term_id TEXT NOT NULL,
        name TEXT NOT NULL,
        teacher TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE course_sessions (
        id TEXT PRIMARY KEY,
        course_id TEXT NOT NULL,
        weekday INTEGER NOT NULL,
        start_period INTEGER NOT NULL,
        end_period INTEGER NOT NULL,
        start_week INTEGER NOT NULL,
        end_week INTEGER NOT NULL,
        week_type TEXT NOT NULL,
        explicit_weeks TEXT,
        location TEXT NOT NULL,
        teacher_override TEXT,
        FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
      )
    ''');
    await _createSettingsTable(db);
    await _createMakeupDaysTable(db);
    await _createCourseCancellationsTable(db);
    await _createMemosTable(db);
  }

  static Future<void> _createSettingsTable(Database db) {
    return db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createMakeupDaysTable(Database db) {
    return db.execute('''
      CREATE TABLE national_makeup_days (
        date TEXT PRIMARY KEY,
        replacement_week INTEGER,
        replacement_weekday INTEGER,
        is_holiday INTEGER NOT NULL DEFAULT 0,
        holiday_name TEXT
      )
    ''');
  }

  static Future<void> _createCourseCancellationsTable(Database db) {
    return db.execute('''
      CREATE TABLE course_cancellations (
        session_id TEXT NOT NULL,
        date TEXT NOT NULL,
        PRIMARY KEY (session_id, date)
      )
    ''');
  }

  static Future<void> _createMemosTable(Database db) {
    return db.execute('''
      CREATE TABLE memos (
        id TEXT PRIMARY KEY,
        term_id TEXT NOT NULL,
        title TEXT NOT NULL,
        location TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        weekday INTEGER,
        start_period INTEGER,
        end_period INTEGER,
        start_week INTEGER,
        end_week INTEGER,
        week_type TEXT,
        explicit_weeks TEXT,
        date TEXT,
        start_minutes INTEGER,
        end_minutes INTEGER,
        FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _seedNationalMakeupDays(Database db) async {
    const makeupDates = [
      '2026-01-04',
      '2026-02-14',
      '2026-02-28',
      '2026-05-09',
      '2026-09-20',
      '2026-10-10',
    ];
    for (final date in makeupDates) {
      await db.insert('national_makeup_days', {
        'date': date,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    const holidayRanges = {
      '元旦': [('2026-01-01', '2026-01-03')],
      '春节': [('2026-02-15', '2026-02-23')],
      '清明节': [('2026-04-04', '2026-04-06')],
      '劳动节': [('2026-05-01', '2026-05-05')],
      '端午节': [('2026-06-19', '2026-06-21')],
      '中秋节': [('2026-09-25', '2026-09-27')],
      '国庆节': [('2026-10-01', '2026-10-07')],
    };
    for (final entry in holidayRanges.entries) {
      for (final range in entry.value) {
        var date = DateTime.parse(range.$1);
        final end = DateTime.parse(range.$2);
        while (!date.isAfter(end)) {
          await db.insert('national_makeup_days', {
            'date': _dateKey(date),
            'is_holiday': 1,
            'holiday_name': entry.key,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          date = date.add(const Duration(days: 1));
        }
      }
    }
  }

  Future<void> replaceTermSchedule(Term term, Iterable<Course> courses) async {
    await database.transaction((txn) async {
      // 更新学期而不是先删后插：删除 terms 行会经外键级联删掉该学期的备忘录。
      final updated = await txn.update(
        'terms',
        {
          'name': term.name,
          'first_week_monday': term.firstWeekMonday.toIso8601String(),
          'total_weeks': term.totalWeeks,
        },
        where: 'id = ?',
        whereArgs: [term.id],
      );
      if (updated == 0) {
        await txn.insert('terms', {
          'id': term.id,
          'name': term.name,
          'first_week_monday': term.firstWeekMonday.toIso8601String(),
          'total_weeks': term.totalWeeks,
        });
      }
      await txn.delete(
        'lesson_periods',
        where: 'term_id = ?',
        whereArgs: [term.id],
      );
      for (final entry in term.periodsByWeekday.entries) {
        for (final period in entry.value) {
          await txn.insert('lesson_periods', {
            'term_id': term.id,
            'weekday': entry.key,
            'number': period.number,
            'start_minutes': period.startMinutes,
            'end_minutes': period.endMinutes,
          });
        }
      }
      await txn.delete('courses', where: 'term_id = ?', whereArgs: [term.id]);
      for (final course in courses) {
        await txn.insert('courses', {
          'id': course.id,
          'term_id': term.id,
          'name': course.name,
          'teacher': course.teacher,
          'color_value': course.colorValue,
        });
        for (final session in course.sessions) {
          final explicitWeeks = session.weekRule.explicitWeeks?.toList();
          explicitWeeks?.sort();
          await txn.insert('course_sessions', {
            'id': session.id,
            'course_id': course.id,
            'weekday': session.weekday,
            'start_period': session.startPeriod,
            'end_period': session.endPeriod,
            'start_week': session.weekRule.startWeek,
            'end_week': session.weekRule.endWeek,
            'week_type': session.weekRule.type.name,
            'explicit_weeks': explicitWeeks?.join(','),
            'location': session.location,
            'teacher_override': session.teacherOverride,
          });
        }
      }
    });
  }

  Future<({Term term, List<Course> courses})?> loadTermSchedule(
    String termId,
  ) async {
    final termRows = await database.query(
      'terms',
      where: 'id = ?',
      whereArgs: [termId],
    );
    if (termRows.isEmpty) return null;
    final termRow = termRows.single;
    final periodRows = await database.query(
      'lesson_periods',
      where: 'term_id = ?',
      whereArgs: [termId],
      orderBy: 'weekday, number',
    );
    final periods = <int, List<LessonPeriod>>{};
    for (final row in periodRows) {
      final weekday = row['weekday'] as int;
      periods
          .putIfAbsent(weekday, () => [])
          .add(
            LessonPeriod(
              number: row['number'] as int,
              startMinutes: row['start_minutes'] as int,
              endMinutes: row['end_minutes'] as int,
            ),
          );
    }
    final term = Term(
      id: termId,
      name: termRow['name'] as String,
      firstWeekMonday: DateTime.parse(termRow['first_week_monday'] as String),
      totalWeeks: termRow['total_weeks'] as int,
      periodsByWeekday: periods,
    );

    final courseRows = await database.query(
      'courses',
      where: 'term_id = ?',
      whereArgs: [termId],
      orderBy: 'rowid',
    );
    final courses = <Course>[];
    for (final courseRow in courseRows) {
      final courseId = courseRow['id'] as String;
      final sessionRows = await database.query(
        'course_sessions',
        where: 'course_id = ?',
        whereArgs: [courseId],
        orderBy: 'rowid',
      );
      final sessions = sessionRows.map((row) {
        final explicitText = row['explicit_weeks'] as String?;
        return CourseSession(
          id: row['id'] as String,
          weekday: row['weekday'] as int,
          startPeriod: row['start_period'] as int,
          endPeriod: row['end_period'] as int,
          weekRule: WeekRule(
            startWeek: row['start_week'] as int,
            endWeek: row['end_week'] as int,
            type: WeekType.values.byName(row['week_type'] as String),
            explicitWeeks: explicitText == null || explicitText.isEmpty
                ? null
                : explicitText.split(',').map(int.parse).toSet(),
          ),
          location: row['location'] as String,
          teacherOverride: row['teacher_override'] as String?,
        );
      }).toList();
      courses.add(
        Course(
          id: courseId,
          name: courseRow['name'] as String,
          teacher: courseRow['teacher'] as String,
          colorValue: courseRow['color_value'] as int,
          sessions: List<CourseSession>.unmodifiable(sessions),
        ),
      );
    }
    return (term: term, courses: List<Course>.unmodifiable(courses));
  }

  Future<List<Memo>> loadMemos(String termId) async {
    final rows = await database.query(
      'memos',
      where: 'term_id = ?',
      whereArgs: [termId],
      orderBy: 'rowid',
    );
    final memos = rows.map((row) {
      final explicitText = row['explicit_weeks'] as String?;
      final dateText = row['date'] as String?;
      final startWeek = row['start_week'] as int?;
      return Memo(
        id: row['id'] as String,
        title: row['title'] as String,
        location: row['location'] as String,
        colorValue: row['color_value'] as int,
        weekday: row['weekday'] as int?,
        startPeriod: row['start_period'] as int?,
        endPeriod: row['end_period'] as int?,
        weekRule: startWeek == null
            ? null
            : WeekRule(
                startWeek: startWeek,
                endWeek: row['end_week'] as int,
                type: WeekType.values.byName(row['week_type'] as String),
                explicitWeeks: explicitText == null || explicitText.isEmpty
                    ? null
                    : explicitText.split(',').map(int.parse).toSet(),
              ),
        date: dateText == null ? null : DateTime.parse(dateText),
        startMinutes: row['start_minutes'] as int?,
        endMinutes: row['end_minutes'] as int?,
      );
    }).toList();
    return List<Memo>.unmodifiable(memos);
  }

  Future<void> replaceTermMemos(String termId, Iterable<Memo> memos) async {
    await database.transaction((txn) async {
      await txn.delete('memos', where: 'term_id = ?', whereArgs: [termId]);
      for (final memo in memos) {
        final weekRule = memo.weekRule;
        final explicitWeeks = weekRule?.explicitWeeks?.toList();
        explicitWeeks?.sort();
        await txn.insert('memos', {
          'id': memo.id,
          'term_id': termId,
          'title': memo.title,
          'location': memo.location,
          'color_value': memo.colorValue,
          'weekday': memo.weekday,
          'start_period': memo.startPeriod,
          'end_period': memo.endPeriod,
          'start_week': weekRule?.startWeek,
          'end_week': weekRule?.endWeek,
          'week_type': weekRule?.type.name,
          'explicit_weeks': explicitWeeks?.join(','),
          'date': memo.date == null ? null : _dateKey(memo.date!),
          'start_minutes': memo.startMinutes,
          'end_minutes': memo.endMinutes,
        });
      }
    });
  }

  Future<NotificationSettings> loadNotificationSettings() async {
    final rows = await database.query('app_settings');
    final values = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    return NotificationSettings(
      enabled: values['notifications_enabled'] != 'false',
      advanceMinutes: int.tryParse(values['advance_minutes'] ?? '') ?? 30,
      memoAdvanceMinutes:
          int.tryParse(values['memo_advance_minutes'] ?? '') ?? 30,
      onlyNextCourse: values['only_next_course'] == 'true',
      delayWhenInClass: values['delay_when_in_class'] != 'false',
      showNextCourseOnLockScreen:
          values['show_next_course_on_lock_screen'] == 'true',
      alertMode: _alertModeFromSettings(values),
      magicOsGuideCompleted: values['magic_os_guide_completed'] == 'true',
      tutorialPromptCompleted: values['tutorial_prompt_completed'] == 'true',
    );
  }

  Future<List<ScheduleAdjustment>> loadScheduleAdjustments() async {
    final rows = await database.query('national_makeup_days', orderBy: 'date');
    return List<ScheduleAdjustment>.unmodifiable(
      rows.map(
        (row) => ScheduleAdjustment(
          date: DateTime.parse(row['date'] as String),
          replacementWeek: row['replacement_week'] as int?,
          replacementWeekday: row['replacement_weekday'] as int?,
          isHoliday: (row['is_holiday'] as int? ?? 0) == 1,
          holidayName: row['holiday_name'] as String?,
        ),
      ),
    );
  }

  Future<void> saveNationalMakeupDays(Iterable<DateTime> dates) async {
    await database.transaction((txn) async {
      for (final date in dates) {
        await txn.insert('national_makeup_days', {
          'date': _dateKey(date),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> saveNationalHolidays(Map<DateTime, String> holidays) async {
    await database.transaction((txn) async {
      for (final entry in holidays.entries) {
        await txn.insert('national_makeup_days', {
          'date': _dateKey(entry.key),
          'is_holiday': 1,
          'holiday_name': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<CourseCancellation>> loadCourseCancellations() async {
    final rows = await database.query(
      'course_cancellations',
      orderBy: 'date, session_id',
    );
    return List<CourseCancellation>.unmodifiable(
      rows.map(
        (row) => CourseCancellation(
          sessionId: row['session_id'] as String,
          date: DateTime.parse(row['date'] as String),
        ),
      ),
    );
  }

  Future<void> saveCourseCancellation(String sessionId, DateTime date) {
    return database.insert('course_cancellations', {
      'session_id': sessionId,
      'date': _dateKey(date),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> replaceScheduleAdjustments(
    Iterable<ScheduleAdjustment> adjustments,
  ) async {
    await database.transaction((txn) async {
      await txn.delete('national_makeup_days');
      for (final item in adjustments) {
        await txn.insert('national_makeup_days', {
          'date': _dateKey(item.date),
          'replacement_week': item.replacementWeek,
          'replacement_weekday': item.replacementWeekday,
          'is_holiday': item.isHoliday ? 1 : 0,
          'holiday_name': item.holidayName,
        });
      }
    });
  }

  Future<void> ensureNationalCalendar() => _seedNationalMakeupDays(database);

  Future<void> replaceCourseCancellations(
    Iterable<CourseCancellation> cancellations,
  ) async {
    await database.transaction((txn) async {
      await txn.delete('course_cancellations');
      for (final item in cancellations) {
        await txn.insert('course_cancellations', {
          'session_id': item.sessionId,
          'date': _dateKey(item.date),
        });
      }
    });
  }

  Future<String?> loadSetting(String key) async {
    final rows = await database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> saveSetting(String key, String value) => database.insert(
    'app_settings',
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> deleteSetting(String key) =>
      database.delete('app_settings', where: 'key = ?', whereArgs: [key]);

  Future<void> setReplacementSchedule(DateTime date, int week, int weekday) {
    return database.insert('national_makeup_days', {
      'date': _dateKey(date),
      'replacement_week': week,
      'replacement_weekday': weekday,
      'is_holiday': 0,
      'holiday_name': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 只清掉替代课表，保留这一天“调休上班日”的记录。
  ///
  /// 直接删行会让调休提示一并消失，用户就再也找不到设置入口了。
  Future<void> clearReplacementSchedule(DateTime date) {
    return database.update('national_makeup_days', {
      'replacement_week': null,
      'replacement_weekday': null,
    }, where: 'date = ?', whereArgs: [_dateKey(date)]);
  }

  Future<void> saveNotificationSettings(NotificationSettings settings) async {
    final values = {
      'notifications_enabled': '${settings.enabled}',
      'advance_minutes': '${settings.advanceMinutes}',
      'memo_advance_minutes': '${settings.memoAdvanceMinutes}',
      'only_next_course': '${settings.onlyNextCourse}',
      'delay_when_in_class': '${settings.delayWhenInClass}',
      'show_next_course_on_lock_screen':
          '${settings.showNextCourseOnLockScreen}',
      'reminder_alert_mode': settings.alertMode.name,
      'magic_os_guide_completed': '${settings.magicOsGuideCompleted}',
      'tutorial_prompt_completed': '${settings.tutorialPromptCompleted}',
    };
    await database.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> close() => database.close();
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

ReminderAlertMode _alertModeFromSettings(Map<String, String> values) {
  final saved = values['reminder_alert_mode'];
  for (final mode in ReminderAlertMode.values) {
    if (mode.name == saved) return mode;
  }
  return values['vibration_enabled'] == 'false'
      ? ReminderAlertMode.notificationOnly
      : ReminderAlertMode.soundAndVibration;
}
