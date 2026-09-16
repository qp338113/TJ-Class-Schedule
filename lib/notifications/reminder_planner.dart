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
    List<ScheduleAdjustment> adjustments = const [],
    List<CourseCancellation> cancellations = const [],
    required NotificationSettings settings,
  }) {
    if (!settings.enabled) return const [];
    final engine = ScheduleEngine(
      term: term,
      courses: courses,
      adjustments: adjustments,
      cancellations: cancellations,
    );
    final firstDay = DateTime(now.year, now.month, now.day);
    final pending = <({ScheduledCourse course, DateTime reminderAt})>[];
    for (var offset = 0; offset < 7; offset++) {
      final date = firstDay.add(Duration(days: offset));
      for (final course in engine.getCoursesForDate(date)) {
        final originalReminderAt = course.startTime.subtract(
          Duration(minutes: settings.advanceMinutes),
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
          pending.add((course: course, reminderAt: reminderAt));
        }
      }
    }
    pending.sort((a, b) => a.reminderAt.compareTo(b.reminderAt));
    final selected = settings.onlyNextCourse && pending.isNotEmpty
        ? [pending.first]
        : pending;
    return List<ReminderPlan>.generate(selected.length, (index) {
      final item = selected[index];
      final course = item.course;
      final location = course.session.location.trim();
      return ReminderPlan(
        id: 1000 + index,
        scheduledAt: item.reminderAt,
        title: '${course.course.name} 即将上课',
        body:
            '${_time(course.startTime)}${location.isEmpty ? '' : ' · $location'}',
        payload: _datePayload(course.startTime),
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
