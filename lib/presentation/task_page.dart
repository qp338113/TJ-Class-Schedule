import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../application/schedule_controller.dart';
import '../application/task_sync_controller.dart';
import '../application/task_state.dart';
import '../data/task_repository.dart';
import '../domain/task_record.dart';
import 'task_import_page.dart';
import 'task_connections_page.dart';
import 'task_display.dart';
import 'task_guide_page.dart';
import 'task_reminder_settings_page.dart';
import '../notifications/notification_service.dart';

class TaskPage extends ConsumerStatefulWidget {
  const TaskPage({super.key, this.initialTaskId});
  final String? initialTaskId;

  @override
  ConsumerState<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends ConsumerState<TaskPage>
    with WidgetsBindingObserver {
  late Future<List<TaskRecord>> _tasks;
  String _search = '';
  String _view = 'pending';
  String _platform = 'all';
  String _course = 'all';
  bool _courseSort = false;
  bool _showDemo = false;
  bool _syncing = false;
  Timer? _timer;
  Timer? _countdownTimer;
  final _authPlatforms = <String>[];
  bool _initialTaskOpened = false;
  late final ProviderContainer _container;
  final _demoCompleted = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _reload();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _automatic());
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _automatic());
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) setState(() {});
    });
  }

  void _automatic() {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    unawaited(_refreshPlatforms(manual: false));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      ref.read(taskRevisionProvider.notifier).state++;
      _automatic();
    } else {
      _timer?.cancel();
      _countdownTimer?.cancel();
      _container.invalidate(taskSyncServiceProvider);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _container.invalidate(taskSyncServiceProvider);
    super.dispose();
  }

  Future<TaskRepository> _repository() async =>
      await ref.read(taskRepositoryProvider.future);

  void _reload() {
    setState(() {
      _tasks = _loadVisible();
    });
  }

  Future<List<TaskRecord>> _loadVisible() async {
    final db = await ref.read(databaseProvider.future);
    final rows = await (await _repository()).loadVisible();
    final auth = <String>[];
    for (final platform in ['canvas', 'haoke']) {
      if (await db.loadSetting('task_${platform}_needs_auth') == 'true') {
        auth.add(platform);
      }
    }
    _authPlatforms
      ..clear()
      ..addAll(auth);
    return rows;
  }

  List<TaskRecord> _visible(List<TaskRecord> saved) {
    final now = DateTime.now();
    final rows = List<TaskRecord>.of(saved);
    final query = _search.trim().toLowerCase();
    rows.removeWhere((task) {
      if (_platform != 'all' && task.platform != _platform) return true;
      if (_course != 'all' && task.course != _course) return true;
      if (query.isNotEmpty &&
          !'${task.title} ${task.course} ${task.platform}'
              .toLowerCase()
              .contains(query)) {
        return true;
      }
      final due = task.dueAt;
      switch (_view) {
        case 'completed':
          return !task.completed;
        case 'overdue':
          return task.completed || due == null || !due.isBefore(now);
        case 'day':
          return task.completed ||
              due == null ||
              due.isBefore(now) ||
              due.isAfter(now.add(const Duration(hours: 24)));
        case 'week':
          return task.completed ||
              due == null ||
              due.isBefore(now) ||
              due.isAfter(now.add(const Duration(days: 7)));
        default:
          return task.completed;
      }
    });
    rows.sort((a, b) {
      if (_courseSort) {
        final course = a.course.compareTo(b.course);
        if (course != 0) return course;
      }
      return (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999));
    });
    return rows;
  }

  Future<void> _edit([TaskRecord? task]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _TaskEditor(task: task)),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _delete(TaskRecord task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条作业？'),
        content: Text('“${task.title}”删除后无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await (await _repository()).deleteManual(task.id);
    if (mounted) _reload();
  }

  Future<void> _toggle(TaskRecord task) async {
    if (!task.completed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认作业已完成？'),
          content: Text('“${task.title}”将移入已完成。这只修改本机记录，不会提交作业；后续同步会保留手动状态。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认完成'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (task.source == 'demo') {
      setState(() => _demoCompleted[task.id] = !task.completed);
      return;
    }
    await (await _repository()).setCompleted(task.id, !task.completed);
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(task.completed ? '已还原至未完成' : '已手动完成；后续同步会保留'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await (await _repository()).setCompleted(task.id, task.completed);
            if (mounted) _reload();
          },
        ),
      ),
    );
  }

  Future<void> _refreshPlatforms({bool manual = true}) async {
    if (_syncing || !mounted) return;
    setState(() => _syncing = true);
    try {
      final service = await ref.read(taskSyncServiceProvider.future);
      final result = await service.refresh(manual: manual);
      if (!mounted) return;
      _reload();
      await _tasks;
      if (!mounted) return;
      if (manual || result.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            persist: false,
            action: _authPlatforms.isEmpty
                ? null
                : SnackBarAction(
                    label: '更新 Token',
                    onPressed: _openConnections,
                  ),
            content: Text(
              result.isEmpty
                  ? '尚未连接 Canvas 或好课'
                  : result.entries
                        .map(
                          (entry) =>
                              "${entry.key == 'canvas'
                                  ? 'Canvas'
                                  : entry.key == 'haoke'
                                  ? '好课'
                                  : entry.key}：${entry.value}",
                        )
                        .join('；'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法同步，已有作业保留')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(taskRevisionProvider, (_, __) => _reload());
    return Scaffold(
      appBar: AppBar(
        title: const Text('作业'),
        actions: [
          IconButton(
            tooltip: '导入采集 JSON',
            onPressed: () async {
              final imported = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const TaskImportPage()),
              );
              if (imported == true && mounted) _reload();
            },
            icon: const Icon(Icons.file_upload_outlined),
          ),
          IconButton(
            tooltip: '同步并刷新',
            onPressed: _syncing ? null : () => _refreshPlatforms(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '平台连接',
            onPressed: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const TaskConnectionsPage()),
              );
              if (mounted) _reload();
            },
            icon: const Icon(Icons.link),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('添加作业'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<TaskRecord>>(
          future: _tasks,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              if (snapshot.hasError) {
                return Center(child: Text('读取作业失败：${snapshot.error}'));
              }
              return const Center(child: CircularProgressIndicator());
            }
            final saved = _showDemo
                ? _demoTasks(DateTime.now())
                      .map(
                        (task) => task.copyWith(
                          completed: _demoCompleted[task.id] ?? false,
                        ),
                      )
                      .toList()
                : snapshot.data!;
            if (!_initialTaskOpened && widget.initialTaskId != null) {
              _initialTaskOpened = true;
              final matches = saved.where(
                (task) => task.id == widget.initialTaskId,
              );
              if (matches.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _showDetail(matches.first);
                });
              }
            }
            final rows = _visible(saved);
            final courses = saved.map((task) => task.course).toSet().toList()
              ..sort();
            final now = DateTime.now();
            final pending = saved.where((task) => !task.completed).length;
            final completed = saved.where((task) => task.completed).length;
            final overdue = saved
                .where(
                  (task) =>
                      !task.completed &&
                      task.dueAt != null &&
                      task.dueAt!.isBefore(now),
                )
                .length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (_authPlatforms.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '平台连接需更新：${_authPlatforms.map((p) => p == 'canvas' ? 'Canvas' : '好课').join('、')}',
                          ),
                          const Text(
                            '登录凭证无法验证或授权不足；已有作业保留。请重新加载 Token 或核对账号权限。',
                          ),
                          TextButton(
                            onPressed: _openConnections,
                            child: const Text('重新加载 Token'),
                          ),
                        ],
                      ),
                    ),
                  ),
                Text(
                  '待完成 $pending  ·  已完成 $completed  ·  逾期 $overdue',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.notifications_outlined),
                      label: const Text('截止提醒'),
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TaskReminderSettingsPage(),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.notification_add_outlined),
                      label: const Text('通知测试'),
                      onPressed: _testNotification,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.help_outline),
                      label: const Text('Token 与使用教程'),
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TaskGuidePage(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索作业、课程或平台',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (key, label) in [
                        ('pending', '待完成'),
                        ('day', '24小时内'),
                        ('week', '7天内'),
                        ('overdue', '已逾期'),
                        ('completed', '已完成'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _view == key,
                            onSelected: (_) => setState(() => _view = key),
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _platform,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('全部平台')),
                          DropdownMenuItem(
                            value: 'canvas',
                            child: Text('Canvas'),
                          ),
                          DropdownMenuItem(value: 'haoke', child: Text('好课')),
                          DropdownMenuItem(
                            value: 'chaoxing',
                            child: Text('学习通'),
                          ),
                          DropdownMenuItem(
                            value: 'polymas',
                            child: Text('Polymas'),
                          ),
                          DropdownMenuItem(value: 'oj', child: Text('课程 OJ')),
                          DropdownMenuItem(value: 'manual', child: Text('手工')),
                        ],
                        onChanged: (value) =>
                            setState(() => _platform = value!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: courses.contains(_course) ? _course : 'all',
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('全部课程'),
                          ),
                          for (final course in courses)
                            DropdownMenuItem(
                              value: course,
                              child: Text(
                                course,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _course = value!),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _courseSort = !_courseSort),
                      icon: const Icon(Icons.sort),
                      label: Text(_courseSort ? '按课程分组' : '按截止时间排序'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _showDemo = !_showDemo;
                        _course = 'all';
                      }),
                      child: Text(_showDemo ? '关闭演示' : '查看演示'),
                    ),
                  ],
                ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('这里暂时没有作业')),
                  ),
                for (var index = 0; index < rows.length; index++) ...[
                  if (_courseSort &&
                      (index == 0 ||
                          rows[index - 1].course != rows[index].course))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        rows[index].course,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  _taskCard(rows[index]),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _testNotification() async {
    final service = ref.read(notificationServiceProvider);
    try {
      final sent = await service.sendTaskTestNotification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          persist: false,
          content: Text(sent ? '测试通知已发送，请查看通知栏' : '系统通知未允许，请在设置中开启'),
          action: sent
              ? null
              : SnackBarAction(
                  label: '通知设置',
                  onPressed: () => service.openNotificationSettings(),
                ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('测试通知发送失败，请检查系统通知设置'),
          ),
        );
      }
    }
  }

  Future<void> _openConnections() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const TaskConnectionsPage()),
    );
    if (mounted) _reload();
  }

  Widget _taskCard(TaskRecord task) {
    final color = taskCourseColor(
      task.course,
      ref.watch(scheduleControllerProvider).valueOrNull?.courses ?? const [],
    );
    final urgent =
        !task.completed &&
        task.dueAt != null &&
        task.dueAt!.difference(DateTime.now()) <= const Duration(hours: 24);
    return Card(
      color: Color.alphaBlend(
        color.withValues(alpha: .07),
        Theme.of(context).colorScheme.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1.5),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          activeColor: color,
          value: task.completed,
          onChanged: (_) => _toggle(task),
        ),
        title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${task.course} · ${task.platform}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              taskCountdown(task, DateTime.now()),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: urgent ? Theme.of(context).colorScheme.error : color,
              ),
            ),
            Text('截止：${_dueLabel(task.dueAt)}'),
          ],
        ),
        onTap: () => _showDetail(task),
      ),
    );
  }

  void _showDetail(TaskRecord task) => unawaited(
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TaskDetail(
        task: task,
        onEdit: task.source == 'manual'
            ? () {
                Navigator.pop(context);
                _edit(task);
              }
            : null,
        onDelete: ['manual', 'browser'].contains(task.source)
            ? () {
                Navigator.pop(context);
                _delete(task);
              }
            : null,
      ),
    ),
  );
}

String _dueLabel(DateTime? date) => date == null
    ? '无截止时间'
    : '${date.toLocal().month}月${date.toLocal().day}日 ${date.toLocal().hour.toString().padLeft(2, '0')}:${date.toLocal().minute.toString().padLeft(2, '0')}';

List<TaskRecord> _demoTasks(DateTime now) => [
  TaskRecord(
    id: 'demo-1',
    title: '演示 · 数学课后习题',
    course: '示例课程',
    platform: 'manual',
    source: 'demo',
    accountId: '',
    createdAt: now,
    dueAt: now.add(const Duration(hours: 8)),
  ),
];

class _TaskDetail extends StatelessWidget {
  const _TaskDetail({required this.task, this.onEdit, this.onDelete});
  final TaskRecord task;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('${task.course} · ${task.platform}'),
              Text('截止：${_dueLabel(task.dueAt)}'),
              Text(taskCountdown(task, DateTime.now())),
              Text('状态：${task.completed ? '已完成' : '待完成'}'),
              if (task.syncedAt != null)
                Text('最近同步：${_dueLabel(task.syncedAt)}'),
              if (task.submissionState != null)
                Text('平台提交状态：${task.submissionState}'),
              if (task.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(task.note),
                ),
              if (task.url.isNotEmpty)
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => _TaskLinkPage(url: task.url),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开平台页面'),
                ),
              Row(
                children: [
                  if (onEdit != null)
                    TextButton(onPressed: onEdit, child: const Text('修改')),
                  if (onDelete != null)
                    TextButton(onPressed: onDelete, child: const Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TaskLinkPage extends StatefulWidget {
  const _TaskLinkPage({required this.url});
  final String url;
  @override
  State<_TaskLinkPage> createState() => _TaskLinkPageState();
}

class _TaskLinkPageState extends State<_TaskLinkPage> {
  @override
  void dispose() {
    controller.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  late final WebViewController controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.url));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('平台页面')),
    body: WebViewWidget(controller: controller),
  );
}

class _TaskEditor extends ConsumerStatefulWidget {
  const _TaskEditor({this.task});
  final TaskRecord? task;
  @override
  ConsumerState<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<_TaskEditor> {
  late final title = TextEditingController(text: widget.task?.title ?? '');
  late final course = TextEditingController(text: widget.task?.course ?? '');
  late final url = TextEditingController(text: widget.task?.url ?? '');
  late final note = TextEditingController(text: widget.task?.note ?? '');
  late String platform = widget.task?.platform ?? 'manual';
  late DateTime? dueAt = widget.task?.dueAt?.toLocal();
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    course.dispose();
    url.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final date = await showDatePicker(
      context: context,
      initialDate: dueAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: dueAt == null
          ? const TimeOfDay(hour: 23, minute: 59)
          : TimeOfDay.fromDateTime(dueAt!),
    );
    if (time == null) return;
    setState(
      () => dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    try {
      setState(() => saving = true);
      final old = widget.task;
      final task = TaskRecord(
        id: old?.id ?? 'manual:${DateTime.now().microsecondsSinceEpoch}',
        title: title.text,
        course: course.text,
        platform: platform,
        source: 'manual',
        accountId: '',
        createdAt: old?.createdAt ?? DateTime.now(),
        dueAt: dueAt,
        completed: old?.completed ?? false,
        manualCompleted: old?.manualCompleted,
        url: url.text,
        note: note.text,
      );
      await (await ref.read(taskRepositoryProvider.future)).save(task);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.task == null ? '添加作业' : '修改作业')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: title,
          maxLength: 200,
          decoration: const InputDecoration(labelText: '作业标题'),
        ),
        TextField(
          controller: course,
          maxLength: 100,
          decoration: const InputDecoration(labelText: '课程名称'),
        ),
        DropdownButtonFormField<String>(
          initialValue: platform,
          decoration: const InputDecoration(labelText: '平台'),
          items: const [
            DropdownMenuItem(value: 'manual', child: Text('手工')),
            DropdownMenuItem(value: 'canvas', child: Text('Canvas')),
            DropdownMenuItem(value: 'haoke', child: Text('好课')),
            DropdownMenuItem(value: 'chaoxing', child: Text('学习通')),
            DropdownMenuItem(value: 'polymas', child: Text('Polymas')),
            DropdownMenuItem(value: 'oj', child: Text('课程 OJ')),
          ],
          onChanged: (value) => platform = value!,
        ),
        ListTile(
          title: Text('截止：${_dueLabel(dueAt)}'),
          onTap: _pickDue,
          trailing: IconButton(
            tooltip: '清除截止时间',
            onPressed: () => setState(() => dueAt = null),
            icon: const Icon(Icons.clear),
          ),
        ),
        TextField(
          controller: url,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: '平台链接（可不填）'),
        ),
        TextField(
          controller: note,
          maxLength: 2000,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '备注（可不填）'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? '保存中' : '保存'),
        ),
      ],
    ),
  );
}
