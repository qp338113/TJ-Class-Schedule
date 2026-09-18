import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/data/schedule_backup_codec.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/presentation/data_management_page.dart';

void main() {
  final term = Term(
    id: currentTermId,
    name: '测试学期',
    firstWeekMonday: DateTime(2026, 9, 7),
    totalWeeks: 20,
    periodsByWeekday: {
      1: const [LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525)],
    },
  );
  final course = Course(
    id: 'course-1',
    name: '高等数学',
    teacher: '张老师',
    colorValue: 0,
    sessions: [
      CourseSession(
        id: 'session-1',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 1,
        weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
        location: 'A101',
      ),
    ],
  );
  final memo = Memo(
    id: 'memo-1',
    title: '交作业',
    location: '图书馆',
    colorValue: 0,
    date: DateTime(2026, 9, 7),
    startMinutes: 600,
    endMinutes: 660,
  );

  testWidgets('导出本地备份会带上备忘录', (tester) async {
    final picker = _FakeFilePicker();
    final original = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = original);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(
            () => _FakeScheduleController(
              ScheduleData(term: term, courses: [course], memos: [memo]),
            ),
          ),
          notificationSettingsProvider.overrideWith(
            () => _FakeSettingsController(const NotificationSettings()),
          ),
        ],
        child: const MaterialApp(home: DataManagementPage()),
      ),
    );
    // 页面只按需 read 这两个 provider，测试里需要主动保活并等它们加载完成。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DataManagementPage)),
    );
    container.listen(scheduleControllerProvider, (_, __) {});
    container.listen(notificationSettingsProvider, (_, __) {});
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出本地备份'));
    await tester.pumpAndSettle();

    // 导出的备份必须包含备忘录，否则再导入会清空本机备忘录。
    final backup = const ScheduleBackupCodec().decode(
      utf8.decode(picker.savedBytes!),
    );
    expect(backup.courses, hasLength(1));
    expect(backup.memos, hasLength(1));
    expect(backup.memos.single.id, 'memo-1');
    expect(backup.memos.single.title, '交作业');
    expect(backup.memos.single.startMinutes, 600);
  });
}

class _FakeFilePicker extends FilePickerPlatform {
  Uint8List? savedBytes;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedBytes = bytes;
    return Uri.file(fileName);
  }
}

class _FakeScheduleController extends ScheduleController {
  _FakeScheduleController(this.data);

  final ScheduleData data;

  @override
  Future<ScheduleData> build() async => data;
}

class _FakeSettingsController extends NotificationSettingsController {
  _FakeSettingsController(this.initial);

  final NotificationSettings initial;

  @override
  Future<NotificationSettings> build() async => initial;
}
