// 以下排课样例使用虚构姓名、编号、课程和地点，仅用于解析回归。
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/import/course_import.dart';
import 'package:offline_course_schedule/import/tongji_timetable_import.dart';

void main() {
  const parser = TongjiTimetableImportParser();

  test('解析同济课表中的教师、课程、周次和地点', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '示甲壬(73895) 示例课程甲甲B(I) (DEMO10107) [1-16] 演示B129',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '示例课程甲甲B(I)');
    expect(row.cells[ImportField.teacher]!.value, '示甲壬');
    expect(row.cells[ImportField.location]!.value, '演示B129');
    expect(row.cells[ImportField.weekday]!.value, 1);
    final periods = row.cells[ImportField.periods]!.value! as PeriodRange;
    expect((periods.start, periods.end), (1, 2));
  });

  test('解析多位教师和不连续周次', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text:
            '示丙甲(91395),示丁乙(96919),示丁癸(88558) 示例课程甲乙A1(I) '
            '(DEMO10104) [1, 3, 5, 7, 9, 11, 13, 15] 示例楼己2-4楼',
        weekday: 4,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.teacher]!.value, '示丙甲、示丁乙、示丁癸');
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
        text: '示甲庚 示例课程乙丙([1-16]示例楼甲 209) 示例楼丙',
        weekday: 1,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '示例课程乙丙');
    expect(row.cells[ImportField.teacher]!.value, '示甲庚');
    expect(row.cells[ImportField.location]!.value, '示例楼甲 209 示例楼丙');
    final periods = row.cells[ImportField.periods]!.value! as PeriodRange;
    expect((periods.start, periods.end), (3, 4));
  });

  test('研究生课表的不连续周次按集合保留', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '示甲甲 示例课程乙甲 '
            '([2, 4, 6, 8, 10, 12, 14, 16]示例楼乙 117) 示例楼丙',
        weekday: 3,
        startPeriod: 5,
        endPeriod: 8,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '示例课程乙甲');
    expect(row.cells[ImportField.teacher]!.value, '示甲甲');
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
        text: '示戊丁 示例课程乙乙III([4, 6, 8, 10, 12, 14]) 示例楼丙，',
        weekday: 3,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '示例课程乙乙III');
    expect(row.cells[ImportField.teacher]!.value, '示戊丁');
    expect(row.cells[ImportField.location]!.value, '示例楼丙');
  });

  test('课程名以括号数字结尾时不会被当成教师工号', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '示甲丙(71549) 示例课程甲壬(1)(DEMO10102) [1-16] 示例楼戊',
        weekday: 1,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '示例课程甲壬(1)');
    expect(row.cells[ImportField.teacher]!.value, '示甲丙');
    expect(row.cells[ImportField.location]!.value, '示例楼戊');
  });

  test('课程名以括号数字结尾且与代码之间有空格', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '示乙乙(00949) 示例课程甲癸(1) (DEMO10097) [7-10] 演示A301',
        weekday: 2,
        startPeriod: 7,
        endPeriod: 10,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.courseName]!.value, '示例课程甲癸(1)');
    expect(row.cells[ImportField.teacher]!.value, '示乙乙');
  });

  test('多位教师仍按逗号分隔完整识别', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '示丙甲(91395),示丁乙(96919),示丁癸(88558) 示例课程甲乙A1(I) '
            '(DEMO10104) [1, 3, 5] 示例楼己2-4楼',
        weekday: 4,
        startPeriod: 3,
        endPeriod: 4,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.teacher]!.value, '示丙甲、示丁乙、示丁癸');
    expect(row.cells[ImportField.courseName]!.value, '示例课程甲乙A1(I)');
  });

  test('空格分隔的多位教师也能识别', () {
    final preview = parser.parse(const [
      TongjiTimetableRecord(
        text: '示甲丙(71549) 示甲壬(73895) 示例课程甲甲B(I)(DEMO10107) [1-16] 演示B129',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
      ),
    ]);

    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.cells[ImportField.teacher]!.value, '示甲丙、示甲壬');
    expect(row.cells[ImportField.courseName]!.value, '示例课程甲甲B(I)');
  });

  // —— 弹窗（「排课信息」）路径 ——
  // 以下为虚构回归样例，保留原有格式边界。
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
        {'示例课程甲辛(示例课程丙庚)'},
      );
      // parse() 会按周几/节次/文本排序，所以按周次查找而不是用下标。
      String teacherOfWeek(String weeks) => preview.rows
          .firstWhere((row) => row.cells[ImportField.weeks]!.raw == weeks)
          .cells[ImportField.teacher]!
          .value! as String;
      expect(teacherOfWeek('5周'), '示甲戊');
      expect(teacherOfWeek('9-16周'), '示戊甲、示甲丁');
      expect(teacherOfWeek('3, 8周'), '示甲丁');
      expect(teacherOfWeek('4周'), '示丁己');
      // 每行地点都保留
      expect(
        preview.rows
            .map((row) => row.cells[ImportField.location]!.value)
            .toSet(),
        {'演示B116'},
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
      expect(byName.keys.toSet(), {'示例课程甲戊A2', '示例课程甲丙(I)'});
      expect(byName['示例课程甲戊A2']!.cells[ImportField.teacher]!.value, '示丙庚');
      expect(
        byName['示例课程甲丙(I)']!.cells[ImportField.teacher]!.value,
        '示乙甲',
      );
      expect(
        byName['示例课程甲戊A2']!.cells[ImportField.location]!.value,
        '示例楼辛303、307',
      );

      // 双周与自定义周次都要落成正确的规则，而不是被当成每周。
      final result = parser.courseImportParser.buildCourses(preview);
      final courses = {
        for (final course in result.courses) course.name: course,
      };
      final chemistry = courses['示例课程甲戊A2']!;
      final algebra = courses['示例课程甲丙(I)']!;
      expect(chemistry.sessions.single.weekRule.type, WeekType.even);
      expect(chemistry.sessions.single.weekRule.includes(2), isTrue);
      expect(chemistry.sessions.single.weekRule.includes(3), isFalse);
      expect(algebra.sessions.single.weekRule.type, WeekType.custom);
      expect(algebra.sessions.single.weekRule.includes(15), isTrue);
      expect(algebra.sessions.single.weekRule.includes(14), isFalse);
    });

    test('标题没有星期时返回空，交由调用方回退', () {
      expect(parseTongjiPopupText('示甲戊(84837) 示例课程甲辛 [5] 演示B116'), isEmpty);
    });

    // 浮层宽度有限，长条目会折行；innerText 按渲染结果换行。
    // 曾被逐行解析直接丢掉续行，导致整条记录消失、那一格少课。
    test('条目折行时接回同一条，教师工号与地点不被截断', () {
      final records = parseTongjiPopupText(_wrappedWednesdayPopup);

      // 折行的那条不能丢。
      expect(records.length, 2);
      final byTeacher = {
        for (final record in records) record.text.split(' ').first: record,
      };
      expect(byTeacher.keys.toSet(), {'示乙壬(83917)', '示戊辛(87996)'});
      // 工号跨行断开（8799 / 8)）必须拼回 87996，地点 演示B301 也不能丢。
      expect(byTeacher['示戊辛(87996)']!.text, contains('演示B301'));

      final preview = parser.parse(records);
      expect(preview.rows.length, 2);
      expect(preview.rows.every((row) => row.isValid), isTrue);
      expect(
        preview.rows.map((row) => row.cells[ImportField.teacher]!.value).toSet(),
        {'示乙壬', '示戊辛'},
      );
    });

    test('地点折行时拼回完整地点，多条同课合并成一节课', () {
      final records = parseTongjiPopupText(_wrappedThursdayPopup);

      // 三段周次、三位老师，都是周四 5-6 节，属同一节课。
      expect(records.length, 3);
      expect(records.every((r) => r.weekday == 4), isTrue);
      expect(records.every((r) => r.startPeriod == 5 && r.endPeriod == 6), isTrue);

      final result = parser.courseImportParser.buildCourses(
        parser.parse(records),
      );
      expect(result.courses, hasLength(1), reason: '同一门课不应被拆成多门');
      final course = result.courses.single;
      expect(course.name, '示例课程甲庚');
      expect(course.sessions, hasLength(1), reason: '同节次应按周次并成一节课');
      final session = course.sessions.single;
      expect((session.weekday, session.startPeriod, session.endPeriod), (4, 5, 6));
      // 折行的 示例楼庚 / 机房 必须拼回完整地点。
      expect(session.location, '示例楼庚机房');
      // 周次并集应为 1-12 周（[10] + [3-9] + [1-2, 11-12]）。
      for (var week = 1; week <= 12; week++) {
        expect(session.weekRule.includes(week), isTrue, reason: '第 $week 周缺失');
      }
      expect(session.weekRule.includes(13), isFalse);
      // 三位老师都要保留（顺序取决于分组遍历，不固定顺序）。
      expect(course.teacher.split('、').toSet(), {'示乙癸', '示乙己', '示丙乙'});
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

  // —— 同一格里的多条排课 ——
  // 浮层是 innerText，换行由渲染决定：同一格的多条课**可能被拼到同一行**，
  // 也可能只读到其中一条。这些都被真实截图复现过。
  group('同一格多条排课', () {
    test('虚构排课内容（两行两条）作为对照基准', () {
      final result = parser.courseImportParser.buildCourses(
        parser.parse(parseTongjiPopupText(_plainWedPopup)),
      );
      expect(
        result.courses.map((course) => course.name).toSet(),
        {'示例课程甲丁A', '示例课程甲甲B(I)'},
      );
    });

    // 研究生格式：没有课程代码、没有教师工号，一行里用逗号并排两段周次与地点。
    // 曾被整行跳过，这一格就整块消失。
    test('研究生格式（无代码无工号）也能读出，一行两段各取自己的周次', () {
      final records = parseTongjiPopupText(_graduateWedPopup);

      expect(records.length, 2);
      expect(records.every((r) => r.weekday == 3), isTrue);
      expect(records.every((r) => r.startPeriod == 3 && r.endPeriod == 4), isTrue);

      final result = parser.courseImportParser.buildCourses(parser.parse(records));
      expect(result.courses, hasLength(1), reason: '同一节课按周次拆段，仍是一门课');
      final course = result.courses.single;
      expect(course.name, '示例课程乙乙III');
      expect(course.teacher, '示戊丁');
      expect(course.sessions, hasLength(1), reason: '同节次应并成一节课');

      final session = course.sessions.single;
      // 两段周次并起来是 1-16 周，中间没有断档。
      for (var week = 1; week <= 16; week++) {
        expect(session.weekRule.includes(week), isTrue, reason: '第 $week 周缺失');
      }
      expect(session.weekRule.includes(17), isFalse);
      // 地点详略不同（一段只写校区、一段写成教室），应取更具体的那条。
      expect(session.location, '示例楼甲 409 示例楼丙');
    });

    // 两条课挤在同一行、中间没有换行。曾把第二条整段当成第一条的「地点」吞掉。
    test('两条挤在同一行时按 [节次] 切开，不吞进上一条的地点', () {
      final records = parseTongjiPopupText(_sameLineWedPopup);

      expect(records.length, 2, reason: '两条都要读到');
      final result = parser.courseImportParser.buildCourses(parser.parse(records));
      expect(
        result.courses.map((course) => course.name).toSet(),
        {'示例课程甲丁A', '示例课程甲甲B(I)'},
      );
      // 地点必须是干净的地点，不能混入下一条的节次与课程名。
      for (final course in result.courses) {
        expect(course.sessions.single.location, isNot(contains('节]')));
        expect(course.sessions.single.location, isNot(contains('(CMS')));
      }
    });

    // 条目带 `1.` `2.` 序号，且部分被拼到同一行。曾只读到没有序号的那一条。
    test('带序号的多条都能读到，序号不会被并进上一条', () {
      final records = parseTongjiPopupText(_numberedWedPopup);

      expect(records.length, 4);
      expect(
        records.every((r) => r.weekday == 3 && r.startPeriod == 3 && r.endPeriod == 4),
        isTrue,
      );
      // 序号不能残留在正文里。
      for (final record in records) {
        expect(record.text, isNot(matches(RegExp(r'\d+\s*\.'))));
      }

      final result = parser.courseImportParser.buildCourses(parser.parse(records));
      expect(
        result.courses.map((course) => course.name).toSet(),
        {'示例课程乙乙III', '示例课程甲丁A', '示例课程甲甲B(I)'},
      );
    });

    // 同一门课按周次拆成三段、三位老师。三段周次并起来是 1-12 周。
    // 页面侧曾因「一格文本里出现多个 [周次] 就整格拒绝」而完全读不到这一格，
    // 这里同时钉住「文本拿到之后能正确解析」。
    test('同课三段周次三位老师合并成一节课，周次无断档', () {
      final records = parseTongjiPopupText(_cadPopup);
      expect(records.length, 3);
      expect(
        records.every((r) => r.weekday == 4 && r.startPeriod == 5 && r.endPeriod == 6),
        isTrue,
      );

      final result = parser.courseImportParser.buildCourses(parser.parse(records));
      expect(result.courses, hasLength(1));
      final course = result.courses.single;
      expect(course.name, '示例课程甲庚');
      expect(course.sessions, hasLength(1));
      expect(course.teacher.split('、').toSet(), {'示乙癸', '示乙己', '示丙乙'});

      final session = course.sessions.single;
      expect(session.location, '示例楼庚机房');
      for (var week = 1; week <= 12; week++) {
        expect(session.weekRule.includes(week), isTrue, reason: '第 $week 周缺失');
      }
      expect(session.weekRule.includes(13), isFalse);
    });

    test('同课三段被拼到同一行时也能全部解析', () {
      final result = parser.courseImportParser.buildCourses(
        parser.parse(parseTongjiPopupText(_cadSameLinePopup)),
      );
      expect(result.courses, hasLength(1));
      final session = result.courses.single.sessions.single;
      expect(session.location, '示例楼庚机房');
      expect(session.weekRule.includes(12), isTrue);
      expect(session.weekRule.includes(13), isFalse);
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
      final same = record(4, 5, 6, '示甲戊(84837) 示例课程甲辛 [5] 演示B116');
      final result = dedupeRecords([same, same, same]);
      expect(result.length, 1);
    });

    test('同一门课不同周次不会被误删（原文不同）', () {
      final result = dedupeRecords([
        record(4, 5, 6, '示甲戊(84837) 示例课程甲辛 [5] 演示B116'),
        record(4, 5, 6, '示戊甲(84900) 示例课程甲辛 [1-2] 演示B116'),
        record(4, 5, 6, '示戊甲(84900),示甲丁(09897) 示例课程甲辛 [9-16] 演示B116'),
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

// 下面两段为虚构的解析回归数据，保留空格与标点结构。
const _thursdayPopup = '''
[星期四] 排课信息
[5-6节] [5] 示例课程甲辛(示例课程丙庚)(DEMO10093) 示甲戊(84837) 演示B116
[5-6节] [1-2] 示例课程甲辛(示例课程丙庚)(DEMO10093) 示戊甲(84900) 演示B116
[5-6节] [9-16] 示例课程甲辛(示例课程丙庚)(DEMO10093) 示戊甲(84900),示甲丁(09897) 演示B116
[5-6节] [6] 示例课程甲辛(示例课程丙庚)(DEMO10093) 示丙己(86875) 演示B116
[5-6节] [7] 示例课程甲辛(示例课程丙庚)(DEMO10093) 示乙丁(86993) 演示B116
[5-6节] [3, 8] 示例课程甲辛(示例课程丙庚)(DEMO10093) 示甲丁(09897) 演示B116
[5-6节] [4] 示例课程甲辛(示例课程丙庚)(DEMO10093) 示丁己(09912) 演示B116
''';

const _mondayPopup = '''
[星期一] 排课信息
[7-8节] [2-16双] 示例课程甲戊A2(DEMO10098) 示丙庚(85947) 示例楼辛303、307
[7-8节] [1, 3, 5, 7, 9, 11, 13, 15] 示例课程甲丙(I)(DEMO10092) 示乙甲(90091) 演示A129
''';

// 虚构回归数据，**保留折行**（工号被从中间截断）。
const _wrappedWednesdayPopup = '''
[星期三] 排课信息
[3-4节] [2-16双] 示例课程甲丁A(DEMO10108) 示乙壬(83917) 演示A201
[3-4节] [1, 3, 5, 7, 9, 11, 13, 15] 示例课程甲甲B(I)(DEMO10096) 示戊辛(8799
6) 演示B301
''';

// 虚构回归数据，**保留折行**（地点被断成 示例楼庚 / 机房）。
const _wrappedThursdayPopup = '''
[星期四] 排课信息
[5-6节] [10] 示例课程甲庚(DEMO10113) 示乙癸(85974) 示例楼庚机房
[5-6节] [3-9] 示例课程甲庚(DEMO10113) 示乙己(97411) 示例楼庚
机房
[5-6节] [1-2, 11-12] 示例课程甲庚(DEMO10113) 示丙乙(09818) 示例楼庚机房
''';

// 虚构回归数据。研究生课表：没有课程代码、没有教师工号，
// 且**同一行里用逗号并排写着两段周次与地点**（一段只写校区，
// 一段写成教室），两者其实是同一节课按周次拆开的两段。
const _graduateWedPopup = '''
[星期三] 排课信息
[3-4节] [4, 6, 8, 10, 12, 14] 示戊丁 示例课程乙乙III( ) 示例楼丙, 示戊丁 示例课程乙乙III([1-3, 5, 7, 9, 11, 13, 15-16]示例楼甲 409) 示例楼丙''';

// 虚构回归数据：两条排课挤在同一行，中间没有换行。
// 曾经把第二条整段当成第一条的「地点」吞掉。
const _sameLineWedPopup = '''
[星期三] 排课信息
[3-4节] [1, 3, 5, 7, 9, 11, 13, 15] 示例课程甲丁A(DEMO10108) 示乙壬(83917) 演示A201 [3-4节] [2-16双] 示例课程甲甲B(I)(DEMO10096) 示戊癸(77511) 演示B301''';

// 虚构回归数据：每条前面带 `1.`、`2.` 序号，且部分条目被拼到同一行。
// 曾经只读到没有序号的那一条。
const _numberedWedPopup = '''
[星期三] 排课信息
1.[3-4节] [4, 6, 8, 10, 12, 14] 示戊丁 示例课程乙乙III( ) 示例楼丙, 示戊丁 示例课程乙乙III([1-3, 5, 7, 9, 11, 13, 15-16]示例楼甲 409) 示例楼丙      2.[3-4节] [1, 3, 5, 7, 9, 11, 13, 15] 示例课程甲丁A(DEMO10108) 示乙壬(83917) 演示A201
[3-4节] [2-16双] 示例课程甲甲B(I)(DEMO10096) 示戊癸(77511) 演示B301''';

// 虚构的网页排课内容（本科格式，两行两条），作为对照基准。
const _plainWedPopup = '''
[星期三] 排课信息
[3-4节] [1, 3, 5, 7, 9, 11, 13, 15] 示例课程甲丁A(DEMO10108) 示乙壬(83917) 演示A201
[3-4节] [2-16双] 示例课程甲甲B(I)(DEMO10096) 示戊癸(77511) 演示B301''';

// 虚构回归样例：周四 5-6 节同一门课按周次拆成三段、三位老师。
const _cadPopup = '''
[星期四] 排课信息
[5-6节] [10] 示例课程甲庚(DEMO10113) 示乙癸(85974) 示例楼庚机房
[5-6节] [3-9] 示例课程甲庚(DEMO10113) 示乙己(97411) 示例楼庚机房
[5-6节] [1-2, 11-12] 示例课程甲庚(DEMO10113) 示丙乙(09818) 示例楼庚机房''';

// 同上，但三条被拼到同一行（浮层偶尔这样返回）。
const _cadSameLinePopup = '''
[星期四] 排课信息
[5-6节] [10] 示例课程甲庚(DEMO10113) 示乙癸(85974) 示例楼庚机房 [5-6节] [3-9] 示例课程甲庚(DEMO10113) 示乙己(97411) 示例楼庚机房 [5-6节] [1-2, 11-12] 示例课程甲庚(DEMO10113) 示丙乙(09818) 示例楼庚机房''';

