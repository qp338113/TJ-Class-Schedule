import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../domain/schedule_engine.dart';
import '../domain/schedule_models.dart';
import 'import_preview_page.dart';
import 'data_management_page.dart';
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
    final engine = ScheduleEngine(
      term: term,
      courses: data.courses,
      adjustments: data.adjustments,
      cancellations: data.cancellations,
    );
    return DefaultTabController(
      key: ValueKey(navigationRevision),
      length: 2,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ManualCoursePage(term: term),
            ),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加课程'),
        ),
        appBar: AppBar(
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
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'tongji', child: Text('从同济1系统导入')),
                PopupMenuItem(value: 'notifications', child: Text('提醒设置')),
                PopupMenuItem(value: 'makeup', child: Text('检查国家调休')),
                PopupMenuItem(value: 'undo_import', child: Text('撤销上次导入')),
                PopupMenuItem(value: 'backup', child: Text('备份与恢复')),
                PopupMenuItem(value: 'term', child: Text('编辑学期与节次')),
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
              child: TabBarView(
                children: [
                  _TodayView(
                    date: selectedDate,
                    courses: engine.getCoursesForDate(selectedDate),
                  ),
                  _WeekView(selectedDate: selectedDate, engine: engine),
                ],
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Powered by Algernon',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _changeDate(WidgetRef ref, DateTime date, int days) {
    ref.read(selectedDateProvider.notifier).state = date.add(
      Duration(days: days),
    );
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
                  : weekday == null || replacementWeek == null
                  ? '今天是国家调休上班日，请确认补哪一周、周几的课'
                  : '调休提示：今天按第 $replacementWeek 周${_weekdayName(weekday)}课表上课'
                        '${actualWeek == null ? '' : '（实际日期是第 $actualWeek 周）'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (!adjustment.isHoliday)
            TextButton(
              onPressed: () => _selectReplacement(context, ref),
              child: Text(
                weekday == null || replacementWeek == null ? '设置' : '修改',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _selectReplacement(BuildContext context, WidgetRef ref) async {
    var selectedWeek = adjustment.replacementWeek ?? actualWeek ?? 1;
    var selectedWeekday = adjustment.replacementWeekday ?? date.weekday;
    final selected = await showDialog<({int week, int weekday})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('设置补课课表'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请按学校通知选择目标教学周和星期。'),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: selectedWeek,
                decoration: const InputDecoration(labelText: '目标教学周'),
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
                initialValue: selectedWeekday,
                decoration: const InputDecoration(labelText: '目标星期'),
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
        ),
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
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onSelectWeek,
  });

  final DateTime date;
  final int? week;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onSelectWeek;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                const SizedBox(height: 2),
                Text(
                  '${date.year}年 · ${_weekdayName(date.weekday)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class _TodayView extends ConsumerWidget {
  const _TodayView({required this.date, required this.courses});

  final DateTime date;
  final List<ScheduledCourse> courses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    ScheduledCourse? next;
    if (_sameDay(date, now)) {
      for (final course in courses) {
        if (course.startTime.isAfter(now)) {
          next = course;
          break;
        }
      }
    }
    if (courses.isEmpty) {
      return const _EmptyCourses(message: '这一天没有课程');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: courses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final course = courses[index];
        final isNext = identical(course, next);
        return _CourseCard(
          item: course,
          isNext: isNext,
          countdown: isNext
              ? _countdown(course.startTime.difference(now))
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
        final courses = engine.getCoursesForDate(date);
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
                  '没有课程',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...courses.map(
                  (course) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CourseCard(item: course, compact: true),
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

  final ScheduledCourse item;
  final bool isNext;
  final String? countdown;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courseColor = Color(item.course.colorValue);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isNext
            ? BorderSide(color: courseColor.withValues(alpha: 0.7), width: 1.2)
            : BorderSide.none,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onLongPress: () => _editCourse(context, ref),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 4, color: courseColor),
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
                                  Expanded(
                                    child: Text(
                                      item.course.name,
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
                                        color: courseColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                [item.session.location, item.teacher]
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
                          tooltip: '更改课程颜色',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _pickColor(context, ref),
                          icon: Icon(
                            Icons.palette_outlined,
                            size: 18,
                            color: courseColor,
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

  Future<void> _editCourse(BuildContext context, WidgetRef ref) async {
    final term = ref.read(scheduleControllerProvider).valueOrNull?.term;
    if (term == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ManualCoursePage(
          term: term,
          course: item.course,
          session: item.session,
          date: item.startTime,
        ),
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
              Text('选择课程颜色', style: Theme.of(context).textTheme.titleMedium),
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
    if (selected != null) {
      await ref
          .read(scheduleControllerProvider.notifier)
          .changeCourseColor(item.course.id, selected);
    }
  }
}

class _EmptyCourses extends StatelessWidget {
  const _EmptyCourses({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.free_breakfast_outlined,
            size: 42,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
