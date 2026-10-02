import 'package:sqflite/sqflite.dart';

import '../domain/task_record.dart';

class TaskRepository {
  const TaskRepository(this.database, {this.onChanged});

  final Database database;
  final void Function()? onChanged;

  Future<List<TaskRecord>> loadVisible() async {
    final rows = await database.query('app_settings');
    final settings = {for (final row in rows) row['key']: row['value']};
    final canvas =
        settings['task_canvas_account'] ?? settings['task_canvas_last_account'];
    final haoke =
        settings['task_haoke_account'] ?? settings['task_haoke_last_account'];
    return (await loadAll())
        .where(
          (task) => switch (task.source) {
            'canvas' => task.accountId == canvas,
            'haoke' => task.accountId == haoke,
            _ => true,
          },
        )
        .toList();
  }

  Future<List<TaskRecord>> loadAll() async {
    final rows = await database.query(
      'tasks',
      orderBy: 'due_at ASC, title ASC',
    );
    return rows.map(TaskRecord.fromRow).toList();
  }

  Future<void> save(TaskRecord task) async {
    await database.insert(
      'tasks',
      task.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    onChanged?.call();
  }

  Future<void> setCompleted(String id, bool completed) async {
    await database.update(
      'tasks',
      {'completed': completed ? 1 : 0, 'manual_completed': completed ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    onChanged?.call();
  }

  Future<void> deleteManual(String id) async {
    final rows = await database.query(
      'tasks',
      columns: ['source'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty ||
        !['manual', 'browser'].contains(rows.single['source'])) {
      throw ArgumentError('只能删除手工或页面导入的作业');
    }
    await database.delete('tasks', where: 'id = ?', whereArgs: [id]);
    onChanged?.call();
  }

  Future<void> mergePlatform(Iterable<TaskRecord> tasks) async {
    await database.transaction((txn) async {
      for (final task in tasks) {
        if (!['canvas', 'haoke'].contains(task.source)) {
          throw ArgumentError('平台同步不能覆盖手工作业');
        }
        final old = await txn.query(
          'tasks',
          columns: ['manual_completed'],
          where: 'id = ?',
          whereArgs: [task.id],
          limit: 1,
        );
        final manual = old.isEmpty ? null : old.single['manual_completed'];
        final updated = manual == null
            ? task
            : task.copyWith(
                completed: manual == 1,
                manualCompleted: manual == 1,
              );
        await txn.insert(
          'tasks',
          updated.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    onChanged?.call();
  }

  Future<void> mergeBrowser(Iterable<TaskRecord> tasks) async {
    await database.transaction((txn) async {
      for (final task in tasks) {
        if (task.source != 'browser') throw ArgumentError('只能导入页面采集记录');
        final existing = await txn.query(
          'tasks',
          columns: ['completed', 'manual_completed'],
          where: 'id = ?',
          whereArgs: [task.id],
          limit: 1,
        );
        final preserved = existing.isEmpty
            ? task
            : task.copyWith(
                completed: existing.single['completed'] == 1,
                manualCompleted: existing.single['manual_completed'] == null
                    ? null
                    : existing.single['manual_completed'] == 1,
              );
        await txn.insert(
          'tasks',
          preserved.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    onChanged?.call();
  }
}
