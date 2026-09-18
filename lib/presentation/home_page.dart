import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../domain/schedule_engine.dart';
import '../domain/schedule_models.dart';
import 'appearance_settings_page.dart';
import 'course_detail_sheet.dart';
import 'data_management_page.dart';
import 'full_timetable_page.dart';
import 'import_preview_page.dart';
import 'manual_course_page.dart';
import 'notification_settings_page.dart';
import 'term_setup_page.dart';
import 'tongji_timetable_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleControllerProvider);
    return schedule.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(scheduleControllerProvider),
            child: const Text('加载失败，点击重试'),
          ),
        ),
      ),
      data: (data) => data.term == null
          ? _WelcomePage(
              onSetup: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const TermSetupPage()),
              ),
            )
          : _ScheduleHome(data: data),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onSetup});

  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, size: 38),
                ),
                const SizedBox(height: 24),
                Text(
                  '先设置你的学期',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  '只需填写开学日期、总周数和每天的节次时间，所有数据都会保存在本机。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(onPressed: onSetup, child: const Text('开始设置')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleHome extends ConsumerWidget {
  const _ScheduleHome({required this.data});

  final ScheduleData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = data.term!;
    final selectedDate = ref.watch(selectedDateProvider);
    final navigationRevision = ref.watch(
      notificationNavigationRevisionProvider,
    );
    final swipeAdvancesWeek =
        ref.watch(swipeAdvancesWeekProvider).valueOrNull ?? false;
    final slideDirection = ref.watch(_dateChangeDirectionProvider);
    final backgroundPath = ref.watch(backgroundImagePathProvider).valueOrNull;
    final overlayOpacity =
        ref.watch(backgroundOverlayOpacityProvider).valueOrNull ??
        BackgroundOverlayOpacityController.defaultOpacity;
    final engine = ScheduleEngine(
      term: term,
      courses: data.courses,
      memos: data.memos,
      adjustments: data.adjustments,
      cancellations: data.cancellations,
    );
    // 有背景图时整屏铺满：图片铺在 Scaffold 外层，标题栏与页面底色改透明即可透出，
    // 不需要 extendBodyBehindAppBar——那会把 body 顶到 y=0，内容钻到标题栏下面。
    final hasBackground =
        backgroundPath != null && File(backgroundPath).existsSync();
    return DefaultTabController(
      key: ValueKey(navigationRevision),
      length: 2,
      child: _BackgroundImage(
        path: backgroundPath,
        overlayOpacity: overlayOpacity,
        child: Scaffold(
          backgroundColor: hasBackground ? Colors.transparent : null,
          // Scaffold 按 endFloat 定位悬浮按钮，只保证「右边缘距屏幕 16」。
          // Row 若撑满整屏（默认 mainAxisSize.max），左端就会被推到屏幕外裁掉，
          // 两个按钮看起来不对称。这里把宽度收成「屏宽 - 左右各 16」，
          // 让左右留白一致。
          floatingActionButton: SizedBox(
            width: MediaQuery.sizeOf(context).width -
                2 * kFloatingActionButtonMargin,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 左下角：整周课表。与右下角的“添加课程”左右对称。
                FloatingActionButton.extended(
                  heroTag: 'full_timetable_fab',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => FullTimetablePage(
                        term: term,
                        courses: data.courses,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text('整周课表'),
                ),
                FloatingActionButton.extended(
                  heroTag: 'add_course_fab',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ManualCoursePage(term: term),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加课程'),
                ),
              ],
            ),
          ),
        appBar: AppBar(
          // 有背景图时不能用全透明：标题与“今日/本周”标签会直接压在图片上，
          // 遇到深色或花哨的图就完全看不清。改用带透明度的表面色——图片仍能透出，
          // 文字始终清晰。（AppBar 的 bottom 是 TabBar，一并被这层底色覆盖。）
          backgroundColor: hasBackground
              ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.72)
              : null,
          elevation: hasBackground ? 0 : null,
          scrolledUnderElevation: hasBackground ? 0 : null,
          title: Text(term.name),
          actions: [
            IconButton(
              tooltip: '导入课表',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const ImportPreviewPage(),
                ),
              ),
              icon: const Icon(Icons.file_upload_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'term') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => TermSetupPage(initialTerm: term),
                    ),
                  );
                } else if (value == 'notifications') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationSettingsPage(),
                    ),
                  );
                } else if (value == 'makeup') {
                  _checkMakeupDays(context, ref);
                } else if (value == 'tongji') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const TongjiTimetablePage(),
                    ),
                  );
                } else if (value == 'undo_import') {
                  _undoImport(context, ref);
                } else if (value == 'backup') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const DataManagementPage(),
                    ),
                  );
                } else if (value == 'swipe_mode') {
                  _toggleSwipeMode(ref, swipeAdvancesWeek);
                } else if (value == 'appearance') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AppearanceSettingsPage(),
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'tongji', child: Text('从同济1系统导入')),
                const PopupMenuItem(value: 'notifications', child: Text('提醒设置')),
                const PopupMenuItem(value: 'makeup', child: Text('检查国家调休')),
                const PopupMenuItem(value: 'undo_import', child: Text('撤销上次导入')),
                const PopupMenuItem(value: 'backup', child: Text('备份与恢复')),
                const PopupMenuItem(value: 'term', child: Text('编辑学期与节次')),
                PopupMenuItem(
                  value: 'swipe_mode',
                  child: Text(
                    swipeAdvancesWeek ? '滑动切换：一周' : '滑动切换：一天',
                  ),
                ),
                const PopupMenuItem(value: 'appearance', child: Text('外观设置')),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '今日'),
              Tab(text: '本周'),
            ],
          ),
        ),
        body: Column(
          children: [
            _DateHeader(
              date: selectedDate,
              week: engine.getWeekForDate(selectedDate),
              hasBackground: hasBackground,
              onPrevious: () => _changeDate(ref, selectedDate, -1),
              onNext: () => _changeDate(ref, selectedDate, 1),
              onToday: () => ref.read(selectedDateProvider.notifier).state =
                  _dateOnly(DateTime.now()),
              onSelectWeek: () => _selectWeek(context, ref, term, selectedDate),
            ),
            if (engine.adjustmentForDate(selectedDate) case final adjustment?)
              _AdjustmentBanner(
                date: selectedDate,
                actualWeek: engine.getWeekForDate(selectedDate),
                adjustment: adjustment,
                term: term,
              ),
            Expanded(
              child: GestureDetector(
                // 左右滑动切换日期；标签页自带的滑动已关闭，改由点顶部 Tab 切换。
                onHorizontalDragEnd: (details) => _handleSwipe(
                  ref,
                  selectedDate,
                  details.primaryVelocity ?? 0,
                  swipeAdvancesWeek,
                ),
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _SlideOnDateChange(
                      dateKey: selectedDate,
                      direction: slideDirection,
                      child: _TodayView(
                        date: selectedDate,
                        courses: engine.getEntriesForDate(selectedDate),
                      ),
                    ),
                    _SlideOnDateChange(
                      dateKey: selectedDate,
                      direction: slideDirection,
                      child: _WeekView(
                        selectedDate: selectedDate,
                        engine: engine,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 6),
              child: const _PoweredByFooter(),
            ),
          ],
        ),
      ),
    ),
  );
}

  void _changeDate(WidgetRef ref, DateTime date, int days) {
    // 记下方向，供日期内容做横向滑入动画。
    ref.read(_dateChangeDirectionProvider.notifier).state = days >= 0 ? 1 : -1;
    ref.read(selectedDateProvider.notifier).state = date.add(
      Duration(days: days),
    );
  }

  /// 按滑动方向切换日期：向左滑（primaryVelocity < 0）前进，向右滑后退。
  /// 速度绝对值不足阈值时视为误触，不做任何切换。
  void _handleSwipe(
    WidgetRef ref,
    DateTime date,
    double primaryVelocity,
    bool swipeAdvancesWeek,
  ) {
    const velocityThreshold = 200.0;
    if (primaryVelocity.abs() < velocityThreshold) return;
    final days = (swipeAdvancesWeek ? 7 : 1) * (primaryVelocity < 0 ? 1 : -1);
    _changeDate(ref, date, days);
  }

  /// 在“滑一天”和“滑一周”之间切换，并写入本机设置。
  void _toggleSwipeMode(WidgetRef ref, bool swipeAdvancesWeek) {
    ref
        .read(swipeAdvancesWeekProvider.notifier)
        .saveSettings(!swipeAdvancesWeek);
  }

  Future<void> _selectWeek(
    BuildContext context,
    WidgetRef ref,
    Term term,
    DateTime selectedDate,
  ) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('快速切换教学周'),
              subtitle: Text('会跳到所选教学周中相同的星期。'),
            ),
            for (var week = 1; week <= term.totalWeeks; week++)
              ListTile(
                title: Text('第 $week 周'),
                onTap: () => Navigator.pop(context, week),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final weekdayOffset = selectedDate.weekday - DateTime.monday;
    ref.read(selectedDateProvider.notifier).state = term.firstWeekMonday.add(
      Duration(days: (selected - 1) * 7 + weekdayOffset),
    );
  }

  Future<void> _checkMakeupDays(BuildContext context, WidgetRef ref) async {
    try {
      final count = await ref
          .read(scheduleControllerProvider.notifier)
          .checkNationalMakeupDays();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0 ? '当前学期没有可更新的国家节假日数据' : '已更新国家节假日与调休，共识别 $count 个调休上班日',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('联网检查失败，已保留本机调休数据')));
    }
  }

  Future<void> _undoImport(BuildContext context, WidgetRef ref) async {
    try {
      final restored = await ref
          .read(scheduleControllerProvider.notifier)
          .undoLastImport();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restored ? '已恢复到导入前的课表' : '没有可以撤销的导入')),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('撤销失败，请重试')));
      }
    }
  }
}

class _AdjustmentBanner extends ConsumerWidget {
  const _AdjustmentBanner({
    required this.date,
    required this.actualWeek,
    required this.adjustment,
    required this.term,
  });

  final DateTime date;
  final int? actualWeek;
  final ScheduleAdjustment adjustment;
  final Term term;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekday = adjustment.replacementWeekday;
    final replacementWeek = adjustment.replacementWeek;
    final hasReplacement = weekday != null && replacementWeek != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            adjustment.isHoliday
                ? Icons.celebration_outlined
                : Icons.event_repeat_rounded,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              adjustment.isHoliday
                  ? '国家法定节假日：${adjustment.holidayName ?? '放假'}，今天不显示课程'
                  : !hasReplacement
                  ? '今天是国家调休上班日，请选择要补哪一天的课'
                  : '调休提示：今天补第 $replacementWeek 周'
                        '${_weekdayName(weekday)}的课'
                        '${actualWeek == null ? '' : '（实际日期是第 $actualWeek 周）'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (!adjustment.isHoliday) ...[
            if (hasReplacement)
              TextButton(
                onPressed: () => ref
                    .read(scheduleControllerProvider.notifier)
                    .clearReplacementSchedule(date),
                child: const Text('取消'),
              ),
            TextButton(
              onPressed: () => _selectReplacement(context, ref),
              child: Text(hasReplacement ? '修改' : '设置'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selectReplacement(BuildContext context, WidgetRef ref) async {
    // 学期可能被改短，旧的替代周次会超出范围；夹回有效区间，否则下拉框找不到
    // 匹配项会断言失败，日期选择器的 initialDate 也会越界。
    var selectedWeek = (adjustment.replacementWeek ?? actualWeek ?? 1).clamp(
      1,
      term.totalWeeks,
    );
    var selectedWeekday = adjustment.replacementWeekday ?? date.weekday;
    final selected = await showDialog<({int week, int weekday})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 选了日期就自动对应教学周和星期，反过来改下拉框也会刷新这里的日期。
          final sourceDate = term.dateOf(selectedWeek, selectedWeekday);
          return AlertDialog(
            title: const Text('设置补课课表'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('按学校通知选出“要补哪一天”的课程，教学周和星期会自动对应。'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: sourceDate,
                      firstDate: term.firstWeekMonday,
                      lastDate: term.lastDay,
                      helpText: '选择要补的课程原本的日期',
                    );
                    if (picked == null) return;
                    final week = term.weekOf(picked);
                    if (week == null) return;
                    setDialogState(() {
                      selectedWeek = week;
                      selectedWeekday = picked.weekday;
                    });
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    '${sourceDate.month}月${sourceDate.day}日'
                    '（${_weekdayName(sourceDate.weekday)}）',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  // DropdownButtonFormField 的值存在 FormFieldState 里，而
                  // FormField.didUpdateWidget 不会因 initialValue 变化而同步它。
                  // 用 key 让选完日期后整个下拉框重建，显示才会跟着更新。
                  key: ValueKey('week-$selectedWeek'),
                  initialValue: selectedWeek,
                  decoration: const InputDecoration(labelText: '教学周'),
                  items: [
                    for (var week = 1; week <= term.totalWeeks; week++)
                      DropdownMenuItem(value: week, child: Text('第 $week 周')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedWeek = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('weekday-$selectedWeekday'),
                  initialValue: selectedWeekday,
                  decoration: const InputDecoration(labelText: '星期'),
                  items: [
                    for (var day = 1; day <= 7; day++)
                      DropdownMenuItem(
                        value: day,
                        child: Text(_weekdayName(day)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedWeekday = value);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  week: selectedWeek,
                  weekday: selectedWeekday,
                )),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (selected != null) {
      await ref
          .read(scheduleControllerProvider.notifier)
          .setReplacementSchedule(date, selected.week, selected.weekday);
    }
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.date,
    required this.week,
    required this.hasBackground,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onSelectWeek,
  });

  final DateTime date;
  final int? week;

  /// 有背景图时给整条日期栏垫一层半透明底色，否则文字会直接压在图片上读不清。
  final bool hasBackground;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onSelectWeek;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: hasBackground
          ? scheme.surface.withValues(alpha: 0.72)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: Row(
          children: [
            IconButton(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                children: [
                  // 窄屏（如 360dp）上「9月18日 · 第 4 周 ▾」按 20 号字放不下会溢出。
                  // 用 FittedBox 在空间不足时整体等比缩小，而不是硬挤出去。
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: onToday,
                          child: Text(
                            '${date.month}月${date.day}日',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Text(' · ', style: TextStyle(fontSize: 20)),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: onSelectWeek,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Text(
                              week == null ? '学期外 ▾' : '第 $week 周 ▾',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.year}年 · ${_weekdayName(date.weekday)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}

class _TodayView extends ConsumerWidget {
  const _TodayView({required this.date, required this.courses});

  final DateTime date;
  final List<ScheduleEntry> courses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    ScheduleEntry? next;
    if (_sameDay(date, now)) {
      for (final entry in courses) {
        if (entry.startTime.isAfter(now)) {
          next = entry;
          break;
        }
      }
    }
    if (courses.isEmpty) {
      return const _EmptyCourses(message: '这一天没有安排');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: courses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = courses[index];
        final isNext = identical(entry, next);
        return _CourseCard(
          item: entry,
          isNext: isNext,
          countdown: isNext
              ? _countdown(entry.startTime.difference(now))
              : null,
        );
      },
    );
  }
}

class _WeekView extends StatelessWidget {
  const _WeekView({required this.selectedDate, required this.engine});

  final DateTime selectedDate;
  final ScheduleEngine engine;

  @override
  Widget build(BuildContext context) {
    final monday = selectedDate.subtract(
      Duration(days: selectedDate.weekday - 1),
    );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      itemCount: 7,
      itemBuilder: (context, index) {
        final date = monday.add(Duration(days: index));
        final courses = engine.getEntriesForDate(date);
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  '${_weekdayName(date.weekday)}  ${date.month}/${date.day}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (courses.isEmpty)
                Text(
                  '没有安排',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...courses.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CourseCard(item: entry, compact: true),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CourseCard extends ConsumerWidget {
  const _CourseCard({
    required this.item,
    this.isNext = false,
    this.countdown,
    this.compact = false,
  });

  final ScheduleEntry item;
  final bool isNext;
  final String? countdown;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemColor = Color(
      switch (item) {
        CourseEntry(course: final scheduled) => scheduled.course.colorValue,
        MemoEntry(memo: final memo) => memo.colorValue,
      },
    );
    // 卡片底色跟随设置，但只在真的有背景图时才调低：否则移除背景图后
    // 卡片会在纯色底上变成半透明，反而看不清。
    final backgroundPath = ref.watch(backgroundImagePathProvider).valueOrNull;
    final hasBackground =
        backgroundPath != null && File(backgroundPath).existsSync();
    final cardOpacity = hasBackground
        ? ref.watch(cardOpacityProvider).valueOrNull ??
              CardOpacityController.defaultOpacity
        : CardOpacityController.defaultOpacity;
    return Card(
      color: (Theme.of(context).cardTheme.color ?? Colors.white).withValues(
        alpha: cardOpacity,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isNext
            ? BorderSide(color: itemColor.withValues(alpha: 0.7), width: 1.2)
            : BorderSide.none,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          // 点一下看这门课的详细信息（含 App 实际存储的各项字段），
          // 长按进入编辑——两个手势分开，避免想查看时误改配置。
          onTap: () => _showDetail(context, ref),
          onLongPress: () => _editEntry(context, ref),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 4, color: itemColor),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      compact ? 10 : 14,
                      6,
                      compact ? 10 : 14,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 82,
                          child: Text(
                            '${_timeText(item.startTime)}\n${_timeText(item.endTime)}',
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (item.isMemo) ...[
                                    Icon(
                                      Icons.event_note_outlined,
                                      size: 13,
                                      color: itemColor,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (countdown != null)
                                    Text(
                                      countdown!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: itemColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                [item.location, item.teacher]
                                    .where((value) => value.isNotEmpty)
                                    .join(' · '),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: item.isMemo ? '更改备忘录颜色' : '更改课程颜色',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _pickColor(context, ref),
                          icon: Icon(
                            Icons.palette_outlined,
                            size: 18,
                            color: itemColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 点按查看详情。课程显示完整字段（便于与 1 系统「排课信息」对照排查识别问题），
  /// 备忘录显示自己的时间信息。
  Future<void> _showDetail(BuildContext context, WidgetRef ref) async {
    final term = ref.read(scheduleControllerProvider).valueOrNull?.term;
    if (term == null) return;
    switch (item) {
      case CourseEntry(course: final scheduled):
        await showCourseDetailSheet(
          context,
          term: term,
          course: scheduled.course,
          session: scheduled.session,
          date: scheduled.startTime,
        );
      case MemoEntry(memo: final memo):
        await _showMemoDetail(context, term, memo);
    }
  }

  Future<void> _showMemoDetail(
    BuildContext context,
    Term term,
    Memo memo,
  ) async {
    final isRepeating = memo.weekRule != null;
    final lines = <String>[
      if (memo.location.isNotEmpty) '地点：${memo.location}',
      if (isRepeating) ...[
        '时间：${weekdayName(memo.weekday!)} '
            '第 ${memo.startPeriod}-${memo.endPeriod} 节',
        '周次：${memo.weekRule!.displayText}',
      ] else ...[
        '日期：${memo.date!.year}年${memo.date!.month}月${memo.date!.day}日'
            ' ${weekdayName(memo.date!.weekday)}',
        '时间：${clockText(memo.startMinutes!)}-${clockText(memo.endMinutes!)}',
      ],
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(memo.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line),
              ),
            const SizedBox(height: 8),
            Text(
              isRepeating ? '按周重复的备忘录' : '一次性备忘录',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _editEntry(BuildContext context, WidgetRef ref) async {
    final term = ref.read(scheduleControllerProvider).valueOrNull?.term;
    if (term == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => switch (item) {
          CourseEntry(course: final scheduled) => ManualCoursePage(
            term: term,
            course: scheduled.course,
            session: scheduled.session,
            date: scheduled.startTime,
          ),
          MemoEntry(memo: final memo) => ManualCoursePage(
            term: term,
            memo: memo,
          ),
        },
      ),
    );
  }

  Future<void> _pickColor(BuildContext context, WidgetRef ref) async {
    const colors = [
      0xFF7D9DCE,
      0xFF7FB69D,
      0xFFD19A8A,
      0xFFB497C9,
      0xFFD0B36C,
      0xFF6FAFB5,
    ];
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.isMemo ? '选择备忘录颜色' : '选择课程颜色',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 16,
                children: colors
                    .map(
                      (value) => InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => Navigator.pop(context, value),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: CircleAvatar(
                            backgroundColor: Color(value),
                            radius: 18,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    final notifier = ref.read(scheduleControllerProvider.notifier);
    switch (item) {
      case CourseEntry(course: final scheduled):
        await notifier.changeCourseColor(scheduled.course.id, selected);
      case MemoEntry(memo: final memo):
        await notifier.changeMemoColor(memo.id, selected);
    }
  }
}

/// 背景图 + 可调浓度的半透明遮罩。没有背景图时直接返回 [child]，
/// 不额外套一层 Stack，保证未设置时的布局与从前完全一致。
class _BackgroundImage extends StatelessWidget {
  const _BackgroundImage({
    required this.path,
    required this.overlayOpacity,
    required this.child,
  });

  final String? path;

  /// 遮罩浓度，0.0 完全透明 ~ 1.0 全黑。由外观设置里的滑杆控制。
  final double overlayOpacity;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final filePath = path;
    // 文件被删掉或路径失效时静默降级为无背景图。
    if (filePath == null || !File(filePath).existsSync()) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(filePath),
          fit: BoxFit.cover,
          // 图片解不开时只隐藏图片本身，不打断界面。
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        if (overlayOpacity > 0)
          IgnorePointer(
            child: ColoredBox(
              color: Color.fromRGBO(0, 0, 0, overlayOpacity.clamp(0.0, 1.0)),
            ),
          ),
        child,
      ],
    );
  }
}

/// 最近一次日期切换的方向：1 表示向后（更晚），-1 表示向前（更早）。
/// 只用于给日期内容做一个横向滑入动画，让切换有方向感。
final _dateChangeDirectionProvider = StateProvider<int>((ref) => 1);

/// 日期变化时让内容横向滑入：新内容从切换方向的一侧进入，旧内容淡出。
/// 与“切到本周课表”的标签页过渡观感一致。
class _SlideOnDateChange extends StatelessWidget {
  const _SlideOnDateChange({
    required this.dateKey,
    required this.direction,
    required this.child,
  });

  /// 用日期本身作为 key：日期一变就触发一次进场动画。
  final DateTime dateKey;
  final int direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        // 按切换方向决定从哪一侧滑入；负方向（更早）则反过来。
        final offset = Tween<Offset>(
          begin: Offset(direction >= 0 ? 0.18 : -0.18, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey(dateKey), child: child),
    );
  }
}

class _EmptyCourses extends ConsumerWidget {
  const _EmptyCourses({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundPath = ref.watch(backgroundImagePathProvider).valueOrNull;
    final hasBackground =
        backgroundPath != null && File(backgroundPath).existsSync();
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.free_breakfast_outlined,
          size: 42,
          color: scheme.outline,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
    // 有背景图时给提示垫一层圆角底色，否则浅色文字压在图上读不清。
    if (!hasBackground) return Center(child: content);
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(padding: const EdgeInsets.all(20), child: content),
      ),
    );
  }
}

/// 底部署名行。有背景图时垫一层半透明底色，否则这行小字会直接压在图片上
/// 几乎看不见——与标题栏、日期栏是同一类问题。
class _PoweredByFooter extends ConsumerWidget {
  const _PoweredByFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundPath = ref.watch(backgroundImagePathProvider).valueOrNull;
    final hasBackground =
        backgroundPath != null && File(backgroundPath).existsSync();
    return ColoredBox(
      color: hasBackground
          ? scheme.surface.withValues(alpha: 0.72)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Powered by Algernon',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

String _weekdayName(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
String _timeText(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String _countdown(Duration duration) {
  final minutes = duration.inMinutes + (duration.inSeconds % 60 == 0 ? 0 : 1);
  if (minutes < 60) return '还有 $minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '还有 $hours 小时' : '还有 $hours 小时 $rest 分';
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
