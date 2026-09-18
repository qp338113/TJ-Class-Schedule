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
    // 只按课程名分组，**不要**把教师并进分组键。
    //
    // 同一门课在不同周次由不同老师上是常态：同济「排课信息」会把一门课按周次
    // 拆成好几行，每行一位老师、一段周次。若分组键含教师，这门课会被拆成好几门，
    // 整周课表就把它们并排渲染成多张窄卡片，看起来像几节互相冲突的课。
    // 教师差异改由 CourseSession.teacherOverride 逐条表达。
    final groups = <String, List<ImportRow>>{};
    for (final row in validRows) {
      final name = row.cells[ImportField.courseName]!.value! as String;
      groups.putIfAbsent(name.trim().toLowerCase(), () => []).add(row);
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
      final courseId = 'import-course-$courseIndex';
      final name = group.first.cells[ImportField.courseName]!.value! as String;
      // 课程级教师取本课程出现过的全部教师，去重后按出现顺序拼接。
      final teachers = <String>[];
      for (final row in group) {
        final teacher = row.cells[ImportField.teacher]?.value as String? ?? '';
        if (teacher.isEmpty || teachers.contains(teacher)) continue;
        teachers.add(teacher);
      }
      final courseTeacher = teachers.join('、');
      // 同一门课、同一星期、同一节次的多行，是本节课的不同周次，必须并成一条
      // session。否则整周课表会把它们当成互相冲突的课程并排渲染。
      final buckets = <String, List<ImportRow>>{};
      for (final row in group) {
        final periods = row.cells[ImportField.periods]!.value! as PeriodRange;
        final weekday = row.cells[ImportField.weekday]!.value! as int;
        buckets
            .putIfAbsent('$weekday|${periods.start}|${periods.end}', () => [])
            .add(row);
      }
      final sessions = <CourseSession>[];
      var sessionIndex = 0;
      for (final bucket in buckets.values) {
        // 再按地点细分。地点「一方包含另一方」时只是同一处写得详略不同
        // （`四平路校区` 与 `彰武北大楼 409 四平路校区`），应当合并；
        // 真正不同的教室（单周 A101、双周 B202）必须各自成段，
        // 否则会丢掉「哪几周在哪个教室」的信息。
        final clusters = <List<ImportRow>>[];
        for (final row in bucket) {
          final location = _locationOf(row);
          List<ImportRow>? cluster;
          for (final candidate in clusters) {
            if (candidate.every(
              (other) => _locationsCompatible(location, _locationOf(other)),
            )) {
              cluster = candidate;
              break;
            }
          }
          if (cluster == null) {
            cluster = <ImportRow>[];
            clusters.add(cluster);
          }
          cluster.add(row);
        }
        for (final cluster in clusters) {
          final firstRow = cluster.first;
          final periods =
              firstRow.cells[ImportField.periods]!.value! as PeriodRange;
          final bucketTeachers = <String>{};
          for (final row in cluster) {
            final teacher =
                row.cells[ImportField.teacher]?.value as String? ?? '';
            if (teacher.isNotEmpty) bucketTeachers.add(teacher);
          }
          // 只有整段周次都由同一位老师上时才记录教师；老师按周次不同就交给
          // 课程级教师表达，避免只显示其中一位而产生误导。
          final sessionTeacher = bucketTeachers.length == 1
              ? bucketTeachers.first
              : '';
          sessions.add(
            CourseSession(
              id: '$courseId-session-$sessionIndex',
              weekday: firstRow.cells[ImportField.weekday]!.value! as int,
              startPeriod: periods.start,
              endPeriod: periods.end,
              weekRule: _unionWeekRules([
                for (final row in cluster)
                  row.cells[ImportField.weeks]!.value! as WeekRule,
              ]),
              location: _mergeLocations([
                for (final row in cluster) _locationOf(row),
              ]),
              // 与课程级教师一致时不写覆盖，保证单人授课的课程与从前一致。
              teacherOverride:
                  sessionTeacher.isEmpty || sessionTeacher == courseTeacher
                  ? null
                  : sessionTeacher,
            ),
          );
          sessionIndex++;
        }
      }
      courses.add(
        Course(
          id: courseId,
          name: name,
          teacher: courseTeacher,
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

/// 取一行的地点文本。
String _locationOf(ImportRow row) =>
    (row.cells[ImportField.location]?.value as String? ?? '').trim();

/// 两段地点文字是否可能是同一个地方。
///
/// 同一节课在不同行里地点写得详略不同（`四平路校区` 与
/// `彰武北大楼 409 四平路校区`），这类应当合并。任一方为空时无法判断，
/// 也按兼容处理——空地点不该把课程拆开。只有两边都是具体地点、
/// 且互不包含时才视为不同教室（例如 `北201` 与 `南301`）。
bool _locationsCompatible(String a, String b) {
  if (a.isEmpty || b.isEmpty) return true;
  return a.contains(b) || b.contains(a);
}

/// 合并同一节课的地点：取最具体（最长）的那条。
///
/// 例：`四平路校区` 与 `彰武北大楼 409 四平路校区` → 取后者。
String _mergeLocations(List<String> locations) {
  var best = '';
  for (final location in locations) {
    if (location.length > best.length) best = location;
  }
  return best;
}

/// 把同一节课的几段周次并成一条规则。
///
/// 同济「排课信息」会把一门课按周次切成多行（例如 `[1-2, 15]`、`[3-10]`、
/// `[11-14, 16]`），它们本是**同一节课**的不同周次，合并后应当覆盖 1-16 周，
/// 而不是三条互相冲突的课程。只有一段时原样返回，保证既有行为不变。
WeekRule _unionWeekRules(List<WeekRule> rules) {
  if (rules.length == 1) return rules.single;
  final weeks = <int>{};
  for (final rule in rules) {
    for (var week = rule.startWeek; week <= rule.endWeek; week++) {
      if (rule.includes(week)) weeks.add(week);
    }
  }
  final sorted = weeks.toList()..sort();
  final first = sorted.first;
  final last = sorted.last;
  final type = rules.first.type;
  if (rules.every((rule) => rule.type == type) && type != WeekType.custom) {
    // 类型一致时优先保留该属性，显示成「2-16周(双)」这类更好读的形式。
    // 但必须先验证压缩后完全等价：若各段之间有断档（例如都是每周课的
    // [1-2] 与 [5-6]），压成「1-6周」会把没课的 3、4 周也算进来。
    final compact = WeekRule(startWeek: first, endWeek: last, type: type);
    final equivalent = List<int>.generate(
      last - first + 1,
      (index) => first + index,
    ).every((week) => compact.includes(week) == weeks.contains(week));
    if (equivalent) return compact;
  }
  return WeekRule(
    startWeek: first,
    endWeek: last,
    type: WeekType.custom,
    explicitWeeks: weeks,
  );
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
