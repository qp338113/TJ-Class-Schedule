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
  });
}
