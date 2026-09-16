import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../data/schedule_backup_codec.dart';

class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  static const _codec = ScheduleBackupCodec();
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('备份与恢复')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('备份是一个保存在你手机里的 JSON 文件，包含学期、课程、调休、临时停课和提醒设置。'),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.save_alt_rounded),
          label: const Text('导出本地备份'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _restore,
          icon: const Icon(Icons.restore_rounded),
          label: const Text('从备份恢复'),
        ),
      ],
    ),
  );

  Future<void> _export() async {
    final schedule = ref.read(scheduleControllerProvider).valueOrNull;
    final settings = ref.read(notificationSettingsProvider).valueOrNull;
    if (schedule?.term == null || settings == null) {
      return _message('课表或设置尚未加载完成');
    }
    setState(() => _busy = true);
    try {
      final json = _codec.encode(
        ScheduleBackup(
          term: schedule!.term!,
          courses: schedule.courses,
          adjustments: schedule.adjustments,
          cancellations: schedule.cancellations,
          settings: settings,
        ),
      );
      final saved = await FilePicker.saveFile(
        fileName: 'TJ-Class-Schedule-backup.json',
        bytes: utf8.encode(json),
        mimeType: 'application/json',
      );
      if (saved != null && mounted) _message('备份已保存');
    } catch (_) {
      if (mounted) _message('备份失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return;
    try {
      final backup = _codec.decode(utf8.decode(await file.readAsBytes()));
      if (!mounted || !await _confirmRestore(backup)) return;
      setState(() => _busy = true);
      await ref.read(scheduleControllerProvider.notifier).restoreBackup(backup);
      await ref
          .read(notificationSettingsProvider.notifier)
          .saveSettings(backup.settings);
      if (!mounted) return;
      if (ref.read(scheduleControllerProvider).hasError) {
        _message('恢复失败，原数据未完整替换');
      } else {
        _message('备份已恢复');
      }
    } catch (_) {
      if (mounted) _message('无法读取这个备份文件');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmRestore(ScheduleBackup backup) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('覆盖当前本机数据？'),
          content: Text(
            '将恢复“${backup.term.name}”和 ${backup.courses.length} 门课程。当前课表会被替换，建议先导出备份。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认恢复'),
            ),
          ],
        ),
      ) ??
      false;

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
