import '../domain/notification_settings.dart';
import '../domain/schedule_engine.dart';
import '../domain/schedule_models.dart';

class ReminderPlan {
  const ReminderPlan({
    required this.id,
    required this.scheduledAt,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final DateTime scheduledAt;
  final String title;
  final String body;
  final String payload;
}

class LockScreenCoursePlan {
  const LockScreenCoursePlan({
    required this.id,
    required this.scheduledAt,
    required this.timeoutAfterMilliseconds,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final DateTime scheduledAt;
  final int timeoutAfterMilliseconds;
  final String title;
  final String body;
  final String payload;
}

class ReminderPlanner {
  const ReminderPlanner();

  List<ReminderPlan> createPlans({
    required DateTime now,
    required Term term,
    required List<Course> courses,
    Iterable<Memo> memos = const [],
    List<ScheduleAdjustment> adjustments = const [],
    List<CourseCancellation> cancellations = const [],
    required NotificationSettings settings,
  }) {
    if (!settings.enabled) return const [];
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      memos: memos,
      adjustments: adjustments,
      cancellations: cancellations,
    );
    final firstDay = DateTime(now.year, now.month, now.day);
    final pending = <({ScheduleEntry entry, DateTime reminderAt})>[];
    for (var offset = 0; offset < 7; offset++) {
      final date = firstDay.add(Duration(days: offset));
      for (final entry in engine.getEntriesForDate(date)) {
        // 备忘录有自己的提前时间，与课程的 advanceMinutes 相互独立。
        final advanceMinutes = entry.isMemo
            ? settings.memoAdvanceMinutes
            : settings.advanceMinutes;
        final originalReminderAt = entry.startTime.subtract(
          Duration(minutes: advanceMinutes),
        );
        var reminderAt = originalReminderAt;
        if (settings.delayWhenInClass) {
          DateTime? latestOngoingEnd;
          for (final ongoing in engine.getCoursesForDate(originalReminderAt)) {
            final isInClass =
                !originalReminderAt.isBefore(ongoing.startTime) &&
                originalReminderAt.isBefore(ongoing.endTime);
            if (isInClass &&
                (latestOngoingEnd == null ||
                    ongoing.endTime.isAfter(latestOngoingEnd))) {
              latestOngoingEnd = ongoing.endTime;
            }
          }
          if (latestOngoingEnd != null) {
            reminderAt = latestOngoingEnd.add(const Duration(minutes: 3));
          }
        }
        if (reminderAt.isAfter(now)) {
          pending.add((entry: entry, reminderAt: reminderAt));
        }
      }
    }
    pending.sort((a, b) {
      final timeOrder = a.reminderAt.compareTo(b.reminderAt);
      if (timeOrder != 0) return timeOrder;
      final startOrder = a.entry.startTime.compareTo(b.entry.startTime);
      if (startOrder != 0) return startOrder;
      return a.entry.isMemo == b.entry.isMemo
          ? a.entry.title.compareTo(b.entry.title)
          : (a.entry.isMemo ? 1 : -1);
    });
    final selected = settings.onlyNextCourse && pending.isNotEmpty
        ? [pending.first]
        : pending;
    return List<ReminderPlan>.generate(selected.length, (index) {
      final item = selected[index];
      final entry = item.entry;
      final location = entry.location.trim();
      return ReminderPlan(
        id: 1000 + index,
        scheduledAt: item.reminderAt,
        title: entry.isMemo
            ? '${entry.title} 即将开始'
            : '${entry.title} 即将上课',
        body:
            '${_time(entry.startTime)}${location.isEmpty ? '' : ' · $location'}',
        payload: _datePayload(entry.startTime),
      );
    });
  }

  List<LockScreenCoursePlan> createLockScreenPlans({
    required DateTime now,
    required Term term,
    required List<Course> courses,
    List<ScheduleAdjustment> adjustments = const [],
    List<CourseCancellation> cancellations = const [],
    required NotificationSettings settings,
  }) {
    if (!settings.enabled || !settings.showNextCourseOnLockScreen) {
      return const [];
    }
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      adjustments: adjustments,
      cancellations: cancellations,
    );
    final firstDay = DateTime(now.year, now.month, now.day);
    final upcoming = <ScheduledCourse>[];
    for (var offset = 0; offset < 7; offset++) {
      final date = firstDay.add(Duration(days: offset));
      upcoming.addAll(
        engine
            .getCoursesForDate(date)
            .where((course) => course.startTime.isAfter(now)),
      );
    }
    upcoming.sort((a, b) => a.startTime.compareTo(b.startTime));
    final plans = <LockScreenCoursePlan>[];
    for (final (index, course) in upcoming.indexed) {
      var showAt = course.startTime.subtract(const Duration(hours: 1));
      if (index > 0 && upcoming[index - 1].startTime.isAfter(showAt)) {
        showAt = upcoming[index - 1].startTime;
      }
      if (!showAt.isAfter(now)) showAt = now.add(const Duration(seconds: 1));
      if (!showAt.isBefore(course.startTime)) continue;
      final details = [
        _time(course.startTime),
        course.session.location.trim(),
        course.teacher.trim(),
      ].where((value) => value.isNotEmpty).join(' · ');
      plans.add(
        LockScreenCoursePlan(
          id: 2000 + plans.length,
          scheduledAt: showAt,
          timeoutAfterMilliseconds: course.startTime
              .difference(showAt)
              .inMilliseconds,
          title: '下一节课：${course.course.name}',
          body: details,
          payload: _datePayload(course.startTime),
        ),
      );
    }
    return List<LockScreenCoursePlan>.unmodifiable(plans);
  }

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _datePayload(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
