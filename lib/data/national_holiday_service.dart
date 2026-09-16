import 'dart:convert';
import 'dart:io';

class NationalHolidayCalendar {
  const NationalHolidayCalendar({
    required this.makeupDays,
    required this.holidays,
  });

  final List<DateTime> makeupDays;
  final Map<DateTime, String> holidays;
}

/// 只从中国政府网读取国家公布的放假与调休日期，不上传任何本地数据。
class NationalHolidayService {
  const NationalHolidayService();

  static const _noticeUrls = {
    2026:
        'https://big5.www.gov.cn/gate/big5/www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm',
  };

  Future<List<DateTime>> fetchMakeupDays(int year) async {
    return (await fetchCalendar(year)).makeupDays;
  }

  Future<NationalHolidayCalendar> fetchCalendar(int year) async {
    final url = _noticeUrls[year];
    if (url == null) {
      return const NationalHolidayCalendar(makeupDays: [], holidays: {});
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'OfflineCourseSchedule/0.2',
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('中国政府网返回 ${response.statusCode}');
      }
      final html = await utf8.decoder.bind(response).join();
      final calendar = parseCalendar(html, year);
      if (calendar.makeupDays.isEmpty || calendar.holidays.isEmpty) {
        throw const FormatException('没有识别到完整的国家放假调休安排');
      }
      return calendar;
    } finally {
      client.close(force: true);
    }
  }

  List<DateTime> parseNotice(String html, int year) {
    return parseCalendar(html, year).makeupDays;
  }

  NationalHolidayCalendar parseCalendar(String html, int year) {
    final plain = html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ');
    final makeupDays = <DateTime>{};
    final holidays = <DateTime, String>{};
    for (final sentence in plain.split(RegExp(r'[。；;]'))) {
      if (sentence.contains('上班')) {
        for (final match in RegExp(
          r'(\d{1,2})月(\d{1,2})日（(?:周|週)[一二三四五六日]）',
        ).allMatches(sentence)) {
          makeupDays.add(
            DateTime(
              year,
              int.parse(match.group(1)!),
              int.parse(match.group(2)!),
            ),
          );
        }
      }
      if (!sentence.contains('放假')) continue;
      final name = RegExp(
        r'(元旦|春节|清明节|劳动节|端午节|中秋节|国庆节)',
      ).firstMatch(sentence)?.group(1);
      final range = RegExp(
        r'(\d{1,2})月(\d{1,2})日.*?至(?:(\d{1,2})月)?(\d{1,2})日.*?放假',
      ).firstMatch(sentence);
      if (name == null || range == null) continue;
      var date = DateTime(
        year,
        int.parse(range.group(1)!),
        int.parse(range.group(2)!),
      );
      final end = DateTime(
        year,
        int.parse(range.group(3) ?? range.group(1)!),
        int.parse(range.group(4)!),
      );
      while (!date.isAfter(end)) {
        holidays[date] = name;
        date = date.add(const Duration(days: 1));
      }
    }
    final sortedMakeupDays = makeupDays.toList()..sort();
    return NationalHolidayCalendar(
      makeupDays: sortedMakeupDays,
      holidays: holidays,
    );
  }
}
