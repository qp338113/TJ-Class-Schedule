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
  for (final entry in _joinWrappedPopupLines(raw)) {
    // 一行里可能挤着好几条（例如「…南201 [3-4节] [2-16双] …」），
    // 必须按 [节次] 逐条切开，否则第二条会被当成第一条的地点吞掉。
    for (final chunk in _splitPopupChunks(entry)) {
      records.addAll(_parsePopupChunk(chunk, weekday));
    }
  }
  return records;
}

/// 浮层里的一条排课：节次，以及 `[节次]` 之后的原始正文。
class _PopupChunk {
  const _PopupChunk({
    required this.start,
    required this.end,
    required this.body,
  });

  final int start;
  final int end;
  final String body;
}

final _popupPeriodPattern = RegExp(r'\[(\d+)(?:\s*-\s*(\d+))?节\]');
final _popupNumbering = RegExp(r'^\[([^\]]+)\]\s*');

/// 把浮层里被折行的条目接回成一条。
///
/// 浮层宽度有限，长条目会折行。真实截图里的例子（注意工号被从中间截断）：
/// ```
/// [3-4节] [1, 3, 5, 7, 9, 11, 13, 15] 高等数学B(I)(CMS1221) 颜启明(0911
/// 8) 北301
/// ```
/// 逐行解析会把第二行当成独立条目丢掉，同时工号残缺导致正则匹配不到，
/// 于是**整条记录消失**，那一格就少了这门课。
///
/// 续行用**空串**拼接而不是空格：折行可能把 `(09118)` 断成 `(0911`/`8)`、
/// 把 `南310` 断成 `南3`/`10`，补空格反而会拼错。
///
/// 带序号的行（`1.[3-4节]`、`2.[3-4节]`）也算**新的一条**，不能并到上一条里，
/// 否则序号那几条会整条丢失。
List<String> _joinWrappedPopupLines(String raw) {
  final entries = <String>[];
  for (final line in raw.split('\n')) {
    final trimmed = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.isEmpty) continue;
    final startsEntry = RegExp(
      r'^(?:\d+\s*[.、]\s*)?\[\d+(?:\s*-\s*\d+)?节\]',
    ).hasMatch(trimmed);
    if (startsEntry || entries.isEmpty) {
      entries.add(trimmed);
    } else {
      entries[entries.length - 1] = entries.last + trimmed;
    }
  }
  return entries;
}

/// 按 `[节次]` 把一个条目切成若干条排课。
List<_PopupChunk> _splitPopupChunks(String entry) {
  final matches = _popupPeriodPattern.allMatches(entry).toList();
  final chunks = <_PopupChunk>[];
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final end = index + 1 < matches.length
        ? matches[index + 1].start
        : entry.length;
    // 序号（如 `2.`）写在下一段 `[节次]` 之前，属于下一段，不属于本段正文。
    final body = entry
        .substring(match.end, end)
        .replaceFirst(RegExp(r'\s*\d+\s*[.、]\s*$'), '')
        .trim();
    chunks.add(
      _PopupChunk(
        start: int.parse(match.group(1)!),
        end: int.parse(match.group(2) ?? match.group(1)!),
        body: body,
      ),
    );
  }
  return chunks;
}

/// 解析一条排课正文，可能产出多条记录（同一节课按周次拆成多段）。
List<TongjiTimetableRecord> _parsePopupChunk(_PopupChunk chunk, int weekday) {
  var body = chunk.body;
  // 行首的 [周次]，例如 [2-16双]、[1, 3, 5]。研究生课表还会把它写在圆括号里，
  // 那一份在分段里单独处理。
  String? leadingWeeks;
  final lead = _popupNumbering.firstMatch(body);
  if (lead != null && _looksLikeWeekSpec(lead.group(1)!)) {
    leadingWeeks = lead.group(1);
    body = body.substring(lead.end).trim();
  }
  if (body.isEmpty) return const [];

  final records = <TongjiTimetableRecord>[];
  for (final segment in _splitPopupSegments(body)) {
    final record = _parsePopupSegment(segment, weekday, chunk, leadingWeeks);
    if (record != null) records.add(record);
  }
  return records;
}

/// 按逗号把一条正文切成若干段。
///
/// 只在下一次出现「教师名 + 空格 + 课程名」时才切，例如
/// `…四平路校区, 钱杨 学术英语写作III([…]彰武北大楼 409) …`
/// ——它们是**同一节课按周次拆成的两段**，各有各的周次与地点。
///
/// 而 `邱军(06122),刘宁(21019)` 这种教师并列不能切：后面的名字紧跟着
/// 工号括号而不是空格，说明它还是同一条。方括号与圆括号内部的逗号也不切。
List<String> _splitPopupSegments(String body) {
  final segments = <String>[];
  var depth = 0;
  var start = 0;
  for (var index = 0; index < body.length; index++) {
    final char = body[index];
    if (char == '[' || char == '(' || char == '（') {
      depth++;
    } else if (char == ']' || char == ')' || char == '）') {
      if (depth > 0) depth--;
    } else if ((char == ',' || char == '，') && depth == 0) {
      final rest = body.substring(index + 1);
      if (RegExp(r'^\s*[\u4e00-\u9fa5]{2,4}\s+\S').hasMatch(rest)) {
        segments.add(body.substring(start, index));
        start = index + 1;
      }
    }
  }
  segments.add(body.substring(start));
  return segments
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();
}

/// 解析单个分段，产出与课程卡片一致格式的记录：
/// 本科 `教师(工号) 课程名(代码) [周次] 地点`，
/// 研究生 `教师 课程名 [周次] 地点`。
TongjiTimetableRecord? _parsePopupSegment(
  String segment,
  int weekday,
  _PopupChunk chunk,
  String? leadingWeeks,
) {
  // —— 本科格式：课程名(课程代码) 教师(工号) 地点 ——
  final codeMatch = RegExp(
    r'\(([A-Za-z]{2,}[A-Za-z0-9_-]*)\)',
  ).firstMatch(segment);
  if (codeMatch != null) {
    final tail = segment.substring(codeMatch.end).trim();
    // 工号可能是一个也可能是多个，用逗号或空格分隔。
    final teacherMatch = RegExp(
      r'^((?:[^\s,，、()]+\(\d+\)\s*[,，、]?\s*)+)',
    ).firstMatch(tail);
    if (teacherMatch != null) {
      final weeks = leadingWeeks;
      if (weeks == null) return null;
      final teachers = teacherMatch.group(1)!.trim();
      final location = tail.substring(teacherMatch.end).trim();
      final coursePart = segment.substring(0, codeMatch.end).trim();
      return TongjiTimetableRecord(
        text: '$teachers $coursePart [$weeks] $location'.trim(),
        weekday: weekday,
        startPeriod: chunk.start,
        endPeriod: chunk.end,
      );
    }
  }

  // —— 研究生格式：教师名 课程名(… ) 地点 ——
  //
  // 这种课表既没有课程代码也没有教师工号，例如
  // `钱杨 学术英语写作III( ) 四平路校区`；
  // 周次可能写在行首，也可能写在圆括号里（`学术英语写作III([1-3, 5, 7]彰武北大楼 409)`）。
  // 必须要求存在圆括号组：否则像「某门课 某老师 某地」这种说明文字会被误判成课程。
  final nameMatch = RegExp(
    r'^([\u4e00-\u9fa5]{2,4})\s+(\S.*)$',
  ).firstMatch(segment);
  if (nameMatch == null) return null;
  final teacher = nameMatch.group(1)!;
  final rest = nameMatch.group(2)!.trim();
  final openMatch = RegExp(r'[（(]').firstMatch(rest);
  if (openMatch == null) return null;
  final closeMatch = RegExp(r'[)）]').firstMatch(rest.substring(openMatch.end));
  if (closeMatch == null) return null;
  final course = rest.substring(0, openMatch.start).trim();
  if (course.isEmpty) return null;
  var inner = rest.substring(openMatch.end, openMatch.end + closeMatch.start);
  final after = rest.substring(openMatch.end + closeMatch.end).trim();

  String? segmentWeeks;
  final innerWeek = _popupNumbering.firstMatch(inner.trim());
  if (innerWeek != null && _looksLikeWeekSpec(innerWeek.group(1)!)) {
    segmentWeeks = innerWeek.group(1);
    inner = inner.trim().substring(innerWeek.end);
  }
  final weeks = segmentWeeks ?? leadingWeeks;
  if (weeks == null) return null;
  final location = [
    inner.trim(),
    after,
  ].where((value) => value.isNotEmpty).join(' ');

  return TongjiTimetableRecord(
    text: '$teacher $course [$weeks] $location'.trim(),
    weekday: weekday,
    startPeriod: chunk.start,
    endPeriod: chunk.end,
  );
}

/// 方括号里是不是周次写法，而不是课程代码之类。
///
/// 与页面上抓取脚本的判定保持一致：必须含数字，且只由数字、分隔符与
/// 「第单双周」等字样组成。
bool _looksLikeWeekSpec(String inner) =>
    RegExp(r'\d').hasMatch(inner) &&
    RegExp(r'^[\d\s,，、\-—~～至第单双周()（）]+$').hasMatch(inner);

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
