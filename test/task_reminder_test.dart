import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/task_state.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/data/task_repository.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:offline_course_schedule/notifications/task_reminder_planner.dart';
import 'package:offline_course_schedule/presentation/task_display.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final now = DateTime.utc(2026, 10, 1, 8);
TaskRecord task(
  String id, {
  DateTime? due,
  bool completed = false,
  String source = 'manual',
  String account = '',
}) => TaskRecord(
  id: id,
  title: '作业 $id',
  course: '数学',
  platform: source,
  source: source,
  accountId: account,
  createdAt: now,
  dueAt: due,
  completed: completed,
);

void main() {
  setUpAll(sqfliteFfiInit);
  test('只预约未来的自选提前时间；完成、无截止、逾期和错过提醒时间均排除', () {
    final rows = [
      task('future', due: now.add(const Duration(hours: 10))),
      task('done', due: now.add(const Duration(hours: 12)), completed: true),
      task('none'),
      task('past', due: now.subtract(const Duration(hours: 1))),
      task('late', due: now.add(const Duration(hours: 2))),
    ];
    final plans = taskReminderPlans(
      rows,
      const TaskReminderSettings(enabled: true, hours: 3),
      now,
    );
    expect(plans, hasLength(1));
    expect(plans.single.scheduledAt, now.add(const Duration(hours: 7)));
    expect(plans.single.payload, 'task:future');
    expect(plans.single.body, contains('3 小时'));
    expect(taskReminderPlans(rows, const TaskReminderSettings(), now), isEmpty);
    expect(
      taskReminderPlans(
        [rows.first.copyWith(completed: true)],
        const TaskReminderSettings(enabled: true, hours: 3),
        now,
      ),
      isEmpty,
    );
  });
  test('剩余与逾期倒计时边界', () {
    expect(taskCountdown(task('none'), now), '未设置截止时间');
    expect(taskCountdown(task('done', completed: true), now), '已完成');
    expect(
      taskCountdown(
        task('soon', due: now.add(const Duration(seconds: 30))),
        now,
      ),
      '剩余 不到1分钟',
    );
    expect(
      taskCountdown(
        task('hours', due: now.add(const Duration(minutes: 125))),
        now,
      ),
      '剩余 2小时 5分钟',
    );
    expect(
      taskCountdown(task('days', due: now.add(const Duration(hours: 51))), now),
      '剩余 2天 3小时',
    );
    expect(
      taskCountdown(
        task('past', due: now.subtract(const Duration(minutes: 30))),
        now,
      ),
      '已逾期 30分钟',
    );
  });
  test('同科目颜色稳定，存在同名课表课程时沿用其颜色', () {
    expect(taskCourseColor('数学', []), taskCourseColor(' 数学 ', []));
    final course = Course(
      id: 'math',
      name: '数学',
      teacher: '',
      colorValue: 0xff123456,
      sessions: [],
    );
    expect(taskCourseColor('数学', [course]), const Color(0xff123456));
  });
  test('提醒设置重建后保留，自定义非法值不会覆盖原设置', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    ProviderContainer container() => ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    final first = container();
    expect(
      (await first.read(taskReminderSettingsProvider.future)).enabled,
      isFalse,
    );
    await first
        .read(taskReminderSettingsProvider.notifier)
        .save(const TaskReminderSettings(enabled: true, hours: 7));
    await expectLater(
      first
          .read(taskReminderSettingsProvider.notifier)
          .save(const TaskReminderSettings(hours: 0)),
      throwsArgumentError,
    );
    first.dispose();
    final reopened = container();
    final saved = await reopened.read(taskReminderSettingsProvider.future);
    expect(saved.hours, 7);
    expect(saved.enabled, isTrue);
    reopened.dispose();
    await db.close();
  });
  test('只为当前或断开后最后账号的任务通知；修改成功才触发更新', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    var revisions = 0;
    final repo = TaskRepository(db.database, onChanged: () => revisions++);
    await repo.save(task('local'));
    await repo.save(task('old', source: 'canvas', account: 'old'));
    await repo.save(task('current', source: 'canvas', account: 'current'));
    await db.saveSetting('task_canvas_last_account', 'old');
    await db.saveSetting('task_canvas_account', 'current');
    expect((await repo.loadVisible()).map((t) => t.id).toSet(), {
      'local',
      'current',
    });
    await db.deleteSetting('task_canvas_account');
    expect((await repo.loadVisible()).map((t) => t.id).toSet(), {
      'local',
      'old',
    });
    await repo.setCompleted('local', true);
    await repo.deleteManual('local');
    expect(revisions, 5);
    await expectLater(repo.deleteManual('old'), throwsArgumentError);
    expect(revisions, 5);
    await db.close();
  });
}
