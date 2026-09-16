import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/import/course_import.dart';

void main() {
  const parser = CourseImportParser();

  test('CSV 自动识别列并把同一课程合并为多个时间段', () {
    const csv = '''任课教师,课程名称,教室,星期,上课节次,教学周
张老师,高等数学,A101,周一,第1-2节,1-16周(单)
张老师,高等数学,B202,周一,第1-2节,2-16周(双)''';

    final preview = parser.parseCsv(csv);
    expect(preview.errors, isEmpty);
    expect(preview.rows, hasLength(2));
    expect(preview.rows.every((row) => row.isValid), isTrue);

    final result = parser.buildCourses(preview);
    expect(result.rejectedRows, isEmpty);
    expect(result.courses, hasLength(1));
    expect(result.courses.single.sessions, hasLength(2));
    expect(result.courses.single.sessions.first.location, 'A101');
    expect(result.courses.single.sessions.last.weekRule.type, WeekType.even);
  });

  test('解析失败保留原文和告警，修正后可导入', () {
    const csv = '''课程名,教师,地点,周几,节次,周次范围
大学英语,李老师,C301,礼拜八,1-2节,若干周''';
    final preview = parser.parseCsv(csv);
    final row = preview.rows.single;
    expect(row.isValid, isFalse);
    expect(row.cells[ImportField.weekday]!.raw, '礼拜八');
    expect(row.cells[ImportField.weekday]!.needsAttention, isTrue);
    expect(row.cells[ImportField.weeks]!.raw, '若干周');
    expect(parser.buildCourses(preview).rejectedRows, hasLength(1));

    final weekdayFixed = parser.updateCell(
      preview,
      1,
      ImportField.weekday,
      '星期三',
    );
    final allFixed = parser.updateCell(
      weekdayFixed,
      1,
      ImportField.weeks,
      '1-16周',
    );
    expect(allFixed.rows.single.isValid, isTrue);
    expect(parser.buildCourses(allFixed).courses, hasLength(1));
  });

  test('缺少必需列时不猜测导入', () {
    final preview = parser.parseCsv('课程名,教师\n大学英语,李老师');
    expect(preview.canImport, isFalse);
    expect(preview.errors.single, contains('缺少必需列'));
  });

  test('预览中删除的课程行不会进入导入结果', () {
    const csv = '''课程名,教师,地点,周几,节次,周次范围
高等数学,张老师,北129,周一,1-2节,1-16周
误识别课程,未知,未知,周二,3-4节,1-16周''';
    final preview = parser.parseCsv(csv);

    final changed = parser.removeRow(preview, 2);

    expect(changed.rows, hasLength(1));
    expect(parser.buildCourses(changed).courses.single.name, '高等数学');
  });

  test('可以读取 xlsx 的首个非空工作表', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('课程名'),
      TextCellValue('教师'),
      TextCellValue('地点'),
      TextCellValue('周几'),
      TextCellValue('节次'),
      TextCellValue('周次范围'),
    ]);
    sheet.appendRow([
      TextCellValue('物理'),
      TextCellValue('王老师'),
      TextCellValue('实验楼'),
      TextCellValue('周五'),
      TextCellValue('3-4节'),
      TextCellValue('2-18双周'),
    ]);

    final bytes = Uint8List.fromList(workbook.save()!);
    final preview = parser.parseXlsx(bytes);
    expect(preview.rows, hasLength(1));
    expect(preview.rows.single.isValid, isTrue);
  });
}
