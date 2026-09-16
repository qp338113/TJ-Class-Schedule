import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../domain/course_conflict.dart';
import '../domain/schedule_models.dart';
import '../import/course_import.dart';

class ImportPreviewPage extends ConsumerStatefulWidget {
  const ImportPreviewPage({
    super.key,
    this.initialPreview,
    this.title = '导入课表',
  });

  final ImportPreview? initialPreview;
  final String title;

  @override
  ConsumerState<ImportPreviewPage> createState() => _ImportPreviewPageState();
}

class _ImportPreviewPageState extends ConsumerState<ImportPreviewPage> {
  static const _parser = CourseImportParser();
  late ImportPreview? _preview;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _preview = widget.initialPreview;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: preview == null ? _emptyState() : _previewTable(preview),
      bottomNavigationBar: preview == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                onPressed: _canCommit(preview) ? _commit : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('确认导入'),
                ),
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.table_view_rounded,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              '选择 CSV 或 Excel 文件',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              '需要包含课程名、周几、节次和周次范围。识别有疑问的格子会标成黄色。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _reading ? null : _pickFile,
              icon: _reading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_open_outlined),
              label: Text(_reading ? '正在读取' : '选择文件'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewTable(ImportPreview preview) {
    if (preview.errors.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text(preview.errors.join('\n'), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _pickFile, child: const Text('重新选择')),
            ],
          ),
        ),
      );
    }
    final warningCount = preview.rows.where((row) => !row.isValid).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  warningCount == 0
                      ? '已识别 ${preview.rows.length} 行课程'
                      : '有 $warningCount 行需要修正',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(onPressed: _pickFile, child: const Text('换个文件')),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 44,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 72,
                  columns: [
                    for (final field in ImportField.values)
                      DataColumn(label: Text(_fieldLabel(field))),
                    const DataColumn(label: Text('操作')),
                  ],
                  rows: preview.rows.map((row) {
                    return DataRow(
                      cells: [
                        for (final field in ImportField.values)
                          DataCell(
                            Tooltip(
                              message: row.cells[field]!.warning ?? '点击修改',
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 80,
                                  maxWidth: 150,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: row.cells[field]!.needsAttention
                                      ? Colors.amber.withValues(alpha: 0.28)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  row.cells[field]!.raw.isEmpty
                                      ? '—'
                                      : row.cells[field]!.raw,
                                ),
                              ),
                            ),
                            onTap: () => _editCell(
                              row.sourceRow,
                              field,
                              row.cells[field]!.raw,
                            ),
                          ),
                        DataCell(
                          IconButton(
                            tooltip: '删除这一行',
                            onPressed: () => _removeRow(row.sourceRow),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    setState(() => _reading = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final extension = file.extension?.toLowerCase();
      final preview = extension == 'csv'
          ? _parser.parseCsv(utf8.decode(bytes, allowMalformed: true))
          : _parser.parseXlsx(bytes);
      if (mounted) setState(() => _preview = preview);
    } catch (_) {
      if (mounted) _showMessage('文件读取失败，请确认格式后重试');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _editCell(
    int sourceRow,
    ImportField field,
    String oldText,
  ) async {
    final controller = TextEditingController(text: oldText);
    final changed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改${_fieldLabel(field)}'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (changed == null || _preview == null) return;
    setState(
      () => _preview = _parser.updateCell(_preview!, sourceRow, field, changed),
    );
  }

  void _removeRow(int sourceRow) {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _preview = _parser.removeRow(preview, sourceRow));
  }

  bool _canCommit(ImportPreview preview) =>
      preview.canImport && preview.rows.every((row) => row.isValid);

  Future<void> _commit() async {
    final result = _parser.buildCourses(_preview!);
    final current = ref.read(scheduleControllerProvider).requireValue.courses;
    final incomingKeys = result.courses.map(_courseKey).toSet();
    final currentKeys = current.map(_courseKey).toSet();
    final newCount = incomingKeys.difference(currentKeys).length;
    final updateCount = incomingKeys.intersection(currentKeys).length;
    final removeCount = currentKeys.difference(incomingKeys).length;
    final conflicts = findCourseConflicts(result.courses);
    final merge = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认导入方式'),
        content: Text(
          '本次识别：新增 $newCount 门，更新 $updateCount 门。\n'
          '全部替换还会移除 $removeCount 门现有课程。'
          '${conflicts.isEmpty ? '' : '\n\n注意：发现 ${conflicts.length} 处课程时间冲突。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回检查'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('全部替换'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('合并导入'),
          ),
        ],
      ),
    );
    if (merge == null) return;
    await ref
        .read(scheduleControllerProvider.notifier)
        .importCourses(result.courses, merge: merge);
    if (!mounted) return;
    final state = ref.read(scheduleControllerProvider);
    if (state.hasError) {
      _showMessage('保存失败，请重试');
    } else {
      Navigator.pop(context, true);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

String _courseKey(Course course) =>
    '${course.name.trim().toLowerCase()}\u0000${course.teacher.trim().toLowerCase()}';

String _fieldLabel(ImportField field) => switch (field) {
  ImportField.courseName => '课程名',
  ImportField.teacher => '教师',
  ImportField.location => '地点',
  ImportField.weekday => '周几',
  ImportField.periods => '节次',
  ImportField.weeks => '周次范围',
};
