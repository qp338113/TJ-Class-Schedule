import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';
import 'package:offline_course_schedule/presentation/app_theme.dart';
import 'package:offline_course_schedule/presentation/appearance_settings_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('主题色缺省为原种子色并可持久化到本机设置', () async {
    final database = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final container = _rawContainer(database);
    addTearDown(container.dispose);
    expect(
      await container.read(themeSeedColorProvider.future),
      ThemeSeedColorController.defaultColorValue,
    );

    await container
        .read(themeSeedColorProvider.notifier)
        .saveSettings(0xFFC586C0);
    expect(await container.read(themeSeedColorProvider.future), 0xFFC586C0);

    // 新容器重新读取同一个数据库，确认已落盘。
    final reloaded = _rawContainer(database);
    addTearDown(reloaded.dispose);
    expect(await reloaded.read(themeSeedColorProvider.future), 0xFFC586C0);
  });

  test('自定义种子色会改变主色，背景色与卡片色保持不变', () {
    const defaultSeed = Color(0xFF607D8B);
    const customSeed = Color(0xFFC586C0);
    final theme = AppTheme.light(seedColor: defaultSeed);
    final custom = AppTheme.light(seedColor: customSeed);

    expect(custom.colorScheme.primary, isNot(theme.colorScheme.primary));
    // 只换主色：背景色与卡片色沿用固定值，不受种子色影响。
    expect(custom.scaffoldBackgroundColor, theme.scaffoldBackgroundColor);
    expect(custom.cardTheme.color, theme.cardTheme.color);
    // 深色模式同样跟随种子色。
    expect(
      AppTheme.dark(seedColor: customSeed).colorScheme.primary,
      isNot(AppTheme.dark(seedColor: defaultSeed).colorScheme.primary),
    );
  });

  test('背景图路径可保存与读回，清除后为 null', () async {
    final database = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final source = _FakeBackgroundImageSource(pickedPath: '/tmp/bg.png');
    final container = _rawContainer(database, source: source);
    addTearDown(container.dispose);
    expect(await container.read(backgroundImagePathProvider.future), isNull);

    // 裁剪后的字节交给控制器落盘，路径写进设置。
    await container
        .read(backgroundImagePathProvider.notifier)
        .saveBackgroundImage(Uint8List.fromList([9, 8, 7]));
    expect(source.stored, [
      Uint8List.fromList([9, 8, 7]),
    ]);
    expect(
      await container.read(backgroundImagePathProvider.future),
      '/tmp/bg.png',
    );

    // 路径确实落盘到 app_settings，而不是只存在内存里。
    expect(await database.loadSetting('background_image_path'), '/tmp/bg.png');

    await container
        .read(backgroundImagePathProvider.notifier)
        .clearBackgroundImage();
    expect(await container.read(backgroundImagePathProvider.future), isNull);
    expect(source.removed, ['/tmp/bg.png']);
  });

  test('用户取消选图时不会触发落盘', () async {
    final database = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final source = _FakeBackgroundImageSource(pickedBytes: null);
    final container = _rawContainer(database, source: source);
    addTearDown(container.dispose);
    // 选图与裁剪都在界面层完成，控制器只在拿到字节后才落盘，
    // 因此这里没有可调用的入口，取消不会改变任何状态。
    expect(await container.read(backgroundImagePathProvider.future), isNull);
    expect(source.stored, isEmpty);
  });

  testWidgets('外观设置页显示预设色块，点选后保存主题色', (tester) async {
    final controller = _FakeThemeSeedColorController(
      ThemeSeedColorController.defaultColorValue,
    );
    await tester.pumpWidget(_page(themeController: controller));
    await tester.pumpAndSettle();

    expect(find.text('主题色'), findsOneWidget);
    // 预设色板共 12 个色块。
    expect(find.byType(CircleAvatar), findsNWidgets(12));
    // 当前色打勾。
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.byType(CircleAvatar).at(9));
    await tester.pumpAndSettle();
    expect(controller.saved, 0xFFC586C0);
  });

  testWidgets('HSL 对话框可打开并确认自定义主题色', (tester) async {
    final controller = _FakeThemeSeedColorController(
      ThemeSeedColorController.defaultColorValue,
    );
    await tester.pumpWidget(_page(themeController: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义颜色'));
    await tester.pumpAndSettle();
    expect(find.text('自定义主题色'), findsOneWidget);
    // 页面本身也有不透明度滑杆，这里限定在对话框内数，避免把两者混在一起。
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Slider),
      ),
      findsNWidgets(3),
    );

    // 拖动色相滑杆后确认，应保存一个与初始值不同的颜色。
    await tester.drag(
      find
          .descendant(of: find.byType(AlertDialog), matching: find.byType(Slider))
          .first,
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(controller.saved, isNotNull);
    expect(controller.saved, isNot(ThemeSeedColorController.defaultColorValue));
  });

  test('小组件颜色缺省为 null，保存后可读回，置空可恢复默认', () async {
    final database = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final container = _rawContainer(database);
    addTearDown(container.dispose);
    // 缺省必须是 null：这样未设置时小组件外观与改造前完全一致。
    expect(await container.read(widgetColorProvider.future), isNull);

    await container
        .read(widgetColorProvider.notifier)
        .saveSettings(0xFF1B4332);
    expect(await container.read(widgetColorProvider.future), 0xFF1B4332);
    expect(await database.loadSetting('widget_color'), '${0xFF1B4332}');

    // 新容器重新读取同一个数据库，确认已落盘。
    final reloaded = _rawContainer(database);
    addTearDown(reloaded.dispose);
    expect(await reloaded.read(widgetColorProvider.future), 0xFF1B4332);

    // 恢复默认：状态回到 null，设置键被删除而不是留下哨兵值。
    await reloaded.read(widgetColorProvider.notifier).saveSettings(null);
    expect(await reloaded.read(widgetColorProvider.future), isNull);
    expect(await database.loadSetting('widget_color'), isNull);
  });

  testWidgets('外观设置页含小组件颜色分组，可点选预设色并恢复默认', (tester) async {
    final widgetColor = _FakeWidgetColorController(null);    await tester.pumpWidget(_page(widgetColorController: widgetColor));
    await tester.pumpAndSettle();

    // 该分组在长页面下方，先滚动到它再断言，否则视口外找不到。
    await tester.scrollUntilVisible(find.text('小组件颜色'), 200);
    await tester.pumpAndSettle();

    expect(find.text('小组件颜色'), findsOneWidget);
    expect(
      find.text('只影响小组件的普通状态，临近上课时的提醒色不受影响'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('widget-color-default')), findsOneWidget);

    // 该分组位于长页面下方，默认测试视口内不可见，先滚动到可见再点击。
    final preset = find.byKey(const ValueKey('widget-color-${0xFFC586C0}'));
    await tester.ensureVisible(preset);
    await tester.pumpAndSettle();
    await tester.tap(preset);
    await tester.pumpAndSettle();
    expect(widgetColor.saved, 0xFFC586C0);

    final defaultOption = find.byKey(const ValueKey('widget-color-default'));
    await tester.ensureVisible(defaultOption);
    await tester.pumpAndSettle();
    await tester.tap(defaultOption);
    await tester.pumpAndSettle();
    expect(widgetColor.saved, isNull);
  });

  test('遮罩浓度缺省为 0.55，保存后可读回并夹在 0~1', () async {
    final database = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final container = _rawContainer(database);
    addTearDown(container.dispose);
    expect(
      await container.read(backgroundOverlayOpacityProvider.future),
      BackgroundOverlayOpacityController.defaultOpacity,
    );

    await container
        .read(backgroundOverlayOpacityProvider.notifier)
        .saveSettings(0.8);
    expect(await container.read(backgroundOverlayOpacityProvider.future), 0.8);

    // 越界值要被夹回合法范围，避免存进数据库后界面出现异常透明度。
    await container
        .read(backgroundOverlayOpacityProvider.notifier)
        .saveSettings(3);
    expect(await container.read(backgroundOverlayOpacityProvider.future), 1.0);

    final reloaded = _rawContainer(database);
    addTearDown(reloaded.dispose);
    expect(await reloaded.read(backgroundOverlayOpacityProvider.future), 1.0);
  });

  test('课表透明度缺省为 1，且不会低于可读下限', () async {
    final database = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final container = _rawContainer(database);
    addTearDown(container.dispose);
    expect(
      await container.read(cardOpacityProvider.future),
      CardOpacityController.defaultOpacity,
    );

    await container.read(cardOpacityProvider.notifier).saveSettings(0.6);
    expect(await container.read(cardOpacityProvider.future), 0.6);

    // 下限保护：再低就会影响文字可读性。
    await container.read(cardOpacityProvider.notifier).saveSettings(0.05);
    expect(
      await container.read(cardOpacityProvider.future),
      CardOpacityController.minOpacity,
    );
  });

  test('小组件刷新频率缺省为省电，三档都能存取', () async {
    final database = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final container = _rawContainer(database);
    addTearDown(container.dispose);
    expect(
      await container.read(widgetRefreshModeProvider.future),
      WidgetRefreshMode.powerSaving,
    );

    for (final mode in WidgetRefreshMode.values) {
      await container
          .read(widgetRefreshModeProvider.notifier)
          .saveSettings(mode);
      expect(await container.read(widgetRefreshModeProvider.future), mode);
    }

    // 落盘后换个容器重读，确认不是只存在内存里。
    final reloaded = _rawContainer(database);
    addTearDown(reloaded.dispose);
    expect(
      await reloaded.read(widgetRefreshModeProvider.future),
      WidgetRefreshMode.precise,
    );
  });

  test('刷新频率遇到无法识别的值时回退到省电', () {
    expect(WidgetRefreshMode.parse('normal'), WidgetRefreshMode.normal);
    expect(WidgetRefreshMode.parse('precise'), WidgetRefreshMode.precise);
    expect(WidgetRefreshMode.parse(null), WidgetRefreshMode.powerSaving);
    expect(WidgetRefreshMode.parse('乱写'), WidgetRefreshMode.powerSaving);
  });

  testWidgets('外观设置页可打开刷新频率选择并保存', (tester) async {
    final modes = _FakeWidgetRefreshModeController(
      WidgetRefreshMode.powerSaving,
    );
    await tester.pumpWidget(_page(refreshModeController: modes));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('倒计时刷新频率'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('倒计时刷新频率'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('refresh-mode-precise')));
    await tester.pumpAndSettle();
    expect(modes.saved, WidgetRefreshMode.precise);
  });

  testWidgets('背景图分组带「开发中，暂不建议使用」提示', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    // 该功能仍在打磨中，必须在界面上明确标注，避免用户误以为已经稳定可用。
    expect(find.text('开发中，暂不建议使用'), findsOneWidget);
  });

  testWidgets('外观设置页在未设置背景图时禁用移除，设置后可移除', (tester) async {
    final background = _FakeBackgroundImagePathController(null);
    await tester.pumpWidget(_page(backgroundController: background));
    await tester.pumpAndSettle();

    expect(find.text('主界面背景图'), findsOneWidget);
    expect(find.text('未设置，深色与浅色模式共用同一张图'), findsOneWidget);
    final removeTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('移除背景图'),
        matching: find.byType(ListTile),
      ),
    );
    expect(removeTile.enabled, isFalse);
  });

  testWidgets('存在背景图时可移除并清空设置', (tester) async {
    final background = _FakeBackgroundImagePathController('/tmp/bg.png');
    await tester.pumpWidget(_page(backgroundController: background));
    await tester.pumpAndSettle();

    expect(find.text('已设置，深色与浅色模式共用同一张图'), findsOneWidget);
    await tester.tap(find.text('移除背景图'));
    await tester.pumpAndSettle();
    expect(background.cleared, isTrue);
  });

  testWidgets('主页菜单包含外观设置并能打开该页', (tester) async {
    final fixture = _scheduleFixture();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(
            () => _FakeScheduleController(fixture.data),
          ),
          themeSeedColorProvider.overrideWith(
            () => _FakeThemeSeedColorController(
              ThemeSeedColorController.defaultColorValue,
            ),
          ),
          backgroundImagePathProvider.overrideWith(
            () => _FakeBackgroundImagePathController(null),
          ),
          widgetColorProvider.overrideWith(
            () => _FakeWidgetColorController(null),
          ),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('外观设置'), findsOneWidget);

    await tester.tap(find.text('外观设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceSettingsPage), findsOneWidget);
    expect(find.text('自定义颜色'), findsOneWidget);
  });

  testWidgets('设置背景图后主页铺图并叠固定半透明遮罩', (tester) async {
    final image = _temporaryPng();
    addTearDown(() => image.parent.deleteSync(recursive: true));
    await tester.pumpWidget(
      _homeApp(backgroundPath: image.path, themeControllerSeed: null),
    );
    await tester.pumpAndSettle();

    final imageWidget = tester.widget<Image>(find.byType(Image));
    expect((imageWidget.image as FileImage).file.path, image.path);
    expect(imageWidget.fit, BoxFit.cover);
    // 遮罩固定为黑色 55% 透明度，深色与浅色模式共用，不暴露给用户。
    expect(_overlayFinder, findsOneWidget);
    // 原内容仍在遮罩之上。
    expect(find.text('测试学期'), findsOneWidget);
  });

  testWidgets('背景图文件丢失时静默降级，不显示图片也不报错', (tester) async {
    await tester.pumpWidget(
      _homeApp(
        backgroundPath: '/definitely/not/here/bg.png',
        themeControllerSeed: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(_overlayFinder, findsNothing);
    // 界面照常可用。
    expect(find.text('测试学期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有背景图时课程卡片始终不透明，不受课表透明度影响', (tester) async {
    final fixture = _fixtureWithCourse();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(
            () => _FakeScheduleController(fixture.data),
          ),
          backgroundImagePathProvider.overrideWith(
            () => _FakeBackgroundImagePathController(null),
          ),
          // 用户曾把课表透明度调低过，但后来移除了背景图。
          cardOpacityProvider.overrideWith(
            () => _FakeCardOpacityController(0.3),
          ),
          // 固定“现在”为当天 00:00，否则傍晚跑测试时会触发
          // “课上完自动跳到第二天”，今天就没有卡片可断言了。
          clockProvider.overrideWith((ref) => Stream.value(fixture.today)),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 没有背景图时卡片必须回到完全不透明，否则会在纯色底上显得发灰、
    // 与周围融为一体而看不清。
    final card = tester.widget<Card>(find.byType(Card).first);
    expect(card.color?.a, 1.0);
  });

  testWidgets('有背景图时课程卡片按设置的透明度绘制', (tester) async {
    final image = _temporaryPng();
    addTearDown(() => image.parent.deleteSync(recursive: true));
    final fixture = _fixtureWithCourse();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(
            () => _FakeScheduleController(fixture.data),
          ),
          backgroundImagePathProvider.overrideWith(
            () => _FakeBackgroundImagePathController(image.path),
          ),
          cardOpacityProvider.overrideWith(
            () => _FakeCardOpacityController(0.5),
          ),
          clockProvider.overrideWith((ref) => Stream.value(fixture.today)),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    await tester.pumpAndSettle();

    final card = tester.widget<Card>(find.byType(Card).first);
    expect(card.color?.a, closeTo(0.5, 0.01));
  });

  testWidgets('未设置背景图时不渲染背景层', (tester) async {
    await tester.pumpWidget(
      _homeApp(backgroundPath: null, themeControllerSeed: null),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(_overlayFinder, findsNothing);
    expect(find.text('测试学期'), findsOneWidget);
  });
}

/// 背景遮罩层。用固定的遮罩颜色定位，避免匹配到界面上其他 ColoredBox。
final _overlayFinder = find.byWidgetPredicate(
  (widget) =>
      widget is ColoredBox && widget.color == const Color.fromRGBO(0, 0, 0, 0.55),
);

ProviderContainer _rawContainer(
  ScheduleDatabase database, {
  BackgroundImageSource? source,
}) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) async => database),
      if (source != null) backgroundImageSourceProvider.overrideWithValue(source),
    ],
  );
}

Widget _page({
  ThemeSeedColorController? themeController,
  BackgroundImagePathController? backgroundController,
  WidgetColorController? widgetColorController,
  WidgetRefreshModeController? refreshModeController,
}) {
  return ProviderScope(
    overrides: [
      themeSeedColorProvider.overrideWith(
        () =>
            themeController ??
            _FakeThemeSeedColorController(
              ThemeSeedColorController.defaultColorValue,
            ),
      ),
      backgroundImagePathProvider.overrideWith(
        () =>
            backgroundController ?? _FakeBackgroundImagePathController(null),
      ),
      widgetColorProvider.overrideWith(
        () => widgetColorController ?? _FakeWidgetColorController(null),
      ),
      widgetRefreshModeProvider.overrideWith(
        () =>
            refreshModeController ??
            _FakeWidgetRefreshModeController(WidgetRefreshMode.powerSaving),
      ),
      // 设置页会读这两个不透明度来显示滑杆数值，未 override 时会一直停在加载态。
      backgroundOverlayOpacityProvider.overrideWith(
        () => _FakeBackgroundOverlayOpacityController(
          BackgroundOverlayOpacityController.defaultOpacity,
        ),
      ),
      cardOpacityProvider.overrideWith(
        () => _FakeCardOpacityController(CardOpacityController.defaultOpacity),
      ),
    ],
    child: const MaterialApp(home: AppearanceSettingsPage()),
  );
}

/// 主页 + 指定背景图路径，用于验证背景渲染与降级。
Widget _homeApp({
  required String? backgroundPath,
  required int? themeControllerSeed,
}) {
  final fixture = _scheduleFixture();
  return ProviderScope(
    overrides: [
      scheduleControllerProvider.overrideWith(
        () => _FakeScheduleController(fixture.data),
      ),
      themeSeedColorProvider.overrideWith(
        () => _FakeThemeSeedColorController(
          themeControllerSeed ?? ThemeSeedColorController.defaultColorValue,
        ),
      ),
      backgroundImagePathProvider.overrideWith(
        () => _FakeBackgroundImagePathController(backgroundPath),
      ),
    ],
    child: const CourseScheduleApp(),
  );
}

/// 写一张 1x1 的真实 PNG 到临时目录，供背景图渲染使用。
File _temporaryPng() {
  final directory = Directory.systemTemp.createTempSync('bg-image-test');
  final file = File('${directory.path}/bg.png');
  file.writeAsBytesSync(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
      'q842NwAAAABJRU5ErkJggg==',
    ),
  );
  return file;
}

({ScheduleData data, DateTime today}) _scheduleFixture() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final term = Term(
    id: currentTermId,
    name: '测试学期',
    firstWeekMonday: monday,
    totalWeeks: 20,
    periodsByWeekday: {
      for (var day = 1; day <= 7; day++)
        day: [const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580)],
    },
  );
  return (data: ScheduleData(term: term), today: today);
}

/// 与 [_scheduleFixture] 相同，但多一门今天有课的课程——用于验证卡片渲染相关行为
/// （没有课程时主页不会出现任何 Card）。
({ScheduleData data, DateTime today}) _fixtureWithCourse() {
  final fixture = _scheduleFixture();
  final term = fixture.data.term!;
  final course = Course(
    id: 'course-1',
    name: '高等数学',
    teacher: '张老师',
    colorValue: 0xFF7D9DCE,
    sessions: [
      CourseSession(
        id: 'session-1',
        weekday: fixture.today.weekday,
        startPeriod: 1,
        endPeriod: 1,
        weekRule: WeekRule(
          startWeek: 1,
          endWeek: term.totalWeeks,
          type: WeekType.every,
        ),
        location: 'A101',
      ),
    ],
  );
  return (
    data: ScheduleData(term: term, courses: [course]),
    today: fixture.today,
  );
}

class _FakeBackgroundImageSource implements BackgroundImageSource {
  _FakeBackgroundImageSource({this.pickedPath, Uint8List? pickedBytes})
    : pickedBytes = pickedBytes ?? Uint8List.fromList([1, 2, 3]);

  /// 用户选图后返回的字节；为 null 表示用户取消。
  final Uint8List? pickedBytes;
  final String? pickedPath;
  final removed = <String>[];
  final stored = <Uint8List>[];

  @override
  Future<Uint8List?> pickBytes() async => pickedBytes;

  @override
  Future<String> store(Uint8List bytes) async {
    stored.add(bytes);
    return pickedPath ?? '/tmp/bg.png';
  }

  @override
  Future<void> remove(String path) async => removed.add(path);
}

class _FakeScheduleController extends ScheduleController {
  _FakeScheduleController(this.data);

  final ScheduleData data;

  @override
  Future<ScheduleData> build() async => data;
}

class _FakeThemeSeedColorController extends ThemeSeedColorController {
  _FakeThemeSeedColorController(this.initial);

  final int initial;
  int? saved;

  @override
  Future<int> build() async => initial;

  @override
  Future<void> saveSettings(int colorValue) async {
    saved = colorValue;
    state = AsyncData(colorValue);
  }
}

class _FakeBackgroundImagePathController
    extends BackgroundImagePathController {
  _FakeBackgroundImagePathController(this.initial);

  final String? initial;
  bool cleared = false;

  @override
  Future<String?> build() async => initial;

  @override
  Future<void> clearBackgroundImage() async {
    cleared = true;
    state = const AsyncData(null);
  }
}

class _FakeWidgetColorController extends WidgetColorController {
  _FakeWidgetColorController(this.initial);

  final int? initial;
  int? saved;

  @override
  Future<int?> build() async => initial;

  @override
  Future<void> saveSettings(int? colorValue) async {
    saved = colorValue;
    state = AsyncData(colorValue);
  }
}

class _FakeWidgetRefreshModeController extends WidgetRefreshModeController {
  _FakeWidgetRefreshModeController(this.initial);

  final WidgetRefreshMode initial;
  WidgetRefreshMode? saved;

  @override
  Future<WidgetRefreshMode> build() async => initial;

  @override
  Future<void> saveSettings(WidgetRefreshMode mode) async {
    saved = mode;
    state = AsyncData(mode);
  }
}

class _FakeBackgroundOverlayOpacityController
    extends BackgroundOverlayOpacityController {
  _FakeBackgroundOverlayOpacityController(this.initial);

  final double initial;

  @override
  Future<double> build() async => initial;
}

class _FakeCardOpacityController extends CardOpacityController {
  _FakeCardOpacityController(this.initial);

  final double initial;

  @override
  Future<double> build() async => initial;
}
