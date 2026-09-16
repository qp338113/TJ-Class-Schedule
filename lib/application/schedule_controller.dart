import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/national_holiday_service.dart';
import '../data/schedule_database.dart';
import '../data/schedule_backup_codec.dart';
import '../domain/notification_settings.dart';
import '../domain/schedule_models.dart';

const currentTermId = 'current-term';

class ScheduleData {
  const ScheduleData({
    this.term,
    this.courses = const [],
    this.adjustments = const [],
    this.cancellations = const [],
  });

  final Term? term;
  final List<Course> courses;
  final List<ScheduleAdjustment> adjustments;
  final List<CourseCancellation> cancellations;
}

final nationalHolidayServiceProvider = Provider(
  (_) => const NationalHolidayService(),
);

final databaseProvider = FutureProvider<ScheduleDatabase>((ref) async {
  final database = await ScheduleDatabase.open();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final scheduleControllerProvider =
    AsyncNotifierProvider<ScheduleController, ScheduleData>(
      ScheduleController.new,
    );

class ScheduleController extends AsyncNotifier<ScheduleData> {
  static const _importSnapshotKey = 'last_import_snapshot';
  static const _backupCodec = ScheduleBackupCodec();
  late final ScheduleDatabase _database;

  @override
  Future<ScheduleData> build() async {
    _database = await ref.watch(databaseProvider.future);
    final saved = await _database.loadTermSchedule(currentTermId);
    final adjustments = await _database.loadScheduleAdjustments();
    final cancellations = await _database.loadCourseCancellations();
    return saved == null
        ? ScheduleData(adjustments: adjustments, cancellations: cancellations)
        : ScheduleData(
            term: saved.term,
            courses: saved.courses,
            adjustments: adjustments,
            cancellations: cancellations,
          );
  }

  Future<void> saveTerm(Term term) async {
    final current = state.valueOrNull ?? const ScheduleData();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _database.replaceTermSchedule(term, current.courses);
      return ScheduleData(
        term: term,
        courses: current.courses,
        adjustments: current.adjustments,
        cancellations: current.cancellations,
      );
    });
  }

  Future<void> replaceCourses(List<Course> courses) async {
    final current = state.requireValue;
    final term = current.term;
    if (term == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _database.replaceTermSchedule(term, courses);
      return ScheduleData(
        term: term,
        courses: List<Course>.unmodifiable(courses),
        adjustments: current.adjustments,
        cancellations: current.cancellations,
      );
    });
  }

  Future<void> importCourses(
    List<Course> incoming, {
    required bool merge,
  }) async {
    final current = state.requireValue;
    await _database.saveSetting(
      _importSnapshotKey,
      _backupCodec.encodeCourses(current.courses),
    );
    final now = DateTime.now().microsecondsSinceEpoch;
    final normalized = <Course>[];
    for (var index = 0; index < incoming.length; index++) {
      final source = incoming[index];
      final old = merge
          ? current.courses
                .where((item) => _courseKey(item) == _courseKey(source))
                .firstOrNull
          : null;
      final id = old?.id ?? 'import-$now-$index';
      normalized.add(
        Course(
          id: id,
          name: source.name,
          teacher: source.teacher,
          colorValue: old?.colorValue ?? source.colorValue,
          sessions: [
            for (
              var sessionIndex = 0;
              sessionIndex < source.sessions.length;
              sessionIndex++
            )
              _copySession(
                source.sessions[sessionIndex],
                '$id-session-$sessionIndex',
              ),
          ],
        ),
      );
    }
    final importedKeys = normalized.map(_courseKey).toSet();
    await replaceCourses(
      merge
          ? [
              ...current.courses.where(
                (course) => !importedKeys.contains(_courseKey(course)),
              ),
              ...normalized,
            ]
          : normalized,
    );
  }

  Future<bool> undoLastImport() async {
    final snapshot = await _database.loadSetting(_importSnapshotKey);
    if (snapshot == null) return false;
    await replaceCourses(_backupCodec.decodeCourses(snapshot));
    await _database.deleteSetting(_importSnapshotKey);
    return true;
  }

  Future<void> restoreBackup(ScheduleBackup backup) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _database.replaceTermSchedule(backup.term, backup.courses);
      await _database.replaceScheduleAdjustments(backup.adjustments);
      await _database.ensureNationalCalendar();
      await _database.replaceCourseCancellations(backup.cancellations);
      final adjustments = await _database.loadScheduleAdjustments();
      return ScheduleData(
        term: backup.term,
        courses: List.unmodifiable(backup.courses),
        adjustments: adjustments,
        cancellations: List.unmodifiable(backup.cancellations),
      );
    });
  }

  Future<void> addCourse(Course course) async {
    final current = state.requireValue;
    await replaceCourses([...current.courses, course]);
  }

  Future<void> updateCourse(Course course) async {
    final current = state.requireValue;
    await replaceCourses([
      for (final existing in current.courses)
        if (existing.id == course.id) course else existing,
    ]);
  }

  Future<void> deleteCourse(String courseId) async {
    final current = state.requireValue;
    await replaceCourses(
      current.courses.where((course) => course.id != courseId).toList(),
    );
  }

  Future<void> cancelSessionOnDate(String sessionId, DateTime date) async {
    final current = state.requireValue;
    await _database.saveCourseCancellation(sessionId, date);
    final cancellations = await _database.loadCourseCancellations();
    state = AsyncData(
      ScheduleData(
        term: current.term,
        courses: current.courses,
        adjustments: current.adjustments,
        cancellations: cancellations,
      ),
    );
  }

  Future<void> changeCourseColor(String courseId, int colorValue) async {
    final current = state.requireValue;
    final changed = current.courses.map((course) {
      if (course.id != courseId) return course;
      return Course(
        id: course.id,
        name: course.name,
        teacher: course.teacher,
        colorValue: colorValue,
        sessions: course.sessions,
      );
    }).toList();
    await replaceCourses(changed);
  }

  Future<int> checkNationalMakeupDays() async {
    final current = state.valueOrNull;
    final term = current?.term;
    if (current == null || term == null) return 0;
    final service = ref.read(nationalHolidayServiceProvider);
    final years = {
      term.firstWeekMonday.year,
      term.firstWeekMonday.add(Duration(days: term.totalWeeks * 7 - 1)).year,
    };
    final dates = <DateTime>[];
    final holidays = <DateTime, String>{};
    for (final year in years) {
      final calendar = await service.fetchCalendar(year);
      dates.addAll(calendar.makeupDays);
      holidays.addAll(calendar.holidays);
    }
    await _database.saveNationalMakeupDays(dates);
    await _database.saveNationalHolidays(holidays);
    final adjustments = await _database.loadScheduleAdjustments();
    state = AsyncData(
      ScheduleData(
        term: term,
        courses: current.courses,
        adjustments: adjustments,
        cancellations: current.cancellations,
      ),
    );
    return dates.length;
  }

  Future<void> setReplacementSchedule(
    DateTime date,
    int week,
    int weekday,
  ) async {
    final current = state.requireValue;
    await _database.setReplacementSchedule(date, week, weekday);
    final adjustments = await _database.loadScheduleAdjustments();
    state = AsyncData(
      ScheduleData(
        term: current.term,
        courses: current.courses,
        adjustments: adjustments,
        cancellations: current.cancellations,
      ),
    );
  }
}

String _courseKey(Course course) =>
    '${course.name.trim().toLowerCase()}\u0000${course.teacher.trim().toLowerCase()}';

CourseSession _copySession(CourseSession source, String id) => CourseSession(
  id: id,
  weekday: source.weekday,
  startPeriod: source.startPeriod,
  endPeriod: source.endPeriod,
  weekRule: source.weekRule,
  location: source.location,
  teacherOverride: source.teacherOverride,
);

final notificationSettingsProvider =
    AsyncNotifierProvider<NotificationSettingsController, NotificationSettings>(
      NotificationSettingsController.new,
    );

class NotificationSettingsController
    extends AsyncNotifier<NotificationSettings> {
  late final ScheduleDatabase _database;

  @override
  Future<NotificationSettings> build() async {
    _database = await ref.watch(databaseProvider.future);
    return _database.loadNotificationSettings();
  }

  Future<void> saveSettings(NotificationSettings settings) async {
    final previous = state;
    state = AsyncData(settings);
    try {
      await _database.saveNotificationSettings(settings);
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final notificationNavigationRevisionProvider = StateProvider<int>((ref) => 0);

final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(
    const Duration(minutes: 1),
    (_) => DateTime.now(),
  );
});
