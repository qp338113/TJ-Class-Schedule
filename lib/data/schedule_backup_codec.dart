import 'dart:convert';

import '../domain/notification_settings.dart';
import '../domain/schedule_models.dart';

class ScheduleBackup {
  const ScheduleBackup({
    required this.term,
    required this.courses,
    required this.adjustments,
    required this.cancellations,
    required this.settings,
  });

  final Term term;
  final List<Course> courses;
  final List<ScheduleAdjustment> adjustments;
  final List<CourseCancellation> cancellations;
  final NotificationSettings settings;
}

class ScheduleBackupCodec {
  const ScheduleBackupCodec();

  String encodeCourses(Iterable<Course> courses) =>
      jsonEncode(courses.map(_courseToJson).toList());

  List<Course> decodeCourses(String source) => _list(
    jsonDecode(source),
  ).map((item) => _courseFromJson(_map(item))).toList();

  String encode(ScheduleBackup backup) => jsonEncode({
    'version': 1,
    'term': _termToJson(backup.term),
    'courses': backup.courses.map(_courseToJson).toList(),
    'adjustments': backup.adjustments
        .map(
          (item) => {
            'date': _dateKey(item.date),
            'replacementWeek': item.replacementWeek,
            'replacementWeekday': item.replacementWeekday,
            'isHoliday': item.isHoliday,
            'holidayName': item.holidayName,
          },
        )
        .toList(),
    'cancellations': backup.cancellations
        .map(
          (item) => {'sessionId': item.sessionId, 'date': _dateKey(item.date)},
        )
        .toList(),
    'settings': {
      'enabled': backup.settings.enabled,
      'advanceMinutes': backup.settings.advanceMinutes,
      'onlyNextCourse': backup.settings.onlyNextCourse,
      'delayWhenInClass': backup.settings.delayWhenInClass,
      'showNextCourseOnLockScreen': backup.settings.showNextCourseOnLockScreen,
      'alertMode': backup.settings.alertMode.name,
      'magicOsGuideCompleted': backup.settings.magicOsGuideCompleted,
      'tutorialPromptCompleted': backup.settings.tutorialPromptCompleted,
    },
  });

  ScheduleBackup decode(String source) {
    final root = jsonDecode(source);
    if (root is! Map<String, dynamic> || root['version'] != 1) {
      throw const FormatException('不是受支持的课表备份文件');
    }
    final settings = _map(root['settings']);
    return ScheduleBackup(
      term: _termFromJson(_map(root['term'])),
      courses: _list(
        root['courses'],
      ).map((item) => _courseFromJson(_map(item))).toList(),
      adjustments: _list(root['adjustments']).map((item) {
        final map = _map(item);
        return ScheduleAdjustment(
          date: DateTime.parse(_string(map, 'date')),
          replacementWeek: map['replacementWeek'] as int?,
          replacementWeekday: map['replacementWeekday'] as int?,
          isHoliday: map['isHoliday'] as bool? ?? false,
          holidayName: map['holidayName'] as String?,
        );
      }).toList(),
      cancellations: _list(root['cancellations']).map((item) {
        final map = _map(item);
        return CourseCancellation(
          sessionId: _string(map, 'sessionId'),
          date: DateTime.parse(_string(map, 'date')),
        );
      }).toList(),
      settings: NotificationSettings(
        enabled: settings['enabled'] as bool? ?? true,
        advanceMinutes: settings['advanceMinutes'] as int? ?? 30,
        onlyNextCourse: settings['onlyNextCourse'] as bool? ?? false,
        delayWhenInClass: settings['delayWhenInClass'] as bool? ?? true,
        showNextCourseOnLockScreen:
            settings['showNextCourseOnLockScreen'] as bool? ?? false,
        alertMode: ReminderAlertMode.values.byName(
          settings['alertMode'] as String? ??
              ReminderAlertMode.soundAndVibration.name,
        ),
        magicOsGuideCompleted:
            settings['magicOsGuideCompleted'] as bool? ?? false,
        tutorialPromptCompleted:
            settings['tutorialPromptCompleted'] as bool? ?? false,
      ),
    );
  }
}

Map<String, Object?> _termToJson(Term term) => {
  'id': term.id,
  'name': term.name,
  'firstWeekMonday': _dateKey(term.firstWeekMonday),
  'totalWeeks': term.totalWeeks,
  'periods': [
    for (final entry in term.periodsByWeekday.entries)
      for (final period in entry.value)
        {
          'weekday': entry.key,
          'number': period.number,
          'startMinutes': period.startMinutes,
          'endMinutes': period.endMinutes,
        },
  ],
};

Term _termFromJson(Map<String, dynamic> map) {
  final periods = <int, List<LessonPeriod>>{};
  for (final item in _list(map['periods'])) {
    final period = _map(item);
    final weekday = _integer(period, 'weekday');
    periods
        .putIfAbsent(weekday, () => [])
        .add(
          LessonPeriod(
            number: _integer(period, 'number'),
            startMinutes: _integer(period, 'startMinutes'),
            endMinutes: _integer(period, 'endMinutes'),
          ),
        );
  }
  return Term(
    id: _string(map, 'id'),
    name: _string(map, 'name'),
    firstWeekMonday: DateTime.parse(_string(map, 'firstWeekMonday')),
    totalWeeks: _integer(map, 'totalWeeks'),
    periodsByWeekday: periods,
  );
}

Map<String, Object?> _courseToJson(Course course) => {
  'id': course.id,
  'name': course.name,
  'teacher': course.teacher,
  'colorValue': course.colorValue,
  'sessions': course.sessions
      .map(
        (session) => {
          'id': session.id,
          'weekday': session.weekday,
          'startPeriod': session.startPeriod,
          'endPeriod': session.endPeriod,
          'startWeek': session.weekRule.startWeek,
          'endWeek': session.weekRule.endWeek,
          'weekType': session.weekRule.type.name,
          'explicitWeeks': session.weekRule.explicitWeeks?.toList(),
          'location': session.location,
          'teacherOverride': session.teacherOverride,
        },
      )
      .toList(),
};

Course _courseFromJson(Map<String, dynamic> map) => Course(
  id: _string(map, 'id'),
  name: _string(map, 'name'),
  teacher: _string(map, 'teacher'),
  colorValue: _integer(map, 'colorValue'),
  sessions: _list(map['sessions']).map((item) {
    final session = _map(item);
    final weeks = session['explicitWeeks'];
    return CourseSession(
      id: _string(session, 'id'),
      weekday: _integer(session, 'weekday'),
      startPeriod: _integer(session, 'startPeriod'),
      endPeriod: _integer(session, 'endPeriod'),
      weekRule: WeekRule(
        startWeek: _integer(session, 'startWeek'),
        endWeek: _integer(session, 'endWeek'),
        type: WeekType.values.byName(_string(session, 'weekType')),
        explicitWeeks: weeks == null
            ? null
            : _list(weeks).map((value) => value as int).toSet(),
      ),
      location: _string(session, 'location'),
      teacherOverride: session['teacherOverride'] as String?,
    );
  }).toList(),
);

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const FormatException('备份文件内容不完整');
}

List<dynamic> _list(Object? value) {
  if (value is List<dynamic>) return value;
  throw const FormatException('备份文件内容不完整');
}

String _string(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String) return value;
  throw const FormatException('备份文件内容不完整');
}

int _integer(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  throw const FormatException('备份文件内容不完整');
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
