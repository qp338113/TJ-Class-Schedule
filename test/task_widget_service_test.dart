import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:offline_course_schedule/widget/task_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('后台同步缓存倒计时数据，完成作业和备注不传给组件', () async {
    SharedPreferences.setMockInitialValues({});
    final due = DateTime.utc(2026, 10, 5);
    final task = TaskRecord.manual(
      id: 'x',
      title: '作业',
      course: '数学',
      platform: 'manual',
      url: '',
      note: '私密备注',
      dueAt: due,
    );
    await const TaskWidgetService().syncBackground([
      task,
      task.copyWith(completed: true),
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('task_widget_tasks')!), [
      {
        'id': 'x',
        'title': '作业',
        'course': '数学',
        'dueMillis': due.millisecondsSinceEpoch,
      },
    ]);
  });
  test('小组件只接收未完成且有截止的真实作业；冷启动取回目标作业', () async {
    final now = DateTime.utc(2026, 10, 1);
    TaskRecord row(
      String id, {
      bool completed = false,
      DateTime? due,
      String source = 'manual',
    }) => TaskRecord(
      id: id,
      title: id,
      course: '数学',
      platform: 'manual',
      source: source,
      accountId: '',
      createdAt: now,
      completed: completed,
      dueAt: due,
      note: '不传送备注',
    );
    Map<Object?, Object?>? payload;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(TaskWidgetService.channel, (call) async {
      if (call.method == 'initialTask') return 'manual:active';
      expect(call.method, 'updateTasks');
      payload = call.arguments as Map<Object?, Object?>;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(TaskWidgetService.channel, null),
    );
    const service = TaskWidgetService();
    await service.sync([
      row('manual:active', due: now),
      row('done', due: now, completed: true),
      row('none'),
      row('demo', due: now, source: 'demo'),
    ]);
    final tasks = payload!['tasks'] as List;
    expect(tasks, hasLength(1));
    expect(tasks.single, {
      'id': 'manual:active',
      'title': 'manual:active',
      'course': '数学',
      'dueMillis': now.millisecondsSinceEpoch,
    });
    expect(await service.initialTask(), 'manual:active');
  });
}
