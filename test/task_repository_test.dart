import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:offline_course_schedule/data/task_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('手工作业可保存、完成、撤销和删除，不影响课表', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final repository = TaskRepository(db.database);
    final task = TaskRecord.manual(
      id: 'manual-1',
      title: '习题一',
      course: '数学',
      platform: 'manual',
      dueAt: DateTime.utc(2026, 10, 2),
      url: 'https://example.com/task',
      note: '',
    );

    await repository.save(task);
    expect((await repository.loadAll()).single.title, '习题一');
    await repository.setCompleted(task.id, true);
    expect((await repository.loadAll()).single.completed, isTrue);
    await repository.setCompleted(task.id, false);
    expect((await repository.loadAll()).single.completed, isFalse);
    await repository.deleteManual(task.id);
    expect(await repository.loadAll(), isEmpty);
    expect(await db.database.query('terms'), isEmpty);
  });

  test('平台作业同步保留旧记录，且不同账号不混合', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final repository = TaskRepository(db.database);
    TaskRecord canvas(String account, String title) => TaskRecord(
      id: 'canvas:$account:1:2',
      title: title,
      course: '数学',
      platform: 'canvas',
      source: 'canvas',
      accountId: account,
      createdAt: DateTime.utc(2026, 10, 1),
      syncedAt: DateTime.utc(2026, 10, 1),
    );

    await repository.mergePlatform([canvas('a', '原作业')]);
    await repository.mergePlatform([canvas('b', '另一账号')]);
    await repository.mergePlatform([canvas('a', '更新标题')]);
    final rows = await repository.loadAll();
    expect(rows, hasLength(2));
    expect(rows.singleWhere((row) => row.accountId == 'a').title, '更新标题');
    expect(rows.singleWhere((row) => row.accountId == 'b').title, '另一账号');
    expect(repository.deleteManual(rows.first.id), throwsArgumentError);
  });

  test('危险链接和无效字段不能写入', () {
    expect(
      () => safeTaskUrl('https://user:pass@example.com'),
      throwsFormatException,
    );
    expect(
      () => safeTaskUrl('https://example.com/?token=secret'),
      throwsFormatException,
    );
    expect(() => safeTaskUrl('https://example.com/?%74oken=secret'), throwsFormatException);
    expect(() => safeTaskUrl('https://example.com/#authorization=secret'), throwsFormatException);
    expect(() => safeTaskUrl('javascript:alert(1)'), throwsFormatException);
    expect(
      () => TaskRecord.manual(
        id: '1',
        title: ' ',
        course: '数学',
        platform: 'manual',
        note: '',
        url: '',
      ),
      throwsArgumentError,
    );
  });

  test('旧版 v7 数据库升级到 v8 后保留学期课程和设置', () async {
    final directory = await Directory.systemTemp.createTemp('task-upgrade-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}schedule.db';
    final old = await ScheduleDatabase.open(factory: databaseFactoryFfi, path: path);
    await old.database.insert('terms', {
      'id': 'current-term', 'name': '旧学期',
      'first_week_monday': '2026-09-07', 'total_weeks': 20,
    });
    await old.database.insert('courses', {
      'id': 'old-course', 'term_id': 'current-term',
      'name': '旧课程', 'teacher': '张老师', 'color_value': 123,
    });
    await old.saveSetting('theme_seed_color', '789');
    // 用完整现有表结构回退版本号，仅移除 v8 新表，模拟真实 v7 升级。
    await old.database.execute('DROP TABLE tasks');
    await old.database.execute('PRAGMA user_version = 7');
    await old.close();

    final upgraded = await ScheduleDatabase.open(factory: databaseFactoryFfi, path: path);
    addTearDown(upgraded.close);
    final schedule = await upgraded.loadTermSchedule('current-term');
    expect(schedule?.term.name, '旧学期');
    expect(schedule?.courses.single.name, '旧课程');
    expect(await upgraded.loadSetting('theme_seed_color'), '789');
    expect(await TaskRepository(upgraded.database).loadAll(), isEmpty);
  });
}
