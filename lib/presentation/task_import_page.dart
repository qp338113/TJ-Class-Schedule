import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/task_state.dart';
import '../domain/task_record.dart';
import '../import/task_json_import.dart';

class TaskImportPage extends ConsumerStatefulWidget {
  const TaskImportPage({super.key});

  @override
  ConsumerState<TaskImportPage> createState() => _TaskImportPageState();
}

class _TaskImportPageState extends ConsumerState<TaskImportPage> {
  final _text = TextEditingController();
  List<TaskRecord> _preview = const [];
  String? _error;
  bool _confirmed = false;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null || !mounted) return;
    try {
      if ((await picked.length() ?? 200001) > 200000) {
        throw const FormatException('文件不能超过 200 KB');
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      _text.text = utf8.decode(bytes);
      _parse();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '请选择有效 UTF-8 JSON 文件，不能超过 200 KB';
          _preview = [];
          _confirmed = false;
        });
      }
    }
  }

  void _parse() {
    try {
      final tasks = parseTaskImport(_text.text);
      setState(() {
        _preview = tasks;
        _confirmed = false;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _preview = const [];
        _confirmed = false;
        _error = '$error';
      });
    }
  }

  Future<void> _save() async {
    if (!_confirmed || _preview.isEmpty) return;
    setState(() => _saving = true);
    try {
      await (await ref.read(
        taskRepositoryProvider.future,
      )).mergeBrowser(_preview);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('导入作业采集文件')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('选择课集采集 JSON，或粘贴内容。导入前请核对课程与截止时间；网页采集不能证明已经提交。'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _chooseFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('选择 JSON 文件'),
          ),
          TextField(
            controller: _text,
            maxLines: 5,
            onChanged: (_) => setState(() {
              _preview = [];
              _confirmed = false;
              _error = null;
            }),
            decoration: const InputDecoration(labelText: '或粘贴 JSON 内容'),
          ),
          OutlinedButton(onPressed: _parse, child: const Text('预览并核对')),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_preview.isNotEmpty) ...[
            Text(
              '待导入 ${_preview.length} 项',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final task in _preview)
              ListTile(
                title: Text(task.title),
                subtitle: Text(
                  '${task.course} · ${task.platform} · ${task.dueAt?.toLocal() ?? '无截止时间'}',
                ),
              ),
            CheckboxListTile(
              value: _confirmed,
              title: const Text('我已核对课程、作业和截止时间'),
              onChanged: (value) => setState(() => _confirmed = value ?? false),
            ),
            FilledButton(
              onPressed: _confirmed && !_saving ? _save : null,
              child: Text(_saving ? '导入中' : '确认导入'),
            ),
          ],
        ],
      ),
    ),
  );
}
