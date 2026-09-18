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
    this.memo,
  });

  final Term term;
  final Course? course;
  final CourseSession? session;
  final DateTime? date;

  /// 编辑既有备忘录时传入；与 [course] 互斥。
  final Memo? memo;

  @override
  ConsumerState<ManualCoursePage> createState() => _ManualCoursePageState();
}

/// 页面顶部的类型切换：同一个入口既能加课程，也能自己添加事件。
enum _EntryType { course, memo }

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

  /// 备忘录专用字段。
  late _EntryType _type;
  var _memoIsOneTime = false;
  late DateTime _memoDate;
  var _memoStartMinutes = 9 * 60;
  var _memoEndMinutes = 10 * 60;
  late int _memoColorValue;
  bool get _isEditing => widget.course != null && widget.session != null;
  bool get _isAddingSession => widget.course != null && widget.session == null;
  bool get _isEditingMemo => widget.memo != null;

  /// 只有全新添加时才显示类型切换：编辑既有课程/备忘录时类型已经确定。
  bool get _canSwitchType => widget.course == null && widget.memo == null;
  List<LessonPeriod> get _periods =>
      widget.term.periodsByWeekday[_weekday] ?? const [];

  @override
  void initState() {
    super.initState();
    final course = widget.course;
    final session = widget.session;
    final memo = widget.memo;
    _type = memo == null ? _EntryType.course : _EntryType.memo;
    _nameController = TextEditingController(
      text: course?.name ?? memo?.title ?? '',
    );
    _teacherController = TextEditingController(text: course?.teacher ?? '');
    _locationController = TextEditingController(
      text: session?.location ?? memo?.location ?? '',
    );
    _weeksController = TextEditingController(
      text: session == null
          ? (memo?.weekRule) == null
                ? '1-${widget.term.totalWeeks}周'
                : _weekText(memo!.weekRule!)
          : _weekText(session.weekRule),
    );
    _weekday = session?.weekday ?? memo?.weekday ?? DateTime.monday;
    final periods = widget.term.periodsByWeekday[_weekday] ?? const [];
    _startPeriod =
        session?.startPeriod ??
        memo?.startPeriod ??
        (periods.isEmpty ? 1 : periods.first.number);
    _endPeriod =
        session?.endPeriod ??
        memo?.endPeriod ??
        (periods.length > 1 ? periods[1].number : _startPeriod);
    const fallbackStart = 9 * 60;
    final memoDate = memo?.date;
    _memoIsOneTime = memoDate != null;
    _memoDate = memoDate ?? DateTime.now();
    _memoStartMinutes = memo?.startMinutes ?? fallbackStart;
    _memoEndMinutes = memo?.endMinutes ?? fallbackStart + 60;
    _memoColorValue = memo?.colorValue ?? _defaultMemoColor();
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
          _type == _EntryType.memo
              ? (_isEditingMemo ? '修改备忘录' : '添加备忘录')
              : _isEditing
              ? '修改课程'
              : _isAddingSession
              ? '添加时间段'
              : '手动添加课程',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (_canSwitchType) ...[
            SegmentedButton<_EntryType>(
              segments: const [
                ButtonSegment(value: _EntryType.course, label: Text('课程')),
                ButtonSegment(value: _EntryType.memo, label: Text('备忘录')),
              ],
              selected: {_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: _type == _EntryType.memo ? '标题（必填）' : '课程名（必填）',
            ),
          ),
          if (_type == _EntryType.course) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _teacherController,
              decoration: const InputDecoration(labelText: '教师'),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(labelText: '地点'),
          ),
          if (_type == _EntryType.memo)
            ..._memoForm(context)
          else ...[
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
                helperText: '例如：1-16周、1-16周(单)、1,5-9周',
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _type == _EntryType.memo ? '保存备忘录' : '保存课程',
              ),
            ),
          ),
          if (_type == _EntryType.memo) ...[
            if (_isEditingMemo) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _deleteMemo,
                child: Text(
                  '删除这条备忘录',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ] else if (_isEditing) ...[
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

  /// 备忘录表单：时间类型二选一，以及颜色。
  List<Widget> _memoForm(BuildContext context) {
    final periodNumbers = _periods.map((period) => period.number).toList();
    return [
      const SizedBox(height: 16),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('按周重复')),
          ButtonSegment(value: true, label: Text('一次性')),
        ],
        selected: {_memoIsOneTime},
        onSelectionChanged: (selection) =>
            setState(() => _memoIsOneTime = selection.first),
      ),
      const SizedBox(height: 12),
      if (_memoIsOneTime) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('日期'),
          trailing: Text(_dateText(_memoDate)),
          onTap: _pickMemoDate,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('开始时刻'),
          trailing: Text(_minutesText(_memoStartMinutes)),
          onTap: () => _pickMemoTime(isStart: true),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('结束时刻'),
          trailing: Text(_minutesText(_memoEndMinutes)),
          onTap: () => _pickMemoTime(isStart: false),
        ),
      ] else ...[
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
            labelText: '重复周次（必填）',
            helperText: '例如：1-16周、1-16周(单)、1,5-9周',
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text('颜色', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 16,
        children: [
          for (final value in _palette)
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => setState(() => _memoColorValue = value),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: CircleAvatar(
                  backgroundColor: Color(value),
                  radius: 16,
                  child: value == _memoColorValue
                      ? const Icon(Icons.check_rounded, size: 16)
                      : null,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 4),
    ];
  }

  int _defaultMemoColor() {
    final current = ref.read(scheduleControllerProvider).valueOrNull;
    return _palette[(current?.memos.length ?? 0) % _palette.length];
  }

  Future<void> _pickMemoDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _memoDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择备忘录日期',
    );
    if (picked != null) setState(() => _memoDate = picked);
  }

  Future<void> _pickMemoTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTime(isStart ? _memoStartMinutes : _memoEndMinutes),
      helpText: isStart ? '选择开始时刻' : '选择结束时刻',
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (isStart) {
        _memoStartMinutes = minutes;
      } else {
        _memoEndMinutes = minutes;
      }
    });
  }

  Future<void> _deleteMemo() async {
    if (!await _confirm('删除这条备忘录？', '删除后就无法恢复了。')) return;
    await ref
        .read(scheduleControllerProvider.notifier)
        .deleteMemo(widget.memo!.id);
    if (mounted) Navigator.pop(context);
  }

  /// 保存备忘录；校验不通过时返回 false 并提示。
  bool _validateMemo(String title) {
    if (title.isEmpty) {
      _showMessage('请填写备忘录标题');
      return false;
    }
    if (_memoIsOneTime) {
      if (_memoEndMinutes <= _memoStartMinutes) {
        _showMessage('结束时刻必须晚于开始时刻');
        return false;
      }
      return true;
    }
    if (_periods.isEmpty ||
        !_periods.any((period) => period.number == _startPeriod) ||
        !_periods.any((period) => period.number == _endPeriod) ||
        _endPeriod < _startPeriod) {
      _showMessage('结束节次不能早于开始节次');
      return false;
    }
    return true;
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
    if (_type == _EntryType.memo) return _saveMemo();
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

  /// 保存备忘录：按周重复走节次，一次性走日期 + 起止时刻。
  Future<void> _saveMemo() async {
    final title = _nameController.text.trim();
    if (!_validateMemo(title)) return;
    WeekRule? weekRule;
    if (!_memoIsOneTime) {
      final weekResult = _weekParser.parse(_weeksController.text);
      if (!weekResult.isSuccess) {
        return _showMessage(weekResult.error ?? '无法识别重复周次');
      }
      weekRule = weekResult.value;
    }
    final oldMemo = widget.memo;
    final memo = Memo(
      id: oldMemo?.id ?? 'memo-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      location: _locationController.text.trim(),
      colorValue: _memoColorValue,
      weekday: _memoIsOneTime ? null : _weekday,
      startPeriod: _memoIsOneTime ? null : _startPeriod,
      endPeriod: _memoIsOneTime ? null : _endPeriod,
      weekRule: _memoIsOneTime ? null : weekRule,
      date: _memoIsOneTime ? _memoDate : null,
      startMinutes: _memoIsOneTime ? _memoStartMinutes : null,
      endMinutes: _memoIsOneTime ? _memoEndMinutes : null,
    );
    final notifier = ref.read(scheduleControllerProvider.notifier);
    if (oldMemo == null) {
      await notifier.addMemo(memo);
    } else {
      await notifier.updateMemo(memo);
    }
    if (!mounted) return;
    if (ref.read(scheduleControllerProvider).hasError) {
      _showMessage('保存失败，请重试');
    } else {
      Navigator.pop(context, true);
    }
  }

  Future<bool> _confirmConflicts(List<CourseConflict> conflicts) async {    final conflict = conflicts.first;
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

TimeOfDay _toTime(int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

String _minutesText(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _dateText(DateTime date) => '${date.year}年${date.month}月${date.day}日';
