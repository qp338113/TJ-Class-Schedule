class TaskRecord {
  static const platforms = {
    'canvas',
    'haoke',
    'chaoxing',
    'polymas',
    'oj',
    'manual',
  };

  TaskRecord({
    required this.id,
    required String title,
    required String course,
    required this.platform,
    required this.source,
    required this.accountId,
    required this.createdAt,
    this.dueAt,
    this.completed = false,
    this.manualCompleted,
    String url = '',
    this.note = '',
    this.syncedAt,
    this.submissionState,
  }) : title = title.trim(),
       course = course.trim(),
       url = safeTaskUrl(url) {
    if (this.title.isEmpty ||
        this.title.length > 200 ||
        this.course.isEmpty ||
        this.course.length > 100 ||
        note.length > 2000 ||
        !platforms.contains(platform)) {
      throw ArgumentError('请检查作业标题、课程和备注');
    }
  }

  factory TaskRecord.manual({
    required String id,
    required String title,
    required String course,
    required String platform,
    required String url,
    required String note,
    DateTime? dueAt,
  }) => TaskRecord(
    id: id,
    title: title,
    course: course,
    platform: platform,
    source: 'manual',
    accountId: '',
    createdAt: DateTime.now(),
    dueAt: dueAt,
    url: url,
    note: note,
  );

  final String id;
  final String title;
  final String course;
  final String platform;
  final String source;
  final String accountId;
  final DateTime createdAt;
  final DateTime? dueAt;
  final bool completed;
  final bool? manualCompleted;
  final String url;
  final String note;
  final DateTime? syncedAt;
  final String? submissionState;

  TaskRecord copyWith({bool? completed, bool? manualCompleted}) => TaskRecord(
    id: id,
    title: title,
    course: course,
    platform: platform,
    source: source,
    accountId: accountId,
    createdAt: createdAt,
    dueAt: dueAt,
    completed: completed ?? this.completed,
    manualCompleted: manualCompleted ?? this.manualCompleted,
    url: url,
    note: note,
    syncedAt: syncedAt,
    submissionState: submissionState,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'course': course,
    'platform': platform,
    'source': source,
    'account_id': accountId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'due_at': dueAt?.toUtc().toIso8601String(),
    'completed': completed ? 1 : 0,
    'manual_completed': manualCompleted == null
        ? null
        : (manualCompleted! ? 1 : 0),
    'url': url,
    'note': note,
    'synced_at': syncedAt?.toUtc().toIso8601String(),
    'submission_state': submissionState,
  };

  factory TaskRecord.fromRow(Map<String, Object?> row) => TaskRecord(
    id: row['id'] as String,
    title: row['title'] as String,
    course: row['course'] as String,
    platform: row['platform'] as String,
    source: row['source'] as String,
    accountId: row['account_id'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    dueAt: row['due_at'] == null
        ? null
        : DateTime.parse(row['due_at'] as String),
    completed: row['completed'] == 1,
    manualCompleted: row['manual_completed'] == null
        ? null
        : row['manual_completed'] == 1,
    url: row['url'] as String,
    note: row['note'] as String,
    syncedAt: row['synced_at'] == null
        ? null
        : DateTime.parse(row['synced_at'] as String),
    submissionState: row['submission_state'] as String?,
  );
}

String safeTaskUrl(String input) {
  final value = input.trim();
  if (value.isEmpty) return '';
  if (value.length > 2000) throw const FormatException('链接过长');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.userInfo.isNotEmpty ||
      uri.queryParameters.keys.any(
        (key) => RegExp(
          r'^(token|access_token|refresh_token|ticket|authorization|cookie|password|enc)$',
          caseSensitive: false,
        ).hasMatch(key),
      ) ||
      RegExp(
        r'token|password|authorization',
        caseSensitive: false,
      ).hasMatch(Uri.decodeComponent(uri.fragment))) {
    throw const FormatException('请填写不含登录凭证的 http 或 https 网址');
  }
  return uri.toString();
}
