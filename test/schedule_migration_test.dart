import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('schedule-migration-');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('5 升到 7 补齐法定节假日字段与备忘录表，并保留旧数据', () async {
    final path = '${tempDir.path}/schedule.db';
    await _createLegacyDatabase(path, version: 5, schema: _legacyV5Schema);

    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(db.close);

    expect(await _columns(db, 'memos'), containsAll(_memoColumns));
    expect(await _columns(db, 'national_makeup_days'), containsAll([
      'is_holiday',
      'holiday_name',
    ]));
    expect(await _columns(db, 'course_cancellations'), containsAll([
      'session_id',
      'date',
    ]));
    await _expectLegacyDataIntact(db);
  });

  test('3 升到 7 依次补齐替代教学周、停课表、节假日字段与备忘录表', () async {
    final path = '${tempDir.path}/schedule.db';
    await _createLegacyDatabase(path, version: 3, schema: _legacyV3Schema);

    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(db.close);

    expect(await _columns(db, 'national_makeup_days'), containsAll([
      'replacement_week',
      'is_holiday',
      'holiday_name',
    ]));
    expect(await _columns(db, 'course_cancellations'), containsAll([
      'session_id',
      'date',
    ]));
    expect(await _columns(db, 'memos'), containsAll(_memoColumns));

    final adjustments = await db.loadScheduleAdjustments();
    final makeup = adjustments.singleWhere(
      (item) => item.matches(DateTime(2025, 9, 20)),
    );
    // 旧的替代星期列在迁移后仍然可读，替代教学周为空。
    expect(makeup.replacementWeekday, DateTime.tuesday);
    expect(makeup.replacementWeek, isNull);
    await _expectLegacyDataIntact(db);
  });

  test('6 升到 7 只新增备忘录表，旧数据完好', () async {
    final path = '${tempDir.path}/schedule.db';
    await _createLegacyDatabase(path, version: 6, schema: _legacyV6Schema);

    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(db.close);

    expect(await _columns(db, 'memos'), containsAll(_memoColumns));
    await _expectLegacyDataIntact(db);
  });

  test('迁移后的备忘录表可写入并按学期外键级联删除', () async {
    final path = '${tempDir.path}/schedule.db';
    await _createLegacyDatabase(path, version: 6, schema: _legacyV6Schema);

    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(db.close);

    await db.replaceTermMemos(_legacyTermId, [_recurringMemo(id: 'memo-1')]);
    expect(await db.loadMemos(_legacyTermId), hasLength(1));

    // 删除学期后应随外键级联一并删除。
    await db.database.delete(
      'terms',
      where: 'id = ?',
      whereArgs: [_legacyTermId],
    );
    expect(await db.loadMemos(_legacyTermId), isEmpty);
  });
}

const _legacyTermId = 'term-legacy';

/// 迁移测试用的旧库都插入同一份旧数据，便于复用同一套校验。
Future<void> _expectLegacyDataIntact(ScheduleDatabase db) async {
  final loaded = await db.loadTermSchedule('term-legacy');
  expect(loaded, isNotNull);
  expect(loaded!.term.name, '旧学期');
  expect(loaded.term.totalWeeks, 18);
  expect(loaded.term.periodsByWeekday[1], hasLength(1));
  expect(loaded.courses.single.name, '旧课程');
  expect(loaded.courses.single.sessions.single.location, 'A101');

  final settings = await db.loadNotificationSettings();
  expect(settings.advanceMinutes, 25);
  expect(settings.enabled, isFalse);
}

/// 用指定的旧版建表语句建立数据库，再以目标版本打开即可触发 onUpgrade。
Future<void> _createLegacyDatabase(
  String path, {
  required int version,
  required List<String> schema,
}) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        for (final statement in schema) {
          await db.execute(statement);
        }
        await _insertLegacyData(db);
      },
    ),
  );
  await db.close();
}

Future<void> _insertLegacyData(Database db) async {
  await db.insert('terms', {
    'id': 'term-legacy',
    'name': '旧学期',
    'first_week_monday': DateTime(2025, 9, 1).toIso8601String(),
    'total_weeks': 18,
  });
  await db.insert('lesson_periods', {
    'term_id': 'term-legacy',
    'weekday': 1,
    'number': 1,
    'start_minutes': 480,
    'end_minutes': 525,
  });
  await db.insert('courses', {
    'id': 'course-legacy',
    'term_id': 'term-legacy',
    'name': '旧课程',
    'teacher': '老老师',
    'color_value': 1,
  });
  await db.insert('course_sessions', {
    'id': 'session-legacy',
    'course_id': 'course-legacy',
    'weekday': 1,
    'start_period': 1,
    'end_period': 1,
    'start_week': 1,
    'end_week': 18,
    'week_type': 'every',
    'location': 'A101',
  });
  // course_cancellations 是 v5 才建的表，更早的库跳过。
  if (await _hasTable(db, 'course_cancellations')) {
    await db.insert('course_cancellations', {
      'session_id': 'session-legacy',
      'date': '2025-09-08',
    });
  }
  await db.insert('app_settings', {
    'key': 'advance_minutes',
    'value': '25',
  });
  await db.insert('app_settings', {
    'key': 'notifications_enabled',
    'value': 'false',
  });
  await db.insert('national_makeup_days', {
    'date': '2025-09-20',
    'replacement_weekday': 2,
  });
}

Future<bool> _hasTable(Database db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  return rows.isNotEmpty;
}

const _termTables = '''
  CREATE TABLE terms (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    first_week_monday TEXT NOT NULL,
    total_weeks INTEGER NOT NULL
  )
''';

const _lessonPeriodsTable = '''
  CREATE TABLE lesson_periods (
    term_id TEXT NOT NULL,
    weekday INTEGER NOT NULL,
    number INTEGER NOT NULL,
    start_minutes INTEGER NOT NULL,
    end_minutes INTEGER NOT NULL,
    PRIMARY KEY (term_id, weekday, number),
    FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE
  )
''';

const _coursesTable = '''
  CREATE TABLE courses (
    id TEXT PRIMARY KEY,
    term_id TEXT NOT NULL,
    name TEXT NOT NULL,
    teacher TEXT NOT NULL,
    color_value INTEGER NOT NULL,
    FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE
  )
''';

const _courseSessionsTable = '''
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
''';

const _settingsTable = '''
  CREATE TABLE app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
''';

const _courseCancellationsTable = '''
  CREATE TABLE course_cancellations (
    session_id TEXT NOT NULL,
    date TEXT NOT NULL,
    PRIMARY KEY (session_id, date)
  )
''';

/// v5 的 national_makeup_days 还没有节假日字段。
const _v5MakeupDaysTable = '''
  CREATE TABLE national_makeup_days (
    date TEXT PRIMARY KEY,
    replacement_week INTEGER,
    replacement_weekday INTEGER
  )
''';

/// v3 的 national_makeup_days 连替代教学周都还没有。
const _v3MakeupDaysTable = '''
  CREATE TABLE national_makeup_days (
    date TEXT PRIMARY KEY,
    replacement_weekday INTEGER
  )
''';

const _v6MakeupDaysTable = '''
  CREATE TABLE national_makeup_days (
    date TEXT PRIMARY KEY,
    replacement_week INTEGER,
    replacement_weekday INTEGER,
    is_holiday INTEGER NOT NULL DEFAULT 0,
    holiday_name TEXT
  )
''';

final _legacyV3Schema = [
  _termTables,
  _lessonPeriodsTable,
  _coursesTable,
  _courseSessionsTable,
  _settingsTable,
  _v3MakeupDaysTable,
];

final _legacyV5Schema = [
  _termTables,
  _lessonPeriodsTable,
  _coursesTable,
  _courseSessionsTable,
  _settingsTable,
  _v5MakeupDaysTable,
  _courseCancellationsTable,
];

final _legacyV6Schema = [
  _termTables,
  _lessonPeriodsTable,
  _coursesTable,
  _courseSessionsTable,
  _settingsTable,
  _v6MakeupDaysTable,
  _courseCancellationsTable,
];

const _memoColumns = [
  'id',
  'term_id',
  'title',
  'location',
  'color_value',
  'weekday',
  'start_period',
  'end_period',
  'start_week',
  'end_week',
  'week_type',
  'explicit_weeks',
  'date',
  'start_minutes',
  'end_minutes',
];

Future<Set<String>> _columns(ScheduleDatabase db, String table) async {
  final rows = await db.database.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String).toSet();
}

Memo _recurringMemo({required String id}) => Memo(
  id: id,
  title: '例会',
  colorValue: 1,
  weekday: 3,
  startPeriod: 7,
  endPeriod: 8,
  weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
);
