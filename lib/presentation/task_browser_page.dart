import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../application/task_state.dart';
import '../import/task_capture.dart';
import '../import/task_json_import.dart';

class TaskBrowserPage extends StatefulWidget {
  const TaskBrowserPage({super.key, required this.url, required this.title});
  final String url;
  final String title;
  @override
  State<TaskBrowserPage> createState() => _TaskBrowserPageState();
}

class _TaskBrowserPageState extends State<TaskBrowserPage> {
  late final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.url));
  bool _busy = false;
  @override
  void dispose() {
    unawaited(
      controller
          .loadRequest(Uri.parse('about:blank'))
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  Future<void> _capture() async {
    setState(() => _busy = true);
    try {
      final uri = Uri.tryParse(await controller.currentUrl() ?? '');
      if (uri == null || !canCaptureTaskPage(uri)) {
        throw const FormatException('请先登录并打开教学平台的作业列表');
      }
      final script = await rootBundle.loadString('assets/task_collector.js');
      // 再次在页面内检查来源，防止查询 URL 与执行脚本之间发生跳转。
      final raw = await controller.runJavaScriptReturningResult(
        '(() => { if (location.origin !== ${jsonEncode(uri.origin)}) throw new Error("页面已跳转，请重试"); $script; return JSON.stringify(collectVisibleTasks()); })()',
      );
      if (raw is! String || raw.length > 200000) {
        throw const FormatException('采集结果过大，请缩小到当前课程');
      }
      dynamic snapshot = jsonDecode(raw);
      if (snapshot is String) snapshot = jsonDecode(snapshot);
      if (snapshot is! Map ||
          snapshot['tasks'] is! List ||
          (snapshot['tasks'] as List).isEmpty) {
        throw const FormatException('当前可见页面没有识别到作业，请打开作业列表后重试');
      }
      final rows = (snapshot['tasks'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (rows.length > 50) throw const FormatException('一次最多采集 50 项作业');
      if (!mounted) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => _CaptureReviewPage(rows: rows)),
      );
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('页面采集失败，请确认页面加载完成后重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Text('登录后打开作业列表，再采集当前可见内容。核对并确认后才会保存到手机。'),
              FilledButton.icon(
                onPressed: _busy ? null : _capture,
                icon: const Icon(Icons.download),
                label: Text(_busy ? '正在采集' : '采集当前页面'),
              ),
            ],
          ),
        ),
        Expanded(child: WebViewWidget(controller: controller)),
      ],
    ),
  );
}

class _CaptureReviewPage extends ConsumerStatefulWidget {
  const _CaptureReviewPage({required this.rows});
  final List<Map<String, dynamic>> rows;
  @override
  ConsumerState<_CaptureReviewPage> createState() => _CaptureReviewPageState();
}

class _CaptureReviewPageState extends ConsumerState<_CaptureReviewPage> {
  bool _confirmed = false, _saving = false;
  int _year = DateTime.now().year;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final row in widget.rows) {
      row['selected'] ??= true;
      _setDeadline(row);
    }
  }

  void _setDeadline(Map<String, dynamic> row) {
    if (row['rangeEnd'] is String) {
      row['dueAt'] = rangeDeadline(
        row['rangeStart'] as String? ?? '',
        row['rangeEnd'] as String,
        _year,
      );
    }
  }

  void _changed() => setState(() => _confirmed = false);
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final tasks = parseTaskImport(
        jsonEncode({
          'version': 1,
          'tasks': widget.rows.where((row) => row['selected'] == true).toList(),
        }),
      );
      await (await ref.read(taskRepositoryProvider.future)).mergeBrowser(tasks);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已导入 ${tasks.length} 项作业')));
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('核对页面采集')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('页面采集不能证明已经提交；已提交项默认不选。请补全课程并核对截止时间，导入项作为待完成保存。'),
        if (widget.rows.any((row) => row['rangeEnd'] != null))
          DropdownButtonFormField<int>(
            initialValue: _year,
            decoration: const InputDecoration(labelText: '好课未标注年份时使用'),
            items: [
              for (var year = 2000; year <= 2100; year++)
                DropdownMenuItem(value: year, child: Text('$year 年')),
            ],
            onChanged: (year) => setState(() {
              _year = year!;
              _confirmed = false;
              for (final row in widget.rows) {
                _setDeadline(row);
              }
            }),
          ),
        for (var index = 0; index < widget.rows.length; index++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  CheckboxListTile(
                    value: widget.rows[index]['selected'] == true,
                    title: Text('导入第 ${index + 1} 项'),
                    onChanged: (value) {
                      widget.rows[index]['selected'] = value;
                      _changed();
                    },
                  ),
                  for (final (field, label, limit) in [
                    ('title', '作业标题', 200),
                    ('course', '课程名称', 100),
                    ('dueAt', '截止时间（如 2026-10-08T23:59，可留空）', 40),
                    ('note', '备注及页面时间线索', 2000),
                  ])
                    TextFormField(
                      key: ValueKey(
                        '$index:$field:${field == 'dueAt' ? _year : ''}',
                      ),
                      initialValue: widget.rows[index][field] as String? ?? '',
                      maxLength: limit,
                      maxLines: field == 'note' ? 3 : 1,
                      decoration: InputDecoration(labelText: label),
                      onChanged: (value) {
                        widget.rows[index][field] = value;
                        _changed();
                      },
                    ),
                ],
              ),
            ),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        CheckboxListTile(
          value: _confirmed,
          title: const Text('已核对所选作业、课程和截止时间'),
          onChanged: (value) => setState(() => _confirmed = value ?? false),
        ),
        FilledButton(
          onPressed: _confirmed && !_saving ? _save : null,
          child: Text(_saving ? '导入中' : '确认导入'),
        ),
      ],
    ),
  );
}
