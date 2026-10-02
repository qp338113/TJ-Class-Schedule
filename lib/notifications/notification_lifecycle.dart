import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../application/task_state.dart';
import '../presentation/task_page.dart';
import '../widget/task_widget_service.dart';
import '../presentation/magic_os_guide_page.dart';
import '../presentation/tutorial_page.dart';
import '../widget/next_course_widget_service.dart';
import 'notification_service.dart';

class NotificationLifecycle extends ConsumerStatefulWidget {
  const NotificationLifecycle({
    required this.service,
    required this.child,
    this.initialDate,
    super.key,
  });

  final NotificationService service;
  final DateTime? initialDate;
  final Widget child;

  @override
  ConsumerState<NotificationLifecycle> createState() =>
      _NotificationLifecycleState();
}

class _NotificationLifecycleState extends ConsumerState<NotificationLifecycle>
    with WidgetsBindingObserver {
  StreamSubscription<DateTime>? _tapSubscription;
  StreamSubscription<String>? _taskTapSubscription;
  bool _startupFlowOpen = false;
  bool _syncing = false;
  bool _resyncRequested = false;
  bool _holidayChecked = false;
  final _widgetService = const NextCourseWidgetService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tapSubscription = widget.service.tappedDates.listen(_openDate);
    _taskTapSubscription = widget.service.tappedTasks.listen(_openTask);
    TaskWidgetService.channel.setMethodCallHandler((call) async {
      if (call.method == 'openTask') _openTask(call.arguments as String? ?? '');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialDate = widget.initialDate;
      if (initialDate != null) _openDate(initialDate);
      final initialTask =
          widget.service.initialTaskId ??
          await const TaskWidgetService().initialTask();
      if (initialTask != null) _openTask(initialTask);
      await widget.service.requestAndroidPermissions();
      await _syncNotifications();
      await _checkNationalMakeupDays();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncNotifications());
  }

  @override
  Widget build(BuildContext context) {
    final currentSettings = ref.watch(notificationSettingsProvider).valueOrNull;
    ref.watch(taskRepositoryProvider);
    ref.watch(taskReminderSettingsProvider);
    ref.listen(
      taskRepositoryProvider,
      (_, __) => unawaited(_syncNotifications()),
    );
    ref.listen(
      taskReminderSettingsProvider,
      (_, __) => unawaited(_syncNotifications()),
    );
    ref.listen(
      taskRevisionProvider,
      (_, __) => unawaited(_syncNotifications()),
    );
    if (currentSettings != null && !_startupFlowOpen) {
      if (!currentSettings.tutorialPromptCompleted) {
        _openTutorialPromptAfterBuild();
      } else if (!currentSettings.magicOsGuideCompleted) {
        _openGuideAfterBuild();
      }
    }
    ref.listen(
      scheduleControllerProvider,
      (_, __) => unawaited(_syncNotifications()),
    );
    ref.listen(notificationSettingsProvider, (_, next) {
      unawaited(_syncNotifications());
    });
    // 小组件颜色是它自己的设置，改完同样走上面那套同步把颜色推到桌面。
    ref.listen(widgetColorProvider, (_, __) {
      unawaited(_syncNotifications());
    });
    // 刷新频率要立刻推到原生侧，否则用户改完得等下次启动才生效。
    ref.listen(widgetRefreshModeProvider, (_, __) {
      unawaited(_syncNotifications());
    });
    return widget.child;
  }

  void _openGuideAfterBuild() {
    _startupFlowOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(builder: (_) => const MagicOsGuidePage()),
          )
          .then((_) {
            if (mounted) setState(() => _startupFlowOpen = false);
          });
    });
  }

  void _openTutorialPromptAfterBuild() {
    _startupFlowOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final shouldView = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('第一次使用，需要看看教程吗？'),
          content: const Text('教程会用简单步骤说明怎样添加学期、导入课表、设置提醒和桌面小组件。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不查看'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('查看教程'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      final settings = ref.read(notificationSettingsProvider).valueOrNull;
      if (settings != null) {
        await ref
            .read(notificationSettingsProvider.notifier)
            .saveSettings(settings.copyWith(tutorialPromptCompleted: true));
      }
      if (!mounted) return;
      if (shouldView == true) {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const TutorialPage()));
      }
      if (mounted) setState(() => _startupFlowOpen = false);
    });
  }

  Future<void> _syncNotifications() async {
    if (!mounted) return;
    if (_syncing) {
      _resyncRequested = true;
      return;
    }
    final schedule = ref.read(scheduleControllerProvider).valueOrNull;
    final settings = ref.read(notificationSettingsProvider).valueOrNull;
    if (schedule == null || settings == null) return;
    final widgetColor = ref.read(widgetColorProvider).valueOrNull;
    final refreshMode =
        ref.read(widgetRefreshModeProvider).valueOrNull ??
        WidgetRefreshModeController.defaultMode;
    _syncing = true;
    try {
      await widget.service.reschedule(schedule: schedule, settings: settings);
      final repository = ref.read(taskRepositoryProvider).valueOrNull;
      final taskSettings = ref.read(taskReminderSettingsProvider).valueOrNull;
      if (repository != null && taskSettings != null) {
        final tasks = await repository.loadVisible();
        await const TaskWidgetService().sync(tasks);
        await widget.service.rescheduleTasks(
          tasks: tasks,
          settings: taskSettings,
        );
      }
      await _widgetService.sync(
        schedule,
        colorValue: widgetColor,
        refreshMode: refreshMode,
      );
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通知或小组件更新失败，请检查系统通知权限后重新打开 App')),
        );
      }
    } finally {
      _syncing = false;
      if (_resyncRequested && mounted) {
        _resyncRequested = false;
        unawaited(_syncNotifications());
      }
    }
  }

  Future<void> _checkNationalMakeupDays() async {
    if (_holidayChecked || !mounted) return;
    _holidayChecked = true;
    try {
      await ref
          .read(scheduleControllerProvider.notifier)
          .checkNationalMakeupDays();
    } catch (_) {
      // 网络不可用时继续使用本机已保存的调休日期。
    }
  }

  void _openDate(DateTime date) {
    if (!mounted) return;
    ref.read(selectedDateProvider.notifier).state = date;
    ref.read(notificationNavigationRevisionProvider.notifier).state++;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openTask(String id) {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => TaskPage(initialTaskId: id.isEmpty ? null : id),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_tapSubscription?.cancel());
    unawaited(_taskTapSubscription?.cancel());
    TaskWidgetService.channel.setMethodCallHandler(null);
    unawaited(widget.service.dispose());
    super.dispose();
  }
}
