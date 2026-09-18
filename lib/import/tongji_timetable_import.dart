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

    var beforeWeek = text.substring(0, weekMatch.start).trim();
    var location = text.substring(weekMatch.end).trim();
    // 研究生课表写成“课程名([1-16]地点)”，周次外多包了一层圆括号。
    if (beforeWeek.endsWith('(') || beforeWeek.endsWith('（')) {
      beforeWeek = beforeWeek.substring(0, beforeWeek.length - 1).trim();
      location = location.replaceFirst(RegExp(r'[)）]'), ' ');
    }
    location = location
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s,，、;；]+|[\s,，、;；]+$'), '')
        .trim();

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
    final teacherGroups = RegExp(
      r'([^\s,，、()]+)\(\d+\)',
    ).allMatches(teacherText).toList();
    var teachers = teacherGroups
        .map((match) => match.group(1)!)
        .join('、');
    String courseName;
    if (teacherPrefix != null) {
      courseName = courseAndTeachers.substring(teacherPrefix.end).trim();
      // 课程名本身可能写成“体育(1)”，会被上面的规则误当成教师工号。
      // 教师后面已经没有课程名时，把最后一个“名称(数字)”还原成课程名。
      if (courseName.isEmpty && teacherGroups.length >= 2) {
        courseName = teacherGroups.last.group(0)!;
        teachers = teacherGroups
            .take(teacherGroups.length - 1)
            .map((match) => match.group(1)!)
            .join('、');
      }
    } else {
      // 研究生课表没有教师工号，按“教师名 课程名”取第一段中文姓名。
      final withoutCode = RegExp(
        r'^([\u4e00-\u9fa5]{2,4})\s+(\S.*)$',
      ).firstMatch(courseAndTeachers);
      if (withoutCode == null) {
        courseName = courseAndTeachers;
      } else {
        teachers = withoutCode.group(1)!;
        courseName = withoutCode.group(2)!.trim();
      }
    }

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

/// 解析同济 1 系统「排课信息」弹窗的文本。
///
/// 弹窗的星期写在标题里，每行自带节次与周次，例如：
/// ```
/// [星期四] 排课信息
/// [5-6节] [5] 专业导论(理科试验班)(PSE1901) 刘梅川(06059) 北116
/// [5-6节] [1-2] 专业导论(理科试验班)(PSE1901) 邱军(06122) 北116
/// ```
/// 相比读课程卡片，这里不需要用卡片在图上的位置去推算星期与节次——
/// 星期来自标题、节次来自每行，因此不会出现位置推算带来的错位。
///
/// 每行会被改写成与课程卡片一致的文字格式
/// （`教师(工号) 课程名(代码) [周次] 地点`），从而复用同一条解析链路。
///
/// 标题里没有星期、或整段没有任何一行能可靠解析时返回空列表，
/// 由调用方回退到读课程卡片。
List<TongjiTimetableRecord> parseTongjiPopupText(String raw) {
  final weekdayMatch = RegExp(r'\[(星期[一二三四五六日天])\]').firstMatch(raw);
  if (weekdayMatch == null) return const [];
  final weekday = _popupWeekdayNumber(weekdayMatch.group(1)!);
  if (weekday == 0) return const [];

  final records = <TongjiTimetableRecord>[];
  for (final line in raw.split('\n')) {
    final trimmed = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.isEmpty) continue;
    // 每行以 [节次] 开头，例如 [5-6节]、[7-8节]。
    final periodMatch = RegExp(
      r'^\[(\d+)(?:\s*-\s*(\d+))?节\]',
    ).firstMatch(trimmed);
    if (periodMatch == null) continue;
    final start = int.parse(periodMatch.group(1)!);
    final end = int.parse(periodMatch.group(2) ?? periodMatch.group(1)!);
    final rest = trimmed.substring(periodMatch.end).trim();
    // 紧随其后是 [周次]，例如 [2-16双]、[1, 3, 5]。
    final weekMatch = RegExp(r'^\[([^\]]+)\]').firstMatch(rest);
    if (weekMatch == null) continue;
    final body = rest.substring(weekMatch.end).trim();
    if (body.isEmpty) continue;
    // 课程名以英文课程代码结尾。找不到就不猜，跳过这一行。
    final codeMatch = RegExp(
      r'\(([A-Za-z]{2,}[A-Za-z0-9_-]*)\)',
    ).firstMatch(body);
    if (codeMatch == null) continue;
    final coursePart = body.substring(0, codeMatch.end).trim();
    final tail = body.substring(codeMatch.end).trim();
    // 代码之后先是「教师(工号)」，可能多个（逗号或空格分隔）。
    // 缺少教师信息时同样跳过，避免把地点误当成教师。
    final teacherMatch = RegExp(
      r'^((?:[^\s,，、()]+\(\d+\)\s*[,，、]?\s*)+)',
    ).firstMatch(tail);
    if (teacherMatch == null) continue;
    final teachers = teacherMatch.group(1)!.trim();
    final location = tail.substring(teacherMatch.end).trim();
    records.add(
      TongjiTimetableRecord(
        text: '$teachers $coursePart [${weekMatch.group(1)}] $location'.trim(),
        weekday: weekday,
        startPeriod: start,
        endPeriod: end,
      ),
    );
  }
  return records;
}

int _popupWeekdayNumber(String label) {
  const weekdays = {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7,
  };
  for (final entry in weekdays.entries) {
    if (label.contains(entry.key)) return entry.value;
  }
  return 0;
}

/// 把弹窗结果与课程卡片结果按格合并。
///
/// 弹窗信息更完整（一格多课会逐条列出），但它需要光标移入才显示，
/// 可能只成功了一部分。如果直接采用弹窗结果，未成功的格子会整格丢失——
/// 那比读卡片更糟。因此按「格」替换：
///
/// - 弹窗成功的格子（同一星期且节次范围有交集）→ 只用弹窗结果
/// - 弹窗没读到的格子 → 保留课程卡片结果，行为与从前一致
///
/// 这样最坏情况等于现在的行为，不会有任何格子因为弹窗失败而丢失。
/// 最后再按「星期 + 节次 + 原文」去重，重复录入的内容只保留一条。
List<TongjiTimetableRecord> mergePopupWithCards({
  required List<TongjiTimetableRecord> popup,
  required List<TongjiTimetableRecord> cards,
}) {
  if (popup.isEmpty) return dedupeRecords(cards);
  if (cards.isEmpty) return dedupeRecords(popup);
  bool sameCell(TongjiTimetableRecord a, TongjiTimetableRecord b) {
    if (a.weekday != b.weekday) return false;
    return a.startPeriod <= b.endPeriod && b.startPeriod <= a.endPeriod;
  }

  final merged = List<TongjiTimetableRecord>.of(popup);
  for (final card in cards) {
    if (popup.any((record) => sameCell(record, card))) continue;
    merged.add(card);
  }
  return dedupeRecords(merged);
}

/// 去掉完全相同的记录。
///
/// 判重键为「星期 + 起止节次 + 原文」，保留首次出现的那条。
/// 同一门课在不同周次、不同教师下是不同记录（原文不同），因此不会被误删；
/// 只有真正重复的内容才会被合并成一条。
///
/// 之所以需要它：浮层是异步渲染的，光标移入后若浮层没来得及更新，
/// 相邻两格可能读到同一份内容，从而把同一门课写入两次。
List<TongjiTimetableRecord> dedupeRecords(
  List<TongjiTimetableRecord> records,
) {
  final seen = <String>{};
  final result = <TongjiTimetableRecord>[];
  for (final record in records) {
    final key = '${record.weekday}|${record.startPeriod}|'
        '${record.endPeriod}|${record.text}';
    if (!seen.add(key)) continue;
    result.add(record);
  }
  return result;
}
