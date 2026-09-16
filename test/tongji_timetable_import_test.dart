import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/import/course_import.dart';
import 'package:offline_course_schedule/import/tongji_timetable_import.dart';

void main() {
  const parser = TongjiTimetableImportParser();

  test('解析同济课表中的教师、课程、周次和地点', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '姚勤(95017) 高等数学B(I) (CMS122103) [1-16] 北129',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '高等数学B(I)');
    expect(row.cells[ImportField.teacher]!.value, '姚勤');
    expect(row.cells[ImportField.location]!.value, '北129');
    expect(row.cells[ImportField.weekday]!.value, 1);
    final periods = row.cells[ImportField.periods]!.value! as PeriodRange;
    expect((periods.start, periods.end), (1, 2));
  });

  test('解析多位教师和不连续周次', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text:
            '徐象繁(13517),王庆国(18131),赫丽(00770) 大学物理实验A1(I) '
            '(PSE123503) [1, 3, 5, 7, 9, 11, 13, 15] 物理馆2-4楼',
        weekday: 4,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.teacher]!.value, '徐象繁、王庆国、赫丽');
    final result = parser.courseImportParser.buildCourses(preview);
    expect(
      result.courses.single.sessions.single.weekRule.type,
      WeekType.custom,
    );
    expect(result.courses.single.sessions.single.weekRule.includes(9), isTrue);
    expect(
      result.courses.single.sessions.single.weekRule.includes(10),
      isFalse,
    );
  });

  test('网页字段不完整时保留原文并标黄', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '网站改版后的未知内容',
        weekday: 3,
        startPeriod: 5,
        endPeriod: 6,
      ),
    ]);

    expect(preview.rows.single.isValid, isFalse);
    expect(
      preview.rows.single.cells[ImportField.weeks]!.needsAttention,
      isTrue,
    );
  });

  test('网页课程固定按周一到周日、同一天从早到晚排列', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '周三老师(3) 周三晚课 (ABC103) [1-16] C303',
        weekday: 3,
        startPeriod: 7,
        endPeriod: 8,
      ),
      TongjiTimetableRecord(
        text: '周一老师(1) 周一课程 (ABC101) [1-16] A101',
        weekday: 1,
        startPeriod: 5,
        endPeriod: 6,
      ),
      TongjiTimetableRecord(
        text: '周三老师(2) 周三早课 (ABC102) [1-16] B202',
        weekday: 3,
        startPeriod: 1,
        endPeriod: 2,
      ),
    ]);

    expect(
      preview.rows
          .map((row) => row.cells[ImportField.courseName]!.value)
          .toList(),
      ['周一课程', '周三早课', '周三晚课'],
    );
  });
}
