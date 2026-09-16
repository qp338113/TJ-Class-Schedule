import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../application/schedule_controller.dart';
import '../domain/schedule_models.dart';
import '../import/term_import.dart';

class TermSetupPage extends ConsumerStatefulWidget {
  const TermSetupPage({super.key, this.initialTerm});

  final Term? initialTerm;

  @override
  ConsumerState<TermSetupPage> createState() => _TermSetupPageState();
}

class _TermSetupPageState extends ConsumerState<TermSetupPage> {
  static const _termParser = TermImportParser();
  late final TextEditingController _nameController;
  late final TextEditingController _weeksController;
  late DateTime _firstMonday;
  late List<LessonPeriod> _periods;

  @override
  void initState() {
    super.initState();
    final term = widget.initialTerm;
    _nameController = TextEditingController(text: term?.name ?? '新学期');
    _weeksController = TextEditingController(text: '${term?.totalWeeks ?? 20}');
    _firstMonday = term?.firstWeekMonday ?? _mondayOf(DateTime.now());
    _periods = List.of(term?.periodsByWeekday[1] ?? tongjiLessonPeriods);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weeksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initialTerm == null ? '设置学期' : '编辑学期')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: '学期名称'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SettingTile(
                  label: '第一周周一',
                  value: _dateText(_firstMonday),
                  onTap: _pickFirstMonday,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _weeksController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '总周数'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Text('每天节次', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _importTermSettings,
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: const Text('从课表识别'),
              ),
              TextButton.icon(
                onPressed: _addPeriod,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._periods.indexed.map((entry) {
            final (index, period) = entry;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  title: Text('第 ${period.number} 节'),
                  subtitle: Text(
                    '${_timeText(period.startMinutes)} - ${_timeText(period.endMinutes)}',
                  ),
                  onTap: () => _editPeriod(index),
                  trailing: IconButton(
                    tooltip: '删除节次',
                    onPressed: _periods.length == 1
                        ? null
                        : () => _removePeriod(index),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('保存学期'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFirstMonday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstMonday,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择开学第一周中的任意一天',
    );
    if (picked != null) setState(() => _firstMonday = _mondayOf(picked));
  }

  Future<void> _editPeriod(int index) async {
    final old = _periods[index];
    final start = await showTimePicker(
      context: context,
      initialTime: _toTime(old.startMinutes),
      helpText: '选择开始时间',
    );
    if (!mounted || start == null) return;
    final end = await showTimePicker(
      context: context,
      initialTime: _toTime(old.endMinutes),
      helpText: '选择结束时间',
    );
    if (!mounted || end == null) return;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes) {
      _showMessage('结束时间必须晚于开始时间');
      return;
    }
    setState(() {
      _periods[index] = LessonPeriod(
        number: old.number,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
      );
    });
  }

  Future<void> _importTermSettings() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [
        'csv',
        'xlsx',
        'png',
        'jpg',
        'jpeg',
        'webp',
        'heic',
        'heif',
        'bmp',
      ],
    );
    if (file == null || !mounted) return;
    try {
      final extension = file.extension?.toLowerCase();
      late final TermImportSuggestion suggestion;
      if (extension == 'csv') {
        suggestion = _termParser.parseCsv(
          utf8.decode(await file.readAsBytes(), allowMalformed: true),
        );
      } else if (extension == 'xlsx') {
        suggestion = _termParser.parseXlsx(await file.readAsBytes());
      } else {
        final path = file.path;
        if (path == null) throw const FormatException('无法读取图片路径');
        final recognizer = TextRecognizer(
          script: TextRecognitionScript.chinese,
        );
        try {
          final text = await recognizer.processImage(
            InputImage.fromFilePath(path),
          );
          suggestion = _termParser.inferFromText(text.text);
        } finally {
          await recognizer.close();
        }
      }
      final weeks = suggestion.totalWeeks;
      if (weeks == null) {
        _showMessage('没有识别到周次，请换一张更清晰的图片或手工填写');
        return;
      }
      setState(() {
        _weeksController.text = '$weeks';
        _periods = List.of(suggestion.periods);
      });
      _showMessage(
        suggestion.usedDefaultPeriods
            ? '已识别 $weeks 周；图片未含时间，已使用同济大学作息模板'
            : '已识别 $weeks 周和文件中的上课时间',
      );
    } catch (_) {
      _showMessage('识别失败，请确认图片清晰；HEIC/HEIF 还需要手机系统支持该格式');
    }
  }

  void _addPeriod() {
    final previous = _periods.last;
    final start = (previous.endMinutes + 10).clamp(0, 23 * 60);
    final end = (start + 45).clamp(start + 1, 24 * 60);
    setState(() {
      _periods.add(
        LessonPeriod(
          number: _periods.length + 1,
          startMinutes: start,
          endMinutes: end,
        ),
      );
    });
  }

  void _removePeriod(int index) {
    setState(() {
      _periods.removeAt(index);
      _periods = [
        for (final (newIndex, period) in _periods.indexed)
          LessonPeriod(
            number: newIndex + 1,
            startMinutes: period.startMinutes,
            endMinutes: period.endMinutes,
          ),
      ];
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final weeks = int.tryParse(_weeksController.text.trim());
    if (name.isEmpty || weeks == null || weeks < 1 || weeks > 60) {
      _showMessage('请填写学期名称，总周数应为 1 到 60');
      return;
    }
    final periodsByDay = {
      for (var day = 1; day <= 7; day++) day: List<LessonPeriod>.of(_periods),
    };
    final term = Term(
      id: currentTermId,
      name: name,
      firstWeekMonday: _firstMonday,
      totalWeeks: weeks,
      periodsByWeekday: periodsByDay,
    );
    await ref.read(scheduleControllerProvider.notifier).saveTerm(term);
    if (!mounted) return;
    final state = ref.read(scheduleControllerProvider);
    if (state.hasError) {
      _showMessage('保存失败，请重试');
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(label, style: Theme.of(context).textTheme.labelMedium),
        subtitle: Text(value),
        onTap: onTap,
      ),
    );
  }
}

DateTime _mondayOf(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

TimeOfDay _toTime(int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
String _timeText(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
String _dateText(DateTime date) => '${date.year}年${date.month}月${date.day}日';
