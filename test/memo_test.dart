import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';

void main() {
  group('备忘录时间类型校验', () {
    test('同时传入按周重复与一次性时间时构造失败', () {
      expect(
        () => Memo(
          id: 'memo-1',
          title: '例会',
          colorValue: 0xFF7D9DCE,
          weekday: 3,
          startPeriod: 7,
          endPeriod: 8,
          weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
          date: DateTime(2026, 10, 1),
          startMinutes: 840,
          endMinutes: 930,
        ),
        throwsArgumentError,
      );
    });

    test('两种时间类型都不填时构造失败', () {
      expect(
        () => Memo(id: 'memo-1', title: '例会', colorValue: 0xFF7D9DCE),
        throwsArgumentError,
      );
    });

    test('按周重复缺少周次规则时构造失败', () {
      expect(
        () => Memo(
          id: 'memo-1',
          title: '例会',
          colorValue: 0xFF7D9DCE,
          weekday: 3,
          startPeriod: 7,
          endPeriod: 8,
        ),
        throwsArgumentError,
      );
    });

    test('一次性缺少起止时刻时构造失败', () {
      expect(
        () => Memo(
          id: 'memo-1',
          title: '体检',
          colorValue: 0xFF7D9DCE,
          date: DateTime(2026, 10, 1),
          startMinutes: 840,
        ),
        throwsArgumentError,
      );
    });

    test('一次性时间混入节次或周次规则时构造失败', () {
      expect(
        () => Memo(
          id: 'memo-1',
          title: '体检',
          colorValue: 0xFF7D9DCE,
          weekday: 3,
          date: DateTime(2026, 10, 1),
          startMinutes: 840,
          endMinutes: 930,
        ),
        throwsArgumentError,
      );
    });
  });

  group('备忘录字段校验', () {
    test('标题不能为空', () {
      expect(
        () => Memo(
          id: 'memo-1',
          title: '   ',
          colorValue: 0xFF7D9DCE,
          weekday: 3,
          startPeriod: 7,
          endPeriod: 8,
          weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
        ),
        throwsArgumentError,
      );
    });

    test('星期与节次越界时构造失败', () {
      expect(
        () => Memo(
          id: 'memo-1',
          title: '例会',
          colorValue: 1,
          weekday: 8,
          startPeriod: 7,
          endPeriod: 8,
          weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
        ),
        throwsArgumentError,
      );
      expect(
        () => Memo(
          id: 'memo-1',
          title: '例会',
          colorValue: 1,
          weekday: 3,
          startPeriod: 8,
          endPeriod: 7,
          weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
        ),
        throwsArgumentError,
      );
    });

    test('一次性时刻越界时构造失败', () {
      expect(
        () => Memo(
          id: 'memo-1',
          title: '体检',
          colorValue: 1,
          date: DateTime(2026, 10, 1),
          startMinutes: -1,
          endMinutes: 930,
        ),
        throwsArgumentError,
      );
      expect(
        () => Memo(
          id: 'memo-1',
          title: '体检',
          colorValue: 1,
          date: DateTime(2026, 10, 1),
          startMinutes: 930,
          endMinutes: 930,
        ),
        throwsArgumentError,
      );
      expect(
        () => Memo(
          id: 'memo-1',
          title: '体检',
          colorValue: 1,
          date: DateTime(2026, 10, 1),
          startMinutes: 840,
          endMinutes: 1441,
        ),
        throwsArgumentError,
      );
    });
  });

  group('备忘录取值', () {
    test('按周重复的备忘录日期为 null 且 isRecurring 为真', () {
      final memo = Memo(
        id: 'memo-1',
        title: '例会',
        location: 'A101',
        colorValue: 1,
        weekday: DateTime.wednesday,
        startPeriod: 7,
        endPeriod: 8,
        weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
      );

      expect(memo.date, isNull);
      expect(memo.isRecurring, isTrue);
      expect(memo.location, 'A101');
    });

    test('一次性备忘录的日期按年月日归一化且 isRecurring 为假', () {
      final memo = Memo(
        id: 'memo-1',
        title: '体检',
        colorValue: 1,
        date: DateTime(2026, 10, 1, 14, 30, 45),
        startMinutes: 840,
        endMinutes: 930,
      );

      expect(memo.date, DateTime(2026, 10, 1));
      expect(memo.isRecurring, isFalse);
      expect(memo.weekday, isNull);
      expect(memo.weekRule, isNull);
      expect(memo.location, '');
    });
  });
}
