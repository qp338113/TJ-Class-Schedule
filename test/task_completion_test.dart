import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/data/task_repository.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('平台刷新更新字段，但保留手动完成及手动待完成', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final repo = TaskRepository(db.database);
    TaskRecord task(bool completed, String title) => TaskRecord(
      id: 'canvas:a:1:2',
      title: title,
      course: '数学',
      platform: 'canvas',
      source: 'canvas',
      accountId: 'a',
      createdAt: DateTime.utc(2026, 10, 1),
      completed: completed,
    );
    await repo.mergePlatform([task(false, '原题')]);
    await repo.setCompleted('canvas:a:1:2', true);
    await repo.mergePlatform([task(false, '新标题')]);
    expect((await repo.loadAll()).single.completed, isTrue);
    expect((await repo.loadAll()).single.title, '新标题');
    await repo.setCompleted('canvas:a:1:2', false);
    await repo.mergePlatform([task(true, '已提交')]);
    expect((await repo.loadAll()).single.completed, isFalse);
  });
}
