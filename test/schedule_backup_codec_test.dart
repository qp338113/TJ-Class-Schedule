import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/schedule_backup_codec.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';

void main() {
  test('本地备份可完整编码并恢复', () {
    const codec = ScheduleBackupCodec();
    final backup = ScheduleBackup(
      term: Term(
        id: 'current-term',
        name: '秋季',
        firstWeekMonday: DateTime(2026, 9, 7),
        totalWeeks: 20,
        periodsByWeekday: {
          1: [LessonPeriod(number: 1, startMinutes: 480, endMinutes: 570)],
        },
      ),
      courses: [
        Course(
          id: 'c1',
          name: '数学',
          teacher: '张老师',
          colorValue: 1,
          sessions: [
            CourseSession(
              id: 's1',
              weekday: 1,
              startPeriod: 1,
              endPeriod: 1,
              weekRule: WeekRule(
                startWeek: 1,
                endWeek: 5,
                type: WeekType.custom,
                explicitWeeks: {1, 3, 5},
              ),
              location: 'A101',
            ),
          ],
        ),
      ],
      adjustments: [
        ScheduleAdjustment(
          date: DateTime(2026, 9, 20),
          replacementWeek: 4,
          replacementWeekday: 2,
        ),
      ],
      cancellations: [
        CourseCancellation(sessionId: 's1', date: DateTime(2026, 9, 21)),
      ],
      settings: const NotificationSettings(
        advanceMinutes: 45,
        alertMode: ReminderAlertMode.vibration,
      ),
    );

    final restored = codec.decode(codec.encode(backup));
    expect(restored.term.name, '秋季');
    expect(restored.courses.single.sessions.single.weekRule.explicitWeeks, {
      1,
      3,
      5,
    });
    expect(restored.adjustments.single.replacementWeek, 4);
    expect(restored.cancellations.single.sessionId, 's1');
    expect(restored.settings.advanceMinutes, 45);
    expect(restored.settings.alertMode, ReminderAlertMode.vibration);
    // 没有备忘录的备份仍可往返，备忘录为空、提醒时间取默认值。
    expect(restored.memos, isEmpty);
    expect(restored.settings.memoAdvanceMinutes, 30);
  });

  test('含有两种时间类型的备忘录可完整往返备份', () {
    const codec = ScheduleBackupCodec();
    final backup = ScheduleBackup(
      term: Term(
        id: 'current-term',
        name: '秋季',
        firstWeekMonday: DateTime(2026, 9, 7),
        totalWeeks: 20,
        periodsByWeekday: {
          1: [LessonPeriod(number: 7, startMinutes: 800, endMinutes: 845)],
        },
      ),
      courses: const [],
      memos: [
        Memo(
          id: 'memo-recurring',
          title: '社团例会',
          location: 'C303',
          colorValue: 0xFF7D9DCE,
          weekday: DateTime.wednesday,
          startPeriod: 7,
          endPeriod: 8,
          weekRule: WeekRule(
            startWeek: 2,
            endWeek: 9,
            type: WeekType.custom,
            explicitWeeks: {2, 4, 9},
          ),
        ),
        Memo(
          id: 'memo-once',
          title: '体检',
          location: '校医院',
          colorValue: 0xFFEF6C6C,
          date: DateTime(2026, 10, 1),
          startMinutes: 14 * 60,
          endMinutes: 15 * 60 + 30,
        ),
      ],
      adjustments: const [],
      cancellations: const [],
      settings: const NotificationSettings(memoAdvanceMinutes: 90),
    );

    final encoded = jsonDecode(codec.encode(backup)) as Map<String, dynamic>;
    expect(encoded['version'], 1);
    expect(encoded['memos'], hasLength(2));

    final restored = codec.decode(codec.encode(backup));
    expect(restored.memos, hasLength(2));
    expect(restored.settings.memoAdvanceMinutes, 90);

    final recurring = restored.memos.firstWhere(
      (memo) => memo.id == 'memo-recurring',
    );
    expect(recurring.title, '社团例会');
    expect(recurring.location, 'C303');
    expect(recurring.colorValue, 0xFF7D9DCE);
    expect(recurring.isRecurring, isTrue);
    expect(recurring.weekday, DateTime.wednesday);
    expect(recurring.startPeriod, 7);
    expect(recurring.endPeriod, 8);
    expect(recurring.weekRule!.type, WeekType.custom);
    expect(recurring.weekRule!.startWeek, 2);
    expect(recurring.weekRule!.endWeek, 9);
    expect(recurring.weekRule!.explicitWeeks, {2, 4, 9});

    final once = restored.memos.firstWhere((memo) => memo.id == 'memo-once');
    expect(once.title, '体检');
    expect(once.location, '校医院');
    expect(once.isRecurring, isFalse);
    expect(once.date, DateTime(2026, 10, 1));
    expect(once.startMinutes, 14 * 60);
    expect(once.endMinutes, 15 * 60 + 30);
    expect(once.weekRule, isNull);
    expect(once.weekday, isNull);
  });

  test('旧备份缺少 memos 与 memoAdvanceMinutes 时按空列表和 30 分钟回退', () {
    const codec = ScheduleBackupCodec();
    final json = codec.encode(
      ScheduleBackup(
        term: Term(
          id: 'current-term',
          name: '秋季',
          firstWeekMonday: DateTime(2026, 9, 7),
          totalWeeks: 20,
          periodsByWeekday: {
            1: [LessonPeriod(number: 1, startMinutes: 480, endMinutes: 570)],
          },
        ),
        courses: [
          Course(
            id: 'c1',
            name: '数学',
            teacher: '张老师',
            colorValue: 1,
            sessions: [
              CourseSession(
                id: 's1',
                weekday: 1,
                startPeriod: 1,
                endPeriod: 1,
                weekRule: WeekRule(
                  startWeek: 1,
                  endWeek: 5,
                  type: WeekType.every,
                ),
                location: 'A101',
              ),
            ],
          ),
        ],
        adjustments: const [],
        cancellations: const [],
        settings: const NotificationSettings(advanceMinutes: 45),
      ),
    );

    // 还原成升级前产生的 v1 备份结构：没有 memos 键，settings 也没有备忘录字段。
    final legacy = jsonDecode(json) as Map<String, dynamic>;
    legacy.remove('memos');
    (legacy['settings'] as Map<String, dynamic>).remove('memoAdvanceMinutes');

    final restored = codec.decode(jsonEncode(legacy));
    expect(restored.memos, isEmpty);
    expect(restored.settings.memoAdvanceMinutes, 30);
    expect(restored.settings.advanceMinutes, 45);
    expect(restored.courses.single.name, '数学');
  });
}
