import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/import/task_json_import.dart';

void main() {
  test('只允许 1–50 条并核对字段；同一条重复采集只保留一项', () {
    const row = '{"title":"习题一","course":"数学","platform":"canvas",'
        '"dueAt":"2026-10-03T12:00:00+08:00","url":"https://canvas.tongji.edu.cn/courses/1",'
        '"note":"阅读课本"}';
    final tasks = parseTaskImport('{"version":1,"tasks":[$row,$row]}');
    expect(tasks, hasLength(1));
    expect(tasks.single.title, '习题一');
    expect(tasks.single.completed, isFalse);
    expect(tasks.single.note, contains('待核对'));
    expect(tasks.single.dueAt!.toUtc(), DateTime.utc(2026, 10, 3, 4));
    expect(() => parseTaskImport('{"version":2,"tasks":[$row]}'), throwsFormatException);
    expect(() => parseTaskImport('{"version":1,"tasks":[]}'), throwsFormatException);
    expect(() => parseTaskImport('{"version":1,"tasks":[${List.filled(51, row).join(',')}]}'), throwsFormatException);
  });

  test('采集 JSON 中的提交状态和多余字段不被信任', () {
    final tasks = parseTaskImport('''{"version":1,"tasks":[{
      "title":"任务","course":"数学","platform":"haoke","dueAt":null,
      "url":"","note":"","status":"completed","token":"secret"
    }]}''');
    expect(tasks.single.completed, isFalse);
    expect(tasks.single.toRow().toString(), isNot(contains('secret')));
  });
}
