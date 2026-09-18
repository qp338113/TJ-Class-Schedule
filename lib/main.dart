import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/schedule_controller.dart';
import 'application/startup_date.dart';
import 'domain/schedule_engine.dart';
import 'notifications/notification_lifecycle.dart';
import 'notifications/notification_service.dart';
import 'presentation/app_theme.dart';
import 'presentation/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationService = NotificationService();
  final initialDate = await notificationService.initialize();
  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: CourseScheduleApp(
        notificationService: notificationService,
        initialDate: initialDate,
      ),
    ),
  );
}

class CourseScheduleApp extends ConsumerStatefulWidget {
  const CourseScheduleApp({
    super.key,
    this.notificationService,
    this.initialDate,
  });

  final NotificationService? notificationService;
  final DateTime? initialDate;

  @override
  ConsumerState<CourseScheduleApp> createState() => _CourseScheduleAppState();
}

class _CourseScheduleAppState extends ConsumerState<CourseScheduleApp> {
  @override
  void initState() {
    super.initState();
    unawaited(_applyStartupDate());
  }

  /// 启动后判定一次：今天的课都上完了就把选中日期直接挪到第二天。
  ///
  /// 刻意放在 initState 而不是 build 里：build 每次重建都会跑，用户手动滑到别的
  /// 日期后会被抢回来。这里只执行一次，之后完全交给用户操作。也不监听 App 回到
  /// 前台，避免重新进 App 时又跳一次。学期未配置或数据加载失败时静默跳过。
  Future<void> _applyStartupDate() async {
    // 用户点通知冷启动时带着明确的日期意图，此时不要覆盖成「第二天」。
    if (widget.initialDate != null) return;
    try {
      final data = await ref.read(scheduleControllerProvider.future);
      final term = data.term;
      if (term == null || !mounted) return;
      final now = await ref.read(clockProvider.future);
      final next = startupSelectedDate(
        ScheduleEngine(
          term: term,
          courses: data.courses,
          memos: data.memos,
          adjustments: data.adjustments,
          cancellations: data.cancellations,
        ),
        now,
      );
      if (next == null || !mounted) return;
      ref.read(selectedDateProvider.notifier).state = next;
    } catch (_) {
      // 课表还没加载好或读取失败时保持原有行为，不打扰用户。
    }
  }

  @override
  Widget build(BuildContext context) {
    // 设置尚未加载完成时先用缺省种子色，避免启动瞬间闪一下主题。
    final seedColor = Color(
      ref.watch(themeSeedColorProvider).valueOrNull ??
          ThemeSeedColorController.defaultColorValue,
    );
    return MaterialApp(
      title: 'TJ Class Schedule',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(seedColor: seedColor),
      darkTheme: AppTheme.dark(seedColor: seedColor),
      themeMode: ThemeMode.system,
      home: widget.notificationService == null
          ? const HomePage()
          : NotificationLifecycle(
              service: widget.notificationService!,
              initialDate: widget.initialDate,
              child: const HomePage(),
            ),
    );
  }
}
