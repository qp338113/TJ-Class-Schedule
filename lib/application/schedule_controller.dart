import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    this.memos = const [],
    this.adjustments = const [],
    this.cancellations = const [],
  });

  final Term? term;
  final List<Course> courses;
  final List<Memo> memos;
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
    final memos = await _database.loadMemos(currentTermId);
    final adjustments = await _database.loadScheduleAdjustments();
    final cancellations = await _database.loadCourseCancellations();
    return saved == null
        ? ScheduleData(
            memos: memos,
            adjustments: adjustments,
            cancellations: cancellations,
          )
        : ScheduleData(
            term: saved.term,
            courses: saved.courses,
            memos: memos,
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
        memos: current.memos,
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
        memos: current.memos,
        adjustments: current.adjustments,
        cancellations: current.cancellations,
      );
    });
  }

  Future<void> replaceMemos(List<Memo> memos) async {
    final current = state.requireValue;
    final term = current.term;
    if (term == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _database.replaceTermMemos(term.id, memos);
      return ScheduleData(
        term: term,
        courses: current.courses,
        memos: List<Memo>.unmodifiable(memos),
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
      await _database.replaceTermMemos(backup.term.id, backup.memos);
      await _database.replaceScheduleAdjustments(backup.adjustments);
      await _database.ensureNationalCalendar();
      await _database.replaceCourseCancellations(backup.cancellations);
      final adjustments = await _database.loadScheduleAdjustments();
      return ScheduleData(
        term: backup.term,
        courses: List.unmodifiable(backup.courses),
        memos: List.unmodifiable(backup.memos),
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
        memos: current.memos,
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

  Future<void> addMemo(Memo memo) async {
    final current = state.requireValue;
    await replaceMemos([...current.memos, memo]);
  }

  Future<void> updateMemo(Memo memo) async {
    final current = state.requireValue;
    await replaceMemos([
      for (final existing in current.memos)
        if (existing.id == memo.id) memo else existing,
    ]);
  }

  Future<void> deleteMemo(String memoId) async {
    final current = state.requireValue;
    await replaceMemos(
      current.memos.where((memo) => memo.id != memoId).toList(),
    );
  }

  Future<void> changeMemoColor(String memoId, int colorValue) async {
    final current = state.requireValue;
    final changed = current.memos.map((memo) {
      if (memo.id != memoId) return memo;
      return Memo(
        id: memo.id,
        title: memo.title,
        location: memo.location,
        colorValue: colorValue,
        weekday: memo.weekday,
        startPeriod: memo.startPeriod,
        endPeriod: memo.endPeriod,
        weekRule: memo.weekRule,
        date: memo.date,
        startMinutes: memo.startMinutes,
        endMinutes: memo.endMinutes,
      );
    }).toList();
    await replaceMemos(changed);
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
        memos: current.memos,
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
        memos: current.memos,
        adjustments: adjustments,
        cancellations: current.cancellations,
      ),
    );
  }

  /// 取消某一天的替代课表，这一天仍是「调休上班日」，只是按实际周次上课。
  Future<void> clearReplacementSchedule(DateTime date) async {
    final current = state.requireValue;
    await _database.clearReplacementSchedule(date);
    final adjustments = await _database.loadScheduleAdjustments();
    state = AsyncData(
      ScheduleData(
        term: current.term,
        courses: current.courses,
        memos: current.memos,
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

/// 主页左右滑动切换日期的步长设置：true 表示一次滑动切换一周。
final swipeAdvancesWeekProvider =
    AsyncNotifierProvider<SwipeAdvancesWeekController, bool>(
      SwipeAdvancesWeekController.new,
    );

class SwipeAdvancesWeekController extends AsyncNotifier<bool> {
  static const _settingKey = 'swipe_advances_week';
  late final ScheduleDatabase _database;

  @override
  Future<bool> build() async {
    _database = await ref.watch(databaseProvider.future);
    final saved = await _database.loadSetting(_settingKey);
    return saved == 'true';
  }

  Future<void> saveSettings(bool advancesWeek) async {
    final previous = state;
    state = AsyncData(advancesWeek);
    try {
      await _database.saveSetting(_settingKey, '$advancesWeek');
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// 主界面主题色（种子色，ARGB int）。缺省值与改造前的写死种子色一致，
/// 保证用户未设置时外观不变。
final themeSeedColorProvider =
    AsyncNotifierProvider<ThemeSeedColorController, int>(
      ThemeSeedColorController.new,
    );

class ThemeSeedColorController extends AsyncNotifier<int> {
  static const _settingKey = 'theme_seed_color';
  static const defaultColorValue = 0xFF607D8B;
  late final ScheduleDatabase _database;

  @override
  Future<int> build() async {
    _database = await ref.watch(databaseProvider.future);
    final saved = await _database.loadSetting(_settingKey);
    final parsed = saved == null ? null : int.tryParse(saved);
    return parsed ?? defaultColorValue;
  }

  Future<void> saveSettings(int colorValue) async {
    final previous = state;
    state = AsyncData(colorValue);
    try {
      await _database.saveSetting(_settingKey, '$colorValue');
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// 背景图的选取与文件落盘。真实实现用 FilePicker 选图、path_provider 定位
/// 应用私有目录，抽成接口是为了让设置读写逻辑能在单元测试里跑通。
///
/// 拆成「取字节」和「存字节」两步，是为了让调用方能在两者之间插入裁剪预览页。
abstract class BackgroundImageSource {
  /// 让用户选一张图片并读出字节；用户取消选择时返回 null。
  Future<Uint8List?> pickBytes();

  /// 把裁剪后的字节写入应用私有目录，返回保存后的路径。
  Future<String> store(Uint8List bytes);

  /// 删除已保存的背景图，文件不存在时静默忽略。
  Future<void> remove(String path);
}

class LocalBackgroundImageSource implements BackgroundImageSource {
  const LocalBackgroundImageSource();

  /// 固定文件名，重新选择时直接覆盖，不留旧图。
  static const _fileName = 'background_image';

  @override
  Future<Uint8List?> pickBytes() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择背景图',
      type: FileType.image,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  @override
  Future<String> store(Uint8List bytes) async {
    final directory = await getApplicationSupportDirectory();
    final target = File(p.join(directory.path, _fileName));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  @override
  Future<void> remove(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

final backgroundImageSourceProvider = Provider<BackgroundImageSource>(
  (_) => const LocalBackgroundImageSource(),
);

/// 主界面背景图在应用私有目录下的路径；null 表示未设置背景图。
/// 图片不进数据库，也不进备份，仅保存一个本机路径。
final backgroundImagePathProvider =
    AsyncNotifierProvider<BackgroundImagePathController, String?>(
      BackgroundImagePathController.new,
    );

class BackgroundImagePathController extends AsyncNotifier<String?> {
  static const _settingKey = 'background_image_path';
  late final ScheduleDatabase _database;

  @override
  Future<String?> build() async {
    _database = await ref.watch(databaseProvider.future);
    return _database.loadSetting(_settingKey);
  }

  /// 用户选好并裁剪完的字节，落盘后保存路径。
  Future<void> saveBackgroundImage(Uint8List bytes) async {
    final path = await ref.read(backgroundImageSourceProvider).store(bytes);
    await _persist(path);
  }

  Future<void> clearBackgroundImage() async {
    final current = state.valueOrNull;
    await _persist(null);
    if (current == null) return;
    try {
      await ref.read(backgroundImageSourceProvider).remove(current);
    } catch (_) {
      // 文件删不掉不影响设置已清空，界面会静默降级为无背景图。
    }
  }

  Future<void> _persist(String? path) async {
    final previous = state;
    state = AsyncData(path);
    try {
      if (path == null) {
        await _database.deleteSetting(_settingKey);
      } else {
        await _database.saveSetting(_settingKey, path);
      }
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// 桌面小组件自己的背景色（ARGB int），与主界面主题色互不影响。
/// null 表示未自定义，小组件沿用原来的浅色背景。
final widgetColorProvider =
    AsyncNotifierProvider<WidgetColorController, int?>(
      WidgetColorController.new,
    );

class WidgetColorController extends AsyncNotifier<int?> {
  static const _settingKey = 'widget_color';
  late final ScheduleDatabase _database;

  @override
  Future<int?> build() async {
    _database = await ref.watch(databaseProvider.future);
    final saved = await _database.loadSetting(_settingKey);
    return saved == null ? null : int.tryParse(saved);
  }

  /// 保存小组件颜色，传 null 表示恢复默认（删除该项设置）。
  Future<void> saveSettings(int? colorValue) async {
    final previous = state;
    state = AsyncData(colorValue);
    try {
      if (colorValue == null) {
        await _database.deleteSetting(_settingKey);
      } else {
        await _database.saveSetting(_settingKey, '$colorValue');
      }
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// 主界面背景图的遮罩浓度（0.0 完全透明 ~ 1.0 全黑）。
/// 默认 0.55：既能让背景图看得见，又能保证卡片文字清晰。
final backgroundOverlayOpacityProvider =
    AsyncNotifierProvider<BackgroundOverlayOpacityController, double>(
      BackgroundOverlayOpacityController.new,
    );

class BackgroundOverlayOpacityController extends AsyncNotifier<double> {
  static const _settingKey = 'background_overlay_opacity';
  static const defaultOpacity = 0.55;
  late final ScheduleDatabase _database;

  @override
  Future<double> build() async {
    _database = await ref.watch(databaseProvider.future);
    final saved = await _database.loadSetting(_settingKey);
    return double.tryParse(saved ?? '')?.clamp(0.0, 1.0) ?? defaultOpacity;
  }

  Future<void> saveSettings(double opacity) async {
    final value = opacity.clamp(0.0, 1.0);
    final previous = state;
    state = AsyncData(value);
    try {
      await _database.saveSetting(_settingKey, '$value');
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// 课程/备忘录卡片的底色不透明度（1.0 完全不透明）。
/// 有背景图时调低一点能透出背景，同时保持文字可读。
final cardOpacityProvider =
    AsyncNotifierProvider<CardOpacityController, double>(
      CardOpacityController.new,
    );

class CardOpacityController extends AsyncNotifier<double> {
  static const _settingKey = 'card_opacity';
  static const defaultOpacity = 1.0;

  /// 再低文字就压不住背景，读不清了。
  static const minOpacity = 0.3;
  late final ScheduleDatabase _database;

  @override
  Future<double> build() async {
    _database = await ref.watch(databaseProvider.future);
    final saved = await _database.loadSetting(_settingKey);
    return double.tryParse(saved ?? '')?.clamp(minOpacity, 1.0) ??
        defaultOpacity;
  }

  Future<void> saveSettings(double opacity) async {
    final value = opacity.clamp(minOpacity, 1.0);
    final previous = state;
    state = AsyncData(value);
    try {
      await _database.saveSetting(_settingKey, '$value');
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// 桌面小组件的倒计时刷新频率。
enum WidgetRefreshMode {
  /// 省电：临近上课（2 小时内）每分钟刷，更远时 5 分钟刷一次。
  powerSaving('省电'),
  /// 正常：始终每分钟刷新。
  normal('正常'),
  /// 精确：每秒刷新，倒计时精确到秒，耗电明显更高。
  precise('精确');

  const WidgetRefreshMode(this.label);

  final String label;

  static WidgetRefreshMode parse(String? raw) {
    for (final mode in values) {
      if (mode.name == raw) return mode;
    }
    return WidgetRefreshMode.powerSaving;
  }
}

/// 小组件倒计时的刷新频率，默认省电模式。
final widgetRefreshModeProvider =
    AsyncNotifierProvider<WidgetRefreshModeController, WidgetRefreshMode>(
      WidgetRefreshModeController.new,
    );

class WidgetRefreshModeController extends AsyncNotifier<WidgetRefreshMode> {
  static const _settingKey = 'widget_refresh_mode';
  static const defaultMode = WidgetRefreshMode.powerSaving;
  late final ScheduleDatabase _database;

  @override
  Future<WidgetRefreshMode> build() async {
    _database = await ref.watch(databaseProvider.future);
    return WidgetRefreshMode.parse(await _database.loadSetting(_settingKey));
  }

  Future<void> saveSettings(WidgetRefreshMode mode) async {
    final previous = state;
    state = AsyncData(mode);
    try {
      await _database.saveSetting(_settingKey, mode.name);
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
