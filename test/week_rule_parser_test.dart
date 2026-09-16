import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/domain/week_rule_parser.dart';

void main() {
  const parser = WeekRuleParser();

  group('常见周次写法', () {
    final cases =
        <String, ({int start, int end, WeekType type, Set<int>? weeks})>{
          '1-16周': (start: 1, end: 16, type: WeekType.every, weeks: null),
          '1-16': (start: 1, end: 16, type: WeekType.every, weeks: null),
          '1,3,5-9周': (
            start: 1,
            end: 9,
            type: WeekType.custom,
            weeks: {1, 3, 5, 6, 7, 8, 9},
          ),
          '1-16周(单)': (start: 1, end: 16, type: WeekType.odd, weeks: null),
          '1-16周(双)': (start: 1, end: 16, type: WeekType.even, weeks: null),
          '1-16周单周': (start: 1, end: 16, type: WeekType.odd, weeks: null),
          '第1-16周': (start: 1, end: 16, type: WeekType.every, weeks: null),
          '2-18双周': (start: 2, end: 18, type: WeekType.even, weeks: null),
        };

    for (final entry in cases.entries) {
      test(entry.key, () {
        final result = parser.parse(entry.key);
        expect(result.error, isNull);
        expect(result.value!.startWeek, entry.value.start);
        expect(result.value!.endWeek, entry.value.end);
        expect(result.value!.type, entry.value.type);
        expect(result.value!.explicitWeeks, entry.value.weeks);
      });
    }
  });

  test('单周规则只包含奇数周', () {
    final rule = parser.parse('1-16周(单)').value!;
    expect(rule.includes(1), isTrue);
    expect(rule.includes(2), isFalse);
    expect(rule.includes(15), isTrue);
    expect(rule.includes(17), isFalse);
  });

  test('不连续周次不会被扩展', () {
    final rule = parser.parse('1,3,5-9周').value!;
    expect(rule.includes(2), isFalse);
    expect(rule.includes(4), isFalse);
    expect(rule.includes(7), isTrue);
  });

  group('非法周次会明确报错', () {
    for (final text in ['', '第周', '0-10周', '16-1周', '1--3周', '1-16单双周']) {
      test('“$text”', () {
        final result = parser.parse(text);
        expect(result.isSuccess, isFalse);
        expect(result.error, isNotEmpty);
      });
    }
  });
}
