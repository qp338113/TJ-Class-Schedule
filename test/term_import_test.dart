import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/import/term_import.dart';

void main() {
  const parser = TermImportParser();

  test('从课表文字识别最大周数并采用同济作息模板', () {
    final result = parser.inferFromText('高等数学 [1-16]，另一门课 2-18双周');

    expect(result.totalWeeks, 18);
    expect(result.usedDefaultPeriods, isTrue);
    expect(result.periods.first.startMinutes, 8 * 60);
    expect(result.periods[1].endMinutes, 9 * 60 + 35);
  });

  test('CSV 有上课时间时用文件时间覆盖模板', () {
    final result = parser.parseCsv('周次范围,节次,上课时间\n1-20周,1-2,08:10-09:45');

    expect(result.totalWeeks, 20);
    expect(result.usedDefaultPeriods, isFalse);
    expect(result.periods.first.startMinutes, 8 * 60 + 10);
    expect(result.periods[1].endMinutes, 9 * 60 + 45);
  });
}
