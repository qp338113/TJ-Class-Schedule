import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';

void main() {
  testWidgets('今日视图同时显示课程与备忘录，并按开始时间排序', (tester) async {
    final fixture = _fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    expect(find.text('交作业'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    // 备忘录带视觉标记；副标题沿用“地点 · 教师”，备忘录教师为空会自动省略。
    expect(find.byIcon(Icons.event_note_outlined), findsOneWidget);
    expect(find.text('图书馆'), findsOneWidget);
    expect(find.text('A202 · 张老师'), findsOneWidget);
    // 备忘录是第 1 节（更早），必须排在课程之上。
    expect(
      tester.getTopLeft(find.text('交作业')).dy,
      lessThan(tester.getTopLeft(find.text('高等数学')).dy),
    );
  });

  testWidgets('本周视图同一天同时显示课程与备忘录', (tester) async {
    final fixture = _fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();

    expect(find.text('交作业'), findsOneWidget);
    expect(find.text('图书馆'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('A202 · 张老师'), findsOneWidget);
  });

  testWidgets('长按备忘录进入备忘录编辑态，长按课程进入课程编辑态', (tester) async {
    _useTallSurface(tester);
    final fixture = _fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('交作业'));
    await tester.pumpAndSettle();
    expect(find.text('修改备忘录'), findsOneWidget);
    expect(find.text('保存备忘录'), findsOneWidget);
    expect(find.text('删除这条备忘录'), findsOneWidget);
    expect(find.text('修改课程'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.longPress(find.text('高等数学'));
    await tester.pumpAndSettle();
    expect(find.text('修改课程'), findsOneWidget);
    expect(find.text('保存课程'), findsOneWidget);
    expect(find.text('修改备忘录'), findsNothing);
  });

  testWidgets('编辑备忘录后调用 updateMemo，保留原 id', (tester) async {
    _useTallSurface(tester);
    final fixture = _fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('交作业'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '交实验报告');
    await tester.tap(find.text('保存备忘录'));
    await tester.pumpAndSettle();

    expect(find.text('保存备忘录'), findsNothing);
    final updated = fixture.controller.updatedMemos.single;
    expect(updated.id, 'memo-1');
    expect(updated.title, '交实验报告');
    expect(updated.weekday, fixture.today.weekday);
    expect(updated.location, '图书馆');
  });

  testWidgets('备忘录用调色板按钮改色走 changeMemoColor', (tester) async {
    final fixture = _fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    final memoCard = find.ancestor(
      of: find.text('交作业'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(
        of: memoCard,
        matching: find.byIcon(Icons.palette_outlined),
      ),
    );
    await tester.pumpAndSettle();
    // 色板第三个颜色与 fixture 里备忘录的初始颜色不同，能确认确实写回了。
    await tester.tap(find.byType(CircleAvatar).at(2));
    await tester.pumpAndSettle();

    expect(fixture.controller.changedMemoColors['memo-1'], 0xFFD19A8A);
  });

  testWidgets('删除备忘录需要二次确认并调用 deleteMemo', (tester) async {
    _useTallSurface(tester);
    final fixture = _fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('交作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除这条备忘录'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条备忘录？'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(fixture.controller.deletedMemos, ['memo-1']);
  });

  testWidgets('添加入口可切到备忘录，校验标题与结束时刻并保存', (tester) async {
    _useTallSurface(tester);
    final fixture = _fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加课程'));
    await tester.pumpAndSettle();
    // 默认是课程态，可切到备忘录。
    expect(find.text('保存课程'), findsOneWidget);

    await tester.tap(find.text('备忘录'));
    await tester.pumpAndSettle();
    expect(find.text('保存备忘录'), findsOneWidget);
    expect(find.text('保存课程'), findsNothing);

    // 标题为空时不能保存。
    await tester.tap(find.text('保存备忘录'));
    await tester.pumpAndSettle();
    expect(find.text('请填写备忘录标题'), findsOneWidget);
    await _dismissSnackBar(tester);

    await tester.tap(find.text('一次性'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '准备材料');
    await tester.enterText(find.byType(TextField).at(1), '图书馆');

    await tester.tap(find.text('日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await _pickTime(tester, '开始时刻', 9, 0);
    await _pickTime(tester, '结束时刻', 8, 30);
    await tester.tap(find.text('保存备忘录'));
    await tester.pumpAndSettle();
    expect(find.text('结束时刻必须晚于开始时刻'), findsOneWidget);
    await _dismissSnackBar(tester);

    await _pickTime(tester, '结束时刻', 10, 30);
    await tester.tap(find.text('保存备忘录'));
    await tester.pumpAndSettle();

    expect(find.text('保存备忘录'), findsNothing);
    final memo = fixture.controller.addedMemos.single;
    expect(memo.title, '准备材料');
    expect(memo.location, '图书馆');
    expect(memo.isRecurring, isFalse);
    expect(memo.date, fixture.today);
    expect(memo.startMinutes, 540);
    expect(memo.endMinutes, 630);
  });

  testWidgets('备忘录支持按周重复时间类型', (tester) async {
    _useTallSurface(tester);
    final fixture = _fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('备忘录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '每周例会');
    await tester.tap(find.text('保存备忘录'));
    await tester.pumpAndSettle();

    final memo = fixture.controller.addedMemos.single;
    expect(memo.title, '每周例会');
    expect(memo.isRecurring, isTrue);
    expect(memo.weekday, DateTime.monday);
    expect(memo.startPeriod, 1);
    expect(memo.endPeriod, 2);
    expect(memo.weekRule, isNotNull);
    expect(memo.date, isNull);
    expect(memo.startMinutes, isNull);
  });
}

/// 备忘录表单较长，默认 800x600 的测试画布会把底部按钮挤出屏幕。
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _dismissSnackBar(WidgetTester tester) async {
  // SnackBar 默认停留 4 秒；等它消失，避免遮挡页面底部的按钮。
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// 打开时间选择器，切到键盘输入模式后填入时分并确认。
Future<void> _pickTime(
  WidgetTester tester,
  String label,
  int hour,
  int minute,
) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), '$hour');
  await tester.enterText(fields.at(1), '$minute');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Widget _app(_Fixture fixture) {
  return ProviderScope(
    overrides: [
      scheduleControllerProvider.overrideWith(() => fixture.controller),
      // 固定“现在”为当天 00:00。fixture 的日期跟着真实今天走，若放任真实时刻，
      // 傍晚之后运行测试会触发“课上完自动跳到第二天”，备忘录就落到昨日视图里了。
      clockProvider.overrideWith((ref) => Stream.value(_startOfToday())),
    ],
    child: const CourseScheduleApp(),
  );
}

DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// 同一天里有一条课程和一条更早的按周重复备忘录。
class _Fixture {
  _Fixture({required this.today, required this.controller});

  final DateTime today;
  final _FakeScheduleController controller;
}

_Fixture _fixture() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final term = Term(
    id: currentTermId,
    name: '测试学期',
    firstWeekMonday: monday,
    totalWeeks: 20,
    periodsByWeekday: {
      for (var day = 1; day <= 7; day++)
        day: const [
          LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525),
          LessonPeriod(number: 2, startMinutes: 530, endMinutes: 575),
        ],
    },
  );
  final course = Course(
    id: 'course-1',
    name: '高等数学',
    teacher: '张老师',
    colorValue: 0xFF7D9DCE,
    sessions: [
      CourseSession(
        id: 'session-1',
        weekday: today.weekday,
        startPeriod: 2,
        endPeriod: 2,
        weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
        location: 'A202',
      ),
    ],
  );
  // 颜色刻意取一个不在调色板里的值，便于断言改色确实写回。
  final memo = Memo(
    id: 'memo-1',
    title: '交作业',
    location: '图书馆',
    colorValue: 0xFF123456,
    weekday: today.weekday,
    startPeriod: 1,
    endPeriod: 1,
    weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
  );
  return _Fixture(
    today: today,
    controller: _FakeScheduleController(
      ScheduleData(term: term, courses: [course], memos: [memo]),
    ),
  );
}

class _FakeScheduleController extends ScheduleController {
  _FakeScheduleController(this.data);

  final ScheduleData data;
  final addedMemos = <Memo>[];
  final updatedMemos = <Memo>[];
  final deletedMemos = <String>[];
  final changedMemoColors = <String, int>{};

  @override
  Future<ScheduleData> build() async => data;

  @override
  Future<void> addMemo(Memo memo) async {
    addedMemos.add(memo);
  }

  @override
  Future<void> updateMemo(Memo memo) async {
    updatedMemos.add(memo);
  }

  @override
  Future<void> deleteMemo(String memoId) async {
    deletedMemos.add(memoId);
  }

  @override
  Future<void> changeMemoColor(String memoId, int colorValue) async {
    changedMemoColors[memoId] = colorValue;
  }
}
