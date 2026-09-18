import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/presentation/magic_os_guide_page.dart';
import 'package:offline_course_schedule/presentation/notification_settings_page.dart';

void main() {
  testWidgets('提醒设置页显示课程提醒与锁屏选项', (tester) async {
    await tester.pumpWidget(
      _withSettings(
        const NotificationSettings(),
        const NotificationSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('上课提醒'), findsOneWidget);
    // 课程与备忘录各有独立的提前时间，默认值同为 30 分钟，因此有两个“30 分钟”。
    expect(find.text('30 分钟'), findsNWidgets(2));
    expect(find.text('提前时间'), findsOneWidget);
    expect(find.text('备忘录提前时间'), findsOneWidget);
    expect(find.text('仅提醒下一节'), findsOneWidget);
    expect(find.text('上课中延后提醒'), findsOneWidget);
    expect(find.text('锁屏显示下一节课'), findsOneWidget);
    expect(find.text('提醒方式'), findsOneWidget);
    expect(find.text('通知 + 震动 + 声音'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('查看使用教程'), 400);
    expect(find.text('查看使用教程'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('联系作者'), 400);
    expect(find.text('22725876'), findsOneWidget);
    expect(find.text('LJ-QWQ1144'), findsOneWidget);
    expect(find.text('1103397369'), findsOneWidget);
  });

  testWidgets('可以输入自定义提前分钟数', (tester) async {
    await tester.pumpWidget(
      _withSettings(
        const NotificationSettings(),
        const NotificationSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('提前时间'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '45');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('45 分钟'), findsOneWidget);
  });

  testWidgets('备忘录提前时间显示当前值并能单独修改', (tester) async {
    final controller = _FakeSettingsController(const NotificationSettings());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationSettingsProvider.overrideWith(() => controller),
        ],
        child: const MaterialApp(home: NotificationSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('备忘录提前时间'), findsOneWidget);
    expect(find.text('30 分钟'), findsNWidgets(2));

    await tester.tap(find.text('备忘录提前时间'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 只改备忘录这一项，课程的提前时间保持不变。
    expect(find.text('10 分钟'), findsOneWidget);
    expect(find.text('30 分钟'), findsOneWidget);
    expect(controller.saved.memoAdvanceMinutes, 10);
    expect(controller.saved.advanceMinutes, 30);
  });

  testWidgets('可以选择通知加震动但不播放声音', (tester) async {
    await tester.pumpWidget(
      _withSettings(
        const NotificationSettings(),
        const NotificationSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('提醒方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通知 + 震动'));
    await tester.pumpAndSettle();
    expect(find.text('通知 + 震动'), findsOneWidget);
  });

  testWidgets('国产 Android 引导显示通用设置和主流品牌路径', (tester) async {
    await tester.pumpWidget(
      _withSettings(const NotificationSettings(), const MagicOsGuidePage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('允许应用自动启动'), findsOneWidget);
    expect(find.text('忽略电池优化'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('各品牌常见路径'), 300);
    await tester.pumpAndSettle();
    expect(find.text('荣耀 · MagicOS'), findsOneWidget);
    expect(find.text('小米 / Redmi · HyperOS / MIUI'), findsOneWidget);
    expect(find.text('vivo / iQOO · OriginOS'), findsOneWidget);
    expect(find.text('我已设置好'), findsOneWidget);
  });
}

Widget _withSettings(NotificationSettings settings, Widget child) {
  return ProviderScope(
    overrides: [
      notificationSettingsProvider.overrideWith(
        () => _FakeSettingsController(settings),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

class _FakeSettingsController extends NotificationSettingsController {
  _FakeSettingsController(this.settings);
  final NotificationSettings settings;
  late NotificationSettings saved;

  @override
  Future<NotificationSettings> build() async {
    saved = settings;
    return settings;
  }

  @override
  Future<void> saveSettings(NotificationSettings settings) async {
    saved = settings;
    state = AsyncData(settings);
  }
}
