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
    expect(find.text('30 分钟'), findsOneWidget);
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

  @override
  Future<NotificationSettings> build() async => settings;

  @override
  Future<void> saveSettings(NotificationSettings settings) async {
    state = AsyncData(settings);
  }
}
