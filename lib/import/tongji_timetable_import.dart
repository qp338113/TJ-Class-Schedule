import 'course_import.dart';

class TongjiTimetableRecord {
  const TongjiTimetableRecord({
    required this.text,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
  });

  final String text;
  final int weekday;
  final int startPeriod;
  final int endPeriod;

  factory TongjiTimetableRecord.fromJson(Map<String, Object?> json) {
    return TongjiTimetableRecord(
      text: json['text'] as String? ?? '',
      weekday: (json['weekday'] as num?)?.toInt() ?? 0,
      startPeriod: (json['startPeriod'] as num?)?.toInt() ?? 0,
      endPeriod: (json['endPeriod'] as num?)?.toInt() ?? 0,
    );
  }
}

class TongjiTimetableImportParser {
  const TongjiTimetableImportParser({
    this.courseImportParser = const CourseImportParser(),
  });

  final CourseImportParser courseImportParser;

  ImportPreview parse(List<TongjiTimetableRecord> records) {
    final sortedRecords = List<TongjiTimetableRecord>.of(records)
      ..sort((a, b) {
        final weekdayOrder = a.weekday.compareTo(b.weekday);
        if (weekdayOrder != 0) return weekdayOrder;
        final startOrder = a.startPeriod.compareTo(b.startPeriod);
        if (startOrder != 0) return startOrder;
        final endOrder = a.endPeriod.compareTo(b.endPeriod);
        return endOrder != 0 ? endOrder : a.text.compareTo(b.text);
      });
    final table = <List<String>>[
      const ['课程名', '教师', '地点', '周几', '节次', '周次范围'],
    ];
    for (final record in sortedRecords) {
      table.add(_recordToRow(record));
    }
    return courseImportParser.parseTable(table, sheetName: '同济1系统');
  }

  List<String> _recordToRow(TongjiTimetableRecord record) {
    final text = record.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final weekMatch = RegExp(r'\[([^\]]+)\]').firstMatch(text);
    if (weekMatch == null) {
      return [text, '', '', '${record.weekday}', _periods(record), ''];
    }

    final beforeWeek = text.substring(0, weekMatch.start).trim();
    final location = text.substring(weekMatch.end).trim();
    final codeMatch = RegExp(
      r'\(([A-Za-z]{2,}[A-Za-z0-9_-]*)\)\s*$',
    ).firstMatch(beforeWeek);
    final courseAndTeachers = codeMatch == null
        ? beforeWeek
        : beforeWeek.substring(0, codeMatch.start).trim();
    final teacherPrefix = RegExp(
      r'^((?:[^\s,，、()]+\(\d+\)\s*[,，、]?\s*)+)',
    ).firstMatch(courseAndTeachers);
    final teacherText = teacherPrefix?.group(1) ?? '';
    final teachers = RegExp(
      r'([^\s,，、()]+)\(\d+\)',
    ).allMatches(teacherText).map((match) => match.group(1)!).join('、');
    final courseName = teacherPrefix == null
        ? courseAndTeachers
        : courseAndTeachers.substring(teacherPrefix.end).trim();

    return [
      courseName,
      teachers,
      location,
      '${record.weekday}',
      _periods(record),
      '${weekMatch.group(1)}周',
    ];
  }

  String _periods(TongjiTimetableRecord record) =>
      '${record.startPeriod}-${record.endPeriod}节';
}
