import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/notifications/notification_lifecycle.dart';
import 'package:offline_course_schedule/notifications/notification_service.dart';
import 'package:offline_course_schedule/presentation/tutorial_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const widgetChannel = MethodChannel('offline_course_schedule/widget');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, null);
  });

  testWidgets('首次进入可选择暂不查看教程且只询问一次', (tester) async {
    final settingsController = _FakeSettingsController(
      const NotificationSettings(magicOsGuideCompleted: true),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(
            () => _FakeScheduleController(),
          ),
          notificationSettingsProvider.overrideWith(() => settingsController),
        ],
        child: MaterialApp(
          home: NotificationLifecycle(
            service: _FakeNotificationService(),
            child: const Scaffold(body: Text('主页')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第一次使用，需要看看教程吗？'), findsOneWidget);
    await tester.tap(find.text('暂不查看'));
    await tester.pumpAndSettle();

    expect(find.text('第一次使用，需要看看教程吗？'), findsNothing);
    expect(
      settingsController.state.valueOrNull?.tutorialPromptCompleted,
      isTrue,
    );
  });

  testWidgets('教程用简单步骤覆盖主要功能', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TutorialPage()));
    await tester.pumpAndSettle();

    expect(find.text('先添加学期'), findsOneWidget);
    expect(find.text('导入课程'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('添加桌面小组件'), 400);
    expect(find.text('添加桌面小组件'), findsOneWidget);
  });
}

class _FakeScheduleController extends ScheduleController {
  @override
  Future<ScheduleData> build() async => const ScheduleData();
}

class _FakeSettingsController extends NotificationSettingsController {
  _FakeSettingsController(this.initial);

  final NotificationSettings initial;

  @override
  Future<NotificationSettings> build() async => initial;

  @override
  Future<void> saveSettings(NotificationSettings settings) async {
    state = AsyncData(settings);
  }
}

class _FakeNotificationService extends NotificationService {
  @override
  Future<void> requestAndroidPermissions() async {}

  @override
  Future<int> reschedule({
    required ScheduleData schedule,
    required NotificationSettings settings,
    DateTime? now,
  }) async => 0;
}
