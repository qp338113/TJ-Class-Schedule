import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../domain/course_conflict.dart';
import '../domain/schedule_models.dart';
import '../domain/week_rule_parser.dart';

class ManualCoursePage extends ConsumerStatefulWidget {
  const ManualCoursePage({
    super.key,
    required this.term,
    this.course,
    this.session,
    this.date,
  });

  final Term term;
  final Course? course;
  final CourseSession? session;
  final DateTime? date;

  @override
  ConsumerState<ManualCoursePage> createState() => _ManualCoursePageState();
}

class _ManualCoursePageState extends ConsumerState<ManualCoursePage> {
  static const _weekParser = WeekRuleParser();
  static const _palette = [
    0xFF7D9DCE,
    0xFF7FB69D,
    0xFFD19A8A,
    0xFFB497C9,
    0xFFD0B36C,
    0xFF6FAFB5,
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _teacherController;
  late final TextEditingController _locationController;
  late final TextEditingController _weeksController;
  var _weekday = DateTime.monday;
  var _startPeriod = 1;
  var _endPeriod = 1;

  bool get _isEditing => widget.course != null && widget.session != null;
  bool get _isAddingSession => widget.course != null && widget.session == null;
  List<LessonPeriod> get _periods =>
      widget.term.periodsByWeekday[_weekday] ?? const [];

  @override
  void initState() {
    super.initState();
    final course = widget.course;
    final session = widget.session;
    _nameController = TextEditingController(text: course?.name ?? '');
    _teacherController = TextEditingController(text: course?.teacher ?? '');
    _locationController = TextEditingController(text: session?.location ?? '');
    _weeksController = TextEditingController(
      text: session == null
          ? '1-${widget.term.totalWeeks}周'
          : _weekText(session.weekRule),
    );
    _weekday = session?.weekday ?? DateTime.monday;
    final periods = widget.term.periodsByWeekday[_weekday] ?? const [];
    _startPeriod =
        session?.startPeriod ?? (periods.isEmpty ? 1 : periods.first.number);
    _endPeriod =
        session?.endPeriod ??
        (periods.length > 1 ? periods[1].number : _startPeriod);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _locationController.dispose();
    _weeksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final periodNumbers = _periods.map((period) => period.number).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? '修改课程'
              : _isAddingSession
              ? '添加时间段'
              : '手动添加课程',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: '课程名（必填）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _teacherController,
            decoration: const InputDecoration(labelText: '教师'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(labelText: '地点'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _weekday,
            decoration: const InputDecoration(labelText: '周几'),
            items: [
              for (var day = 1; day <= 7; day++)
                DropdownMenuItem(value: day, child: Text(_weekdayName(day))),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _weekday = value;
                final available =
                    widget.term.periodsByWeekday[value] ?? const [];
                _startPeriod = available.isEmpty ? 1 : available.first.number;
                _endPeriod = available.length > 1
                    ? available[1].number
                    : _startPeriod;
              });
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _periodPicker(
                  label: '开始节次',
                  value: _startPeriod,
                  numbers: periodNumbers,
                  onChanged: (value) => setState(() => _startPeriod = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _periodPicker(
                  label: '结束节次',
                  value: _endPeriod,
                  numbers: periodNumbers,
                  onChanged: (value) => setState(() => _endPeriod = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weeksController,
            decoration: const InputDecoration(
              labelText: '上课周次（必填）',
              helperText: '例如：1-16周、1-16周(单)、1,3,5-9周',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('保存课程'),
            ),
          ),
          if (_isEditing) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _addSession,
              child: const Text('为这门课添加另一个时间段'),
            ),
            if (widget.date != null)
              OutlinedButton(
                onPressed: _cancelThisDate,
                child: Text('仅 ${widget.date!.month}月${widget.date!.day}日 停课'),
              ),
            const SizedBox(height: 12),
            TextButton(onPressed: _deleteSession, child: const Text('删除这个时间段')),
            TextButton(
              onPressed: _deleteCourse,
              child: Text(
                '删除整门课程',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _periodPicker({
    required String label,
    required int value,
    required List<int> numbers,
    required ValueChanged<int> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      initialValue: numbers.contains(value) ? value : numbers.firstOrNull,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final number in numbers)
          DropdownMenuItem(value: number, child: Text('第 $number 节')),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return _showMessage('请填写课程名');
    if (_periods.isEmpty ||
        !_periods.any((period) => period.number == _startPeriod) ||
        !_periods.any((period) => period.number == _endPeriod) ||
        _endPeriod < _startPeriod) {
      return _showMessage('结束节次不能早于开始节次');
    }
    final weekResult = _weekParser.parse(_weeksController.text);
    if (!weekResult.isSuccess) {
      return _showMessage(weekResult.error ?? '无法识别上课周次');
    }
    final current = ref.read(scheduleControllerProvider).requireValue;
    final oldCourse = widget.course;
    final courseId =
        oldCourse?.id ?? 'manual-${DateTime.now().microsecondsSinceEpoch}';
    final sessionId =
        widget.session?.id ??
        '$courseId-session-${DateTime.now().microsecondsSinceEpoch}';
    final session = CourseSession(
      id: sessionId,
      weekday: _weekday,
      startPeriod: _startPeriod,
      endPeriod: _endPeriod,
      weekRule: weekResult.value!,
      location: _locationController.text.trim(),
    );
    final sessions = oldCourse == null
        ? [session]
        : widget.session == null
        ? [...oldCourse.sessions, session]
        : [
            for (final oldSession in oldCourse.sessions)
              if (oldSession.id == widget.session!.id) session else oldSession,
          ];
    final course = Course(
      id: courseId,
      name: name,
      teacher: _teacherController.text.trim(),
      colorValue:
          oldCourse?.colorValue ??
          _palette[current.courses.length % _palette.length],
      sessions: sessions,
    );
    final proposed = [
      for (final existing in current.courses)
        if (existing.id == course.id) course else existing,
      if (oldCourse == null) course,
    ];
    final conflicts = findCourseConflicts(proposed);
    if (conflicts.isNotEmpty && !await _confirmConflicts(conflicts)) return;
    if (oldCourse == null) {
      await ref.read(scheduleControllerProvider.notifier).addCourse(course);
    } else {
      await ref.read(scheduleControllerProvider.notifier).updateCourse(course);
    }
    if (!mounted) return;
    if (ref.read(scheduleControllerProvider).hasError) {
      _showMessage('保存失败，请重试');
    } else {
      Navigator.pop(context, true);
    }
  }

  Future<bool> _confirmConflicts(List<CourseConflict> conflicts) async {
    final conflict = conflicts.first;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('发现课程时间冲突'),
            content: Text(
              '第 ${conflict.week} 周${_weekdayName(conflict.weekday)}，'
              '第 ${conflict.startPeriod}-${conflict.endPeriod} 节：'
              '${conflict.firstCourse} 与 ${conflict.secondCourse} 重叠。\n\n仍要保存吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('返回修改'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('仍然保存'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _addSession() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) =>
            ManualCoursePage(term: widget.term, course: widget.course),
      ),
    );
    if (added == true && mounted) Navigator.pop(context);
  }

  Future<void> _cancelThisDate() async {
    if (!await _confirm('确认临时停课？', '只取消这一天的这个课程时间段。')) return;
    await ref
        .read(scheduleControllerProvider.notifier)
        .cancelSessionOnDate(widget.session!.id, widget.date!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteSession() async {
    if (!await _confirm('删除这个时间段？', '其他时间段会继续保留。')) return;
    final course = widget.course!;
    final sessions = course.sessions
        .where((session) => session.id != widget.session!.id)
        .toList();
    if (sessions.isEmpty) {
      await ref
          .read(scheduleControllerProvider.notifier)
          .deleteCourse(course.id);
    } else {
      await ref
          .read(scheduleControllerProvider.notifier)
          .updateCourse(
            Course(
              id: course.id,
              name: course.name,
              teacher: course.teacher,
              colorValue: course.colorValue,
              sessions: sessions,
            ),
          );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteCourse() async {
    if (!await _confirm('删除整门课程？', '这门课的所有时间段都会被删除。')) return;
    await ref
        .read(scheduleControllerProvider.notifier)
        .deleteCourse(widget.course!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

String _weekText(WeekRule rule) {
  final weeks = rule.explicitWeeks;
  if (weeks != null) {
    final sorted = weeks.toList()..sort();
    return '${sorted.join(',')}周';
  }
  final suffix = switch (rule.type) {
    WeekType.odd => '(单)',
    WeekType.even => '(双)',
    WeekType.every || WeekType.custom => '',
  };
  return '${rule.startWeek}-${rule.endWeek}周$suffix';
}

String _weekdayName(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
