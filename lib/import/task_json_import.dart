import 'dart:convert';

import '../domain/task_record.dart';

List<TaskRecord> parseTaskImport(String text) {
  if (utf8.encode(text).length > 200000) {
    throw const FormatException('文件不能超过 200 KB');
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic> ||
      decoded['version'] != 1 ||
      decoded['tasks'] is! List ||
      (decoded['tasks'] as List).isEmpty ||
      (decoded['tasks'] as List).length > 50) {
    throw const FormatException('请选择包含 1–50 项作业的课集采集文件');
  }
  final now = DateTime.now();
  final unique = <String, TaskRecord>{};
  for (final entry in decoded['tasks'] as List) {
    if (entry is! Map<String, dynamic>) throw const FormatException('作业格式无效');
    final title = entry['title'];
    final course = entry['course'];
    final platform = entry['platform'];
    final dueText = entry['dueAt'];
    final url = entry['url'] ?? '';
    final note = entry['note'] ?? '';
    if (title is! String ||
        course is! String ||
        platform is! String ||
        url is! String ||
        note is! String ||
        (dueText != null && dueText is! String)) {
      throw const FormatException('作业字段无效');
    }
    final dueAt = dueText == null || dueText.isEmpty
        ? null
        : DateTime.tryParse(dueText);
    if (dueText != null && dueText.isNotEmpty && dueAt == null) {
      throw const FormatException('截止时间无效');
    }
    if (note.length > 2000) throw const FormatException('备注不能超过 2000 字');
    final key =
        '$platform|${course.trim()}|${safeTaskUrl(url)}|${title.trim()}';
    final importNote = '浏览器页面采集，待核对。\n$note';
    final task = TaskRecord(
      id: 'browser:${_stableId(key)}',
      title: title,
      course: course,
      platform: platform,
      source: 'browser',
      accountId: '',
      createdAt: now,
      dueAt: dueAt,
      url: url,
      note: importNote.substring(
        0,
        importNote.length > 2000 ? 2000 : importNote.length,
      ),
    );
    unique[key] = task;
  }
  return unique.values.toList();
}

String _stableId(String value) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(value)) {
    hash = ((hash ^ byte) * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
