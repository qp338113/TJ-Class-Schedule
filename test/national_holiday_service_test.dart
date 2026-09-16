import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/national_holiday_service.dart';

void main() {
  test('从国务院通知中只提取调休上班日期', () {
    const service = NationalHolidayService();
    final dates = service.parseNotice(
      '春节放假。2月14日（周六）、2月28日（周六）上班。'
      '国庆放假。9月20日（週日）、10月10日（週六）上班。',
      2026,
    );

    expect(dates, [
      DateTime(2026, 2, 14),
      DateTime(2026, 2, 28),
      DateTime(2026, 9, 20),
      DateTime(2026, 10, 10),
    ]);
  });

  test('从国务院通知中提取完整放假日期和节日名称', () {
    const service = NationalHolidayService();
    final calendar = service.parseCalendar(
      '一、元旦：1月1日（周四）至3日（周六）放假调休，共3天。'
      '1月4日（周日）上班。'
      '七、国庆节：10月1日（周四）至7日（周三）放假调休，共7天。'
      '9月20日（周日）、10月10日（周六）上班。',
      2026,
    );

    expect(calendar.holidays[DateTime(2026, 1, 1)], '元旦');
    expect(calendar.holidays[DateTime(2026, 1, 3)], '元旦');
    expect(calendar.holidays[DateTime(2026, 10, 7)], '国庆节');
    expect(calendar.holidays, hasLength(10));
    expect(calendar.makeupDays, [
      DateTime(2026, 1, 4),
      DateTime(2026, 9, 20),
      DateTime(2026, 10, 10),
    ]);
  });
}
