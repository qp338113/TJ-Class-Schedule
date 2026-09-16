import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../domain/schedule_models.dart';
import '../domain/week_rule_parser.dart';

enum ImportField { courseName, teacher, location, weekday, periods, weeks }

class ImportCell<T> {
  const ImportCell({required this.raw, this.value, this.warning});

  final String raw;
  final T? value;
  final String? warning;

  /// 预览页据此把单元格标成黄色。
  bool get needsAttention => warning != null;
}

class ImportRow {
  const ImportRow({required this.sourceRow, required this.cells});

  final int sourceRow;
  final Map<ImportField, ImportCell<Object>> cells;

  bool get isValid => const [
    ImportField.courseName,
    ImportField.weekday,
    ImportField.periods,
    ImportField.weeks,
  ].every((field) => cells[field]?.needsAttention == false);
}

class ImportPreview {
  const ImportPreview({
    required this.sheetName,
    required this.headerRow,
    required this.columnIndexes,
    required this.rows,
    this.errors = const [],
  });

  final String sheetName;
  final int headerRow;
  final Map<ImportField, int> columnIndexes;
  final List<ImportRow> rows;
  final List<String> errors;

  bool get canImport => errors.isEmpty && rows.any((row) => row.isValid);
}

class PeriodRange {
  const PeriodRange(this.start, this.end);
  final int start;
  final int end;
}

class ImportCommitResult {
  const ImportCommitResult({required this.courses, required this.rejectedRows});
  final List<Course> courses;
  final List<ImportRow> rejectedRows;
}

class CourseImportParser {
  const CourseImportParser({this.weekRuleParser = const WeekRuleParser()});

  final WeekRuleParser weekRuleParser;

  ImportPreview parseCsv(String content) {
    final text = content.startsWith('\uFEFF') ? content.substring(1) : content;
    final normalizedText = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final table = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(normalizedText)
        .map((row) => row.map((value) => value.toString()).toList())
        .toList();
    return parseTable(table, sheetName: 'CSV');
  }

  ImportPreview parseXlsx(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    for (final entry in workbook.tables.entries) {
      final table = entry.value.rows
          .map(
            (row) => row.map((cell) => cell?.value?.toString() ?? '').toList(),
          )
          .toList();
      if (table.any((row) => row.any((cell) => cell.trim().isNotEmpty))) {
        return parseTable(table, sheetName: entry.key);
      }
    }
    return const ImportPreview(
      sheetName: '',
      headerRow: -1,
      columnIndexes: {},
      rows: [],
      errors: ['Excel 中没有可导入的数据'],
    );
  }

  ImportPreview parseTable(List<List<String>> table, {String sheetName = ''}) {
    if (table.isEmpty) {
      return ImportPreview(
        sheetName: sheetName,
        headerRow: -1,
        columnIndexes: const {},
        rows: const [],
        errors: const ['文件内容为空'],
      );
    }
    final header = _findHeader(table);
    if (header == null) {
      return ImportPreview(
        sheetName: sheetName,
        headerRow: -1,
        columnIndexes: const {},
        rows: const [],
        errors: const ['未找到课程名、周几、节次、周次范围这些必需列'],
      );
    }
    final missing = _requiredFields.where(
      (field) => !header.columns.containsKey(field),
    );
    if (missing.isNotEmpty) {
      return ImportPreview(
        sheetName: sheetName,
        headerRow: header.row,
        columnIndexes: header.columns,
        rows: const [],
        errors: ['缺少必需列：${missing.map(_fieldName).join('、')}'],
      );
    }

    final rows = <ImportRow>[];
    for (var index = header.row + 1; index < table.length; index++) {
      if (table[index].every((cell) => cell.trim().isEmpty)) continue;
      rows.add(_parseRow(index, table[index], header.columns));
    }
    return ImportPreview(
      sheetName: sheetName,
      headerRow: header.row,
      columnIndexes: header.columns,
      rows: List<ImportRow>.unmodifiable(rows),
    );
  }

  /// 用户修正一个单元格后，只重算该格，不影响同一行的其他修改。
  ImportPreview updateCell(
    ImportPreview preview,
    int sourceRow,
    ImportField field,
    String newText,
  ) {
    final rows = preview.rows.map((row) {
      if (row.sourceRow != sourceRow) return row;
      final cells = Map<ImportField, ImportCell<Object>>.of(row.cells);
      cells[field] = _parseCell(field, newText);
      return ImportRow(
        sourceRow: row.sourceRow,
        cells: Map<ImportField, ImportCell<Object>>.unmodifiable(cells),
      );
    }).toList();
    return ImportPreview(
      sheetName: preview.sheetName,
      headerRow: preview.headerRow,
      columnIndexes: preview.columnIndexes,
      rows: List<ImportRow>.unmodifiable(rows),
      errors: preview.errors,
    );
  }

  ImportPreview removeRow(ImportPreview preview, int sourceRow) {
    return ImportPreview(
      sheetName: preview.sheetName,
      headerRow: preview.headerRow,
      columnIndexes: preview.columnIndexes,
      rows: List<ImportRow>.unmodifiable(
        preview.rows.where((row) => row.sourceRow != sourceRow),
      ),
      errors: preview.errors,
    );
  }

  ImportCommitResult buildCourses(ImportPreview preview) {
    final validRows = preview.rows.where((row) => row.isValid).toList();
    final groups = <String, List<ImportRow>>{};
    for (final row in validRows) {
      final name = row.cells[ImportField.courseName]!.value! as String;
      final teacher = row.cells[ImportField.teacher]?.value as String? ?? '';
      groups.putIfAbsent('$name\u0000$teacher', () => []).add(row);
    }
    const palette = [
      0xFF7D9DCE,
      0xFF7FB69D,
      0xFFD19A8A,
      0xFFB497C9,
      0xFFD0B36C,
      0xFF6FAFB5,
    ];
    var courseIndex = 0;
    final courses = <Course>[];
    for (final group in groups.values) {
      final first = group.first;
      final courseId = 'import-course-$courseIndex';
      final name = first.cells[ImportField.courseName]!.value! as String;
      final teacher = first.cells[ImportField.teacher]?.value as String? ?? '';
      final sessions = <CourseSession>[];
      for (var sessionIndex = 0; sessionIndex < group.length; sessionIndex++) {
        final row = group[sessionIndex];
        final periods = row.cells[ImportField.periods]!.value! as PeriodRange;
        sessions.add(
          CourseSession(
            id: '$courseId-session-$sessionIndex',
            weekday: row.cells[ImportField.weekday]!.value! as int,
            startPeriod: periods.start,
            endPeriod: periods.end,
            weekRule: row.cells[ImportField.weeks]!.value! as WeekRule,
            location: row.cells[ImportField.location]?.value as String? ?? '',
          ),
        );
      }
      courses.add(
        Course(
          id: courseId,
          name: name,
          teacher: teacher,
          colorValue: palette[courseIndex % palette.length],
          sessions: List<CourseSession>.unmodifiable(sessions),
        ),
      );
      courseIndex++;
    }
    return ImportCommitResult(
      courses: List<Course>.unmodifiable(courses),
      rejectedRows: List<ImportRow>.unmodifiable(
        preview.rows.where((row) => !row.isValid),
      ),
    );
  }

  ImportRow _parseRow(
    int sourceRow,
    List<String> row,
    Map<ImportField, int> columns,
  ) {
    final cells = <ImportField, ImportCell<Object>>{};
    for (final field in ImportField.values) {
      final column = columns[field];
      final raw = column != null && column < row.length ? row[column] : '';
      cells[field] = _parseCell(field, raw);
    }
    return ImportRow(
      sourceRow: sourceRow,
      cells: Map<ImportField, ImportCell<Object>>.unmodifiable(cells),
    );
  }

  ImportCell<Object> _parseCell(ImportField field, String raw) {
    final text = raw.trim();
    switch (field) {
      case ImportField.courseName:
        return text.isEmpty
            ? ImportCell(raw: raw, warning: '课程名不能为空')
            : ImportCell(raw: raw, value: text);
      case ImportField.teacher:
      case ImportField.location:
        return ImportCell(raw: raw, value: text);
      case ImportField.weekday:
        final value = _parseWeekday(text);
        return value == null
            ? ImportCell(raw: raw, warning: '无法识别周几')
            : ImportCell(raw: raw, value: value);
      case ImportField.periods:
        final value = _parsePeriods(text);
        return value == null
            ? ImportCell(raw: raw, warning: '无法识别节次')
            : ImportCell(raw: raw, value: value);
      case ImportField.weeks:
        final result = weekRuleParser.parse(text);
        return result.isSuccess
            ? ImportCell(raw: raw, value: result.value)
            : ImportCell(raw: raw, warning: result.error);
    }
  }

  int? _parseWeekday(String text) {
    const names = {
      '1': 1,
      '一': 1,
      '周一': 1,
      '星期一': 1,
      '2': 2,
      '二': 2,
      '周二': 2,
      '星期二': 2,
      '3': 3,
      '三': 3,
      '周三': 3,
      '星期三': 3,
      '4': 4,
      '四': 4,
      '周四': 4,
      '星期四': 4,
      '5': 5,
      '五': 5,
      '周五': 5,
      '星期五': 5,
      '6': 6,
      '六': 6,
      '周六': 6,
      '星期六': 6,
      '7': 7,
      '日': 7,
      '天': 7,
      '周日': 7,
      '周天': 7,
      '星期日': 7,
      '星期天': 7,
    };
    return names[text.replaceAll(RegExp(r'\s+'), '')];
  }

  PeriodRange? _parsePeriods(String text) {
    final normalized = text
        .replaceAll(RegExp(r'[第节课\s]'), '')
        .replaceAll(RegExp(r'[－—–~～至]'), '-');
    final match = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(normalized);
    if (match == null) return null;
    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2) ?? match.group(1)!);
    return start > 0 && end >= start ? PeriodRange(start, end) : null;
  }

  _DetectedHeader? _findHeader(List<List<String>> table) {
    _DetectedHeader? best;
    for (var row = 0; row < table.length && row < 10; row++) {
      final columns = <ImportField, int>{};
      for (var column = 0; column < table[row].length; column++) {
        final field = _detectField(table[row][column]);
        if (field != null) columns.putIfAbsent(field, () => column);
      }
      if (best == null || columns.length > best.columns.length) {
        best = _DetectedHeader(row, columns);
      }
    }
    return best?.columns.isEmpty == true ? null : best;
  }

  ImportField? _detectField(String header) {
    final text = header.toLowerCase().replaceAll(RegExp(r'[\s_()（）]'), '');
    for (final entry in _aliases.entries) {
      if (entry.value.any((alias) => text == alias || text.contains(alias))) {
        return entry.key;
      }
    }
    return null;
  }
}

class _DetectedHeader {
  const _DetectedHeader(this.row, this.columns);
  final int row;
  final Map<ImportField, int> columns;
}

const _requiredFields = {
  ImportField.courseName,
  ImportField.weekday,
  ImportField.periods,
  ImportField.weeks,
};

const _aliases = <ImportField, List<String>>{
  ImportField.courseName: ['课程名', '课程名称', '课程'],
  ImportField.teacher: ['教师', '老师', '任课教师'],
  ImportField.location: ['地点', '教室', '上课地点'],
  ImportField.weekday: ['周几', '星期', '上课日期'],
  ImportField.periods: ['节次', '上课节次', '课节'],
  ImportField.weeks: ['周次范围', '周次', '教学周'],
};

String _fieldName(ImportField field) => switch (field) {
  ImportField.courseName => '课程名',
  ImportField.teacher => '教师',
  ImportField.location => '地点',
  ImportField.weekday => '周几',
  ImportField.periods => '节次',
  ImportField.weeks => '周次范围',
};
