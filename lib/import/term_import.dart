import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../domain/schedule_models.dart';
import '../domain/week_rule_parser.dart';

class TermImportSuggestion {
  const TermImportSuggestion({
    required this.totalWeeks,
    required this.periods,
    required this.usedDefaultPeriods,
  });

  final int? totalWeeks;
  final List<LessonPeriod> periods;
  final bool usedDefaultPeriods;
}

/// 从课表文件中提取“学期设置”所需的周数与作息时间。
class TermImportParser {
  const TermImportParser({this.weekRuleParser = const WeekRuleParser()});

  final WeekRuleParser weekRuleParser;

  TermImportSuggestion parseCsv(String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final table = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(normalized)
        .map((row) => row.map((cell) => cell.toString()).toList())
        .toList();
    return _parseTable(table);
  }

  TermImportSuggestion parseXlsx(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    for (final sheet in workbook.tables.values) {
      final table = sheet.rows
          .map(
            (row) => row.map((cell) => cell?.value?.toString() ?? '').toList(),
          )
          .toList();
      if (table.any((row) => row.any((cell) => cell.trim().isNotEmpty))) {
        return _parseTable(table);
      }
    }
    return _suggestion(null, const []);
  }

  TermImportSuggestion inferFromText(String text) {
    final candidates = <String>[];
    final pattern = RegExp(
      r'\[([0-9,，、\-－—–\s单双周]+)\]|((?:第)?\d+(?:\s*[-－—–]\s*\d+)?(?:周(?:\s*[（(]?[单双][）)]?)?|[单双]周))',
    );
    for (final match in pattern.allMatches(text)) {
      candidates.add(match.group(1) ?? match.group(2)!);
    }
    return _suggestion(_maxWeek(candidates), const []);
  }

  TermImportSuggestion _parseTable(List<List<String>> table) {
    if (table.isEmpty) return _suggestion(null, const []);
    final headerIndex = table.indexWhere(
      (row) => row.any((cell) {
        final name = _header(cell);
        return _weekHeaders.contains(name) || _periodHeaders.contains(name);
      }),
    );
    if (headerIndex < 0) {
      return inferFromText(table.expand((row) => row).join('\n'));
    }
    final header = table[headerIndex].map(_header).toList();
    final weekColumn = header.indexWhere(_weekHeaders.contains);
    final periodColumn = header.indexWhere(_periodHeaders.contains);
    final timeColumn = header.indexWhere(_timeHeaders.contains);
    final weekTexts = <String>[];
    final timeRows = <({String period, String time})>[];
    for (final row in table.skip(headerIndex + 1)) {
      if (weekColumn >= 0 && weekColumn < row.length) {
        weekTexts.add(row[weekColumn]);
      }
      if (periodColumn >= 0 &&
          timeColumn >= 0 &&
          periodColumn < row.length &&
          timeColumn < row.length) {
        timeRows.add((period: row[periodColumn], time: row[timeColumn]));
      }
    }
    return _suggestion(_maxWeek(weekTexts), timeRows);
  }

  TermImportSuggestion _suggestion(
    int? totalWeeks,
    List<({String period, String time})> timeRows,
  ) {
    final periods = List<LessonPeriod>.of(tongjiLessonPeriods);
    var usedFileTime = false;
    for (final row in timeRows) {
      final periodMatch = RegExp(
        r'(\d+)\s*(?:[-－—–~至]\s*(\d+))?',
      ).firstMatch(row.period);
      final timeMatch = RegExp(
        r'(\d{1,2}):(\d{2})\s*[-－—–~至]\s*(\d{1,2}):(\d{2})',
      ).firstMatch(row.time);
      if (periodMatch == null || timeMatch == null) continue;
      final startPeriod = int.parse(periodMatch.group(1)!);
      final endPeriod = int.parse(
        periodMatch.group(2) ?? periodMatch.group(1)!,
      );
      if (startPeriod < 1 ||
          endPeriod > periods.length ||
          endPeriod < startPeriod) {
        continue;
      }
      final startMinutes =
          int.parse(timeMatch.group(1)!) * 60 + int.parse(timeMatch.group(2)!);
      final endMinutes =
          int.parse(timeMatch.group(3)!) * 60 + int.parse(timeMatch.group(4)!);
      if (startMinutes >= endMinutes || endMinutes > 24 * 60) continue;
      if (startPeriod == endPeriod) {
        periods[startPeriod - 1] = LessonPeriod(
          number: startPeriod,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
        );
        usedFileTime = true;
        continue;
      }
      final first = periods[startPeriod - 1];
      final last = periods[endPeriod - 1];
      periods[startPeriod - 1] = LessonPeriod(
        number: startPeriod,
        startMinutes: startMinutes,
        endMinutes: first.endMinutes > startMinutes
            ? first.endMinutes
            : endMinutes,
      );
      periods[endPeriod - 1] = LessonPeriod(
        number: endPeriod,
        startMinutes: last.startMinutes < endMinutes
            ? last.startMinutes
            : startMinutes,
        endMinutes: endMinutes,
      );
      usedFileTime = true;
    }
    return TermImportSuggestion(
      totalWeeks: totalWeeks,
      periods: List<LessonPeriod>.unmodifiable(periods),
      usedDefaultPeriods: !usedFileTime,
    );
  }

  int? _maxWeek(Iterable<String> values) {
    int? maximum;
    for (final value in values) {
      final result = weekRuleParser.parse(value);
      final end = result.value?.endWeek;
      if (end != null && (maximum == null || end > maximum)) maximum = end;
    }
    return maximum;
  }

  String _header(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s_（）()]'), '');
}

const _weekHeaders = {'周次', '周次范围', '教学周', '上课周次'};
const _periodHeaders = {'节次', '上课节次', '课程节次'};
const _timeHeaders = {'上课时间', '时间', '节次时间', '起止时间'};

/// 同济大学 2026—2027 学年第一学期校历中的作息时间。
const tongjiLessonPeriods = [
  LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525),
  LessonPeriod(number: 2, startMinutes: 530, endMinutes: 575),
  LessonPeriod(number: 3, startMinutes: 600, endMinutes: 645),
  LessonPeriod(number: 4, startMinutes: 650, endMinutes: 695),
  LessonPeriod(number: 5, startMinutes: 810, endMinutes: 855),
  LessonPeriod(number: 6, startMinutes: 860, endMinutes: 905),
  LessonPeriod(number: 7, startMinutes: 930, endMinutes: 975),
  LessonPeriod(number: 8, startMinutes: 980, endMinutes: 1025),
  LessonPeriod(number: 9, startMinutes: 1110, endMinutes: 1155),
  LessonPeriod(number: 10, startMinutes: 1160, endMinutes: 1205),
  LessonPeriod(number: 11, startMinutes: 1210, endMinutes: 1255),
];
