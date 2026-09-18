import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/import/course_import.dart';
import 'package:offline_course_schedule/import/tongji_timetable_import.dart';

void main() {
  const parser = TongjiTimetableImportParser();

  test('解析同济课表中的教师、课程、周次和地点', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '姚勤(95017) 高等数学B(I) (CMS122103) [1-16] 北129',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '高等数学B(I)');
    expect(row.cells[ImportField.teacher]!.value, '姚勤');
    expect(row.cells[ImportField.location]!.value, '北129');
    expect(row.cells[ImportField.weekday]!.value, 1);
    final periods = row.cells[ImportField.periods]!.value! as PeriodRange;
    expect((periods.start, periods.end), (1, 2));
  });

  test('解析多位教师和不连续周次', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text:
            '徐象繁(13517),王庆国(18131),赫丽(00770) 大学物理实验A1(I) '
            '(PSE123503) [1, 3, 5, 7, 9, 11, 13, 15] 物理馆2-4楼',
        weekday: 4,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.teacher]!.value, '徐象繁、王庆国、赫丽');
    final result = parser.courseImportParser.buildCourses(preview);
    expect(
      result.courses.single.sessions.single.weekRule.type,
      WeekType.custom,
    );
    expect(result.courses.single.sessions.single.weekRule.includes(9), isTrue);
    expect(
      result.courses.single.sessions.single.weekRule.includes(10),
      isFalse,
    );
  });

  test('网页字段不完整时保留原文并标黄', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '网站改版后的未知内容',
        weekday: 3,
        startPeriod: 5,
        endPeriod: 6,
      ),
    ]);

    expect(preview.rows.single.isValid, isFalse);
    expect(
      preview.rows.single.cells[ImportField.weeks]!.needsAttention,
      isTrue,
    );
  });

  test('网页课程固定按周一到周日、同一天从早到晚排列', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '周三老师(3) 周三晚课 (ABC103) [1-16] C303',
        weekday: 3,
        startPeriod: 7,
        endPeriod: 8,
      ),
      TongjiTimetableRecord(
        text: '周一老师(1) 周一课程 (ABC101) [1-16] A101',
        weekday: 1,
        startPeriod: 5,
        endPeriod: 6,
      ),
      TongjiTimetableRecord(
        text: '周三老师(2) 周三早课 (ABC102) [1-16] B202',
        weekday: 3,
        startPeriod: 1,
        endPeriod: 2,
      ),
    ]);

    expect(
      preview.rows
          .map((row) => row.cells[ImportField.courseName]!.value)
          .toList(),
      ['周一课程', '周三早课', '周三晚课'],
    );
  });

  test('解析研究生课表没有课程代码的卡片', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '周舒威 高等地下结构([1-16]彰武北大楼 209) 四平路校区',
        weekday: 1,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '高等地下结构');
    expect(row.cells[ImportField.teacher]!.value, '周舒威');
    expect(row.cells[ImportField.location]!.value, '彰武北大楼 209 四平路校区');
    final periods = row.cells[ImportField.periods]!.value! as PeriodRange;
    expect((periods.start, periods.end), (3, 4));
  });

  test('研究生课表的不连续周次按集合保留', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '万立明 中国马克思主义与当代 '
            '([2, 4, 6, 8, 10, 12, 14, 16]彰武南大楼 117) 四平路校区',
        weekday: 3,
        startPeriod: 5,
        endPeriod: 8,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '中国马克思主义与当代');
    expect(row.cells[ImportField.teacher]!.value, '万立明');
    final rule = parser
        .courseImportParser
        .buildCourses(preview)
        .courses
        .single
        .sessions
        .single
        .weekRule;
    expect(rule.type, WeekType.custom);
    expect(rule.includes(2), isTrue);
    expect(rule.includes(3), isFalse);
  });

  test('研究生课表只有校区时地点保留校区', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '钱杨 学术英语写作III([4, 6, 8, 10, 12, 14]) 四平路校区，',
        weekday: 3,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '学术英语写作III');
    expect(row.cells[ImportField.teacher]!.value, '钱杨');
    expect(row.cells[ImportField.location]!.value, '四平路校区');
  });

  test('课程名以括号数字结尾时不会被当成教师工号', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '冯辉(93761) 体育(1)(DPE110120) [1-16] 综合训练馆羽毛球馆',
        weekday: 1,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '体育(1)');
    expect(row.cells[ImportField.teacher]!.value, '冯辉');
    expect(row.cells[ImportField.location]!.value, '综合训练馆羽毛球馆');
  });

  test('课程名以括号数字结尾且与代码之间有空格', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '孙毅(22161) 形势与政策(1) (CMA111629) [7-10] 南301',
        weekday: 2,
        startPeriod: 7,
        endPeriod: 10,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '形势与政策(1)');
    expect(row.cells[ImportField.teacher]!.value, '孙毅');
  });

  test('多位教师仍按逗号分隔完整识别', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '徐象繁(13517),王庆国(18131),赫丽(00770) 大学物理实验A1(I) '
            '(PSE123503) [1, 3, 5] 物理馆2-4楼',
        weekday: 4,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.teacher]!.value, '徐象繁、王庆国、赫丽');
    expect(row.cells[ImportField.courseName]!.value, '大学物理实验A1(I)');
  });

  test('空格分隔的多位教师也能识别', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '冯辉(93761) 姚勤(95017) 高等数学B(I)(CMS122103) [1-16] 北129',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.teacher]!.value, '冯辉、姚勤');
    expect(row.cells[ImportField.courseName]!.value, '高等数学B(I)');
  });

  // —— 弹窗（「排课信息」）路径 ——
  // 文本取自用户提供的真实截图，逐字照抄。
  // 价值：星期来自标题、节次与周次来自每行，不再需要用卡片位置去推算。
  group('排课信息弹窗', () {
    test('周四弹窗：同一门课按周次切成多行，不同老师各成一行', () {
      final records = parseTongjiPopupText(_thursdayPopup);

      expect(records.length, 7);
      expect(records.every((r) => r.weekday == 4), isTrue);
      expect(records.every((r) => r.startPeriod == 5 && r.endPeriod == 6), isTrue);

      final preview = parser.parse(records);
      expect(preview.rows.length, 7);
      expect(preview.rows.every((row) => row.isValid), isTrue);

      // 同一门课：名称一致
      expect(
        preview.rows
            .map((row) => row.cells[ImportField.courseName]!.value)
            .toSet(),
        {'专业导论(理科试验班)'},
      );
      // parse() 会按周几/节次/文本排序，所以按周次查找而不是用下标。
      String teacherOfWeek(String weeks) => preview.rows
          .firstWhere((row) => row.cells[ImportField.weeks]!.raw == weeks)
          .cells[ImportField.teacher]!
          .value! as String;
      expect(teacherOfWeek('5周'), '刘梅川');
      expect(teacherOfWeek('9-16周'), '邱军、刘宁');
      expect(teacherOfWeek('3, 8周'), '刘宁');
      expect(teacherOfWeek('4周'), '祝捷');
      // 每行地点都保留
      expect(
        preview.rows
            .map((row) => row.cells[ImportField.location]!.value)
            .toSet(),
        {'北116'},
      );
    });

    test('周一弹窗：同一格两门课、不同老师与不同周次规则', () {
      final records = parseTongjiPopupText(_mondayPopup);

      expect(records.length, 2);
      expect(records.every((r) => r.weekday == 1), isTrue);

      final preview = parser.parse(records);
      expect(preview.rows.every((row) => row.isValid), isTrue);
      final byName = {
        for (final row in preview.rows)
          row.cells[ImportField.courseName]!.value!: row,
      };
      expect(byName.keys.toSet(), {'普通化学实验A2', '高等代数与解析几何(I)'});
      expect(byName['普通化学实验A2']!.cells[ImportField.teacher]!.value, '李汶军');
      expect(
        byName['高等代数与解析几何(I)']!.cells[ImportField.teacher]!.value,
        '孙娟娟',
      );
      expect(
        byName['普通化学实验A2']!.cells[ImportField.location]!.value,
        '工程试验馆303、307',
      );

      // 双周与自定义周次都要落成正确的规则，而不是被当成每周。
      final result = parser.courseImportParser.buildCourses(preview);
      final courses = {
        for (final course in result.courses) course.name: course,
      };
      final chemistry = courses['普通化学实验A2']!;
      final algebra = courses['高等代数与解析几何(I)']!;
      expect(chemistry.sessions.single.weekRule.type, WeekType.even);
      expect(chemistry.sessions.single.weekRule.includes(2), isTrue);
      expect(chemistry.sessions.single.weekRule.includes(3), isFalse);
      expect(algebra.sessions.single.weekRule.type, WeekType.custom);
      expect(algebra.sessions.single.weekRule.includes(15), isTrue);
      expect(algebra.sessions.single.weekRule.includes(14), isFalse);
    });

    test('标题没有星期时返回空，交由调用方回退', () {
      expect(parseTongjiPopupText('刘梅川(06059) 专业导论 [5] 北116'), isEmpty);
    });

    test('内容不是排课信息时返回空，不会误判', () {
      expect(parseTongjiPopupText(''), isEmpty);
      expect(parseTongjiPopupText('[星期四] 排课信息\n今天没有安排'), isEmpty);
      // 缺课程代码、缺教师工号的行都必须跳过，避免写入错位数据。
      expect(
        parseTongjiPopupText('[星期五] 排课信息\n[1-2节] [1-16] 某门课 某老师 某地'),
        isEmpty,
      );
    });
  });

  // —— 弹窗与卡片的按格合并 ——
  // 弹窗可能只成功一部分，直接采用会让未成功的格子整格丢失，
  // 反而比只读卡片更糟。因此按「格」替换而不是整体替换。
  group('弹窗与卡片按格合并', () {
    TongjiTimetableRecord record(int weekday, int start, int end, String name) =>
        TongjiTimetableRecord(
          text: '老师(1) $name (ABC101) [1-16] 某地',
          weekday: weekday,
          startPeriod: start,
          endPeriod: end,
        );

    test('弹窗全部失败时行为与从前完全一致', () {
      final cards = [record(1, 1, 2, '甲课'), record(3, 5, 6, '乙课')];
      expect(mergePopupWithCards(popup: const [], cards: cards), cards);
    });

    test('弹窗成功的格子只保留弹窗结果，其余格保留卡片结果', () {
      final cards = [record(1, 1, 2, '甲课'), record(3, 5, 6, '乙课')];
      // 只有周三那格读到了弹窗，且被拆成两条。
      final merged = mergePopupWithCards(
        popup: [record(3, 5, 6, '乙课一班'), record(3, 5, 6, '乙课二班')],
        cards: cards,
      );

      expect(merged.length, 3);
      expect(merged.where((r) => r.weekday == 1).length, 1);
      expect(merged.where((r) => r.weekday == 3).length, 2);
    });

    test('节次范围有交集即视为同一格', () {
      final cards = [record(2, 5, 8, '合并格课程')];
      // 弹窗按 5-6 节给出，与卡片的 5-8 节有交集，属同一格。
      final merged = mergePopupWithCards(
        popup: [record(2, 5, 6, '拆分后的课')],
        cards: cards,
      );
      expect(merged.length, 1);
      expect(merged.single.text.contains('拆分后的课'), isTrue);
    });

    test('不同星期的课程不会被误判成同一格', () {
      final cards = [record(1, 1, 2, '周一课'), record(2, 1, 2, '周二课')];
      final merged = mergePopupWithCards(
        popup: [record(1, 1, 2, '周一课新版')],
        cards: cards,
      );

      expect(merged.length, 2);
      expect(merged.any((r) => r.text.contains('周一课新版')), isTrue);
      expect(merged.any((r) => r.text.contains('周二课')), isTrue);
    });

    test('卡片为空时直接用弹窗结果', () {
      final popupRows = [record(1, 1, 2, '甲课')];
      expect(mergePopupWithCards(popup: popupRows, cards: const []), popupRows);
    });
  });

  // —— 重复录入只保留一条 ——
  group('重复记录去重', () {
    TongjiTimetableRecord record(
      int weekday,
      int start,
      int end,
      String text,
    ) => TongjiTimetableRecord(
      text: text,
      weekday: weekday,
      startPeriod: start,
      endPeriod: end,
    );

    test('完全相同的记录只保留一条', () {
      final same = record(4, 5, 6, '刘梅川(06059) 专业导论 [5] 北116');
      final result = dedupeRecords([same, same, same]);
      expect(result.length, 1);
    });

    test('同一门课不同周次不会被误删（原文不同）', () {
      final result = dedupeRecords([
        record(4, 5, 6, '刘梅川(06059) 专业导论 [5] 北116'),
        record(4, 5, 6, '邱军(06122) 专业导论 [1-2] 北116'),
        record(4, 5, 6, '邱军(06122),刘宁(21019) 专业导论 [9-16] 北116'),
      ]);
      expect(result.length, 3);
    });

    test('同一天不同节次的相同内容不会被误删', () {
      final result = dedupeRecords([
        record(1, 1, 2, '某课 [1-16] 某地'),
        record(1, 5, 6, '某课 [1-16] 某地'),
      ]);
      expect(result.length, 2);
    });

    test('不同星期的相同内容不会被误删', () {
      final result = dedupeRecords([
        record(1, 1, 2, '某课 [1-16] 某地'),
        record(3, 1, 2, '某课 [1-16] 某地'),
      ]);
      expect(result.length, 2);
    });

    test('合并结果里也做了去重', () {
      final duplicated = record(2, 3, 4, '重复课 [1-16] 某地');
      final merged = mergePopupWithCards(
        popup: [duplicated, duplicated],
        cards: const [],
      );
      expect(merged.length, 1);
    });
  });
}

// 下面两段取自用户提供的真实截图，逐字照抄（含空格与标点）。
const _thursdayPopup = '''
[星期四] 排课信息
[5-6节] [5] 专业导论(理科试验班)(PSE1901) 刘梅川(06059) 北116
[5-6节] [1-2] 专业导论(理科试验班)(PSE1901) 邱军(06122) 北116
[5-6节] [9-16] 专业导论(理科试验班)(PSE1901) 邱军(06122),刘宁(21019) 北116
[5-6节] [6] 专业导论(理科试验班)(PSE1901) 李忠华(08097) 北116
[5-6节] [7] 专业导论(理科试验班)(PSE1901) 季福武(08115) 北116
[5-6节] [3, 8] 专业导论(理科试验班)(PSE1901) 刘宁(21019) 北116
[5-6节] [4] 专业导论(理科试验班)(PSE1901) 祝捷(21134) 北116
''';

const _mondayPopup = '''
[星期一] 排课信息
[7-8节] [2-16双] 普通化学实验A2(CSE1216) 李汶军(07169) 工程试验馆303、307
[7-8节] [1, 3, 5, 7, 9, 11, 13, 15] 高等代数与解析几何(I)(CMS1229) 孙娟娟(12213) 南129
''';

