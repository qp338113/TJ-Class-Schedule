import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../domain/notification_settings.dart';
import '../notifications/notification_service.dart';
import 'magic_os_guide_page.dart';
import 'tutorial_page.dart';

class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(notificationSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('提醒设置')),
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('设置加载失败')),
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('上课提醒'),
                    subtitle: const Text('关闭后会取消所有待发送提醒'),
                    value: settings.enabled,
                    onChanged: (value) =>
                        _update(ref, settings.copyWith(enabled: value)),
                  ),
                  const Divider(height: 1, indent: 16),
                  SwitchListTile(
                    title: const Text('上课中延后提醒'),
                    subtitle: const Text('提醒时间正在上课时，改到下课 3 分钟后'),
                    value: settings.delayWhenInClass,
                    onChanged: settings.enabled
                        ? (value) => _update(
                            ref,
                            settings.copyWith(delayWhenInClass: value),
                          )
                        : null,
                  ),
                  const Divider(height: 1, indent: 16),
                  SwitchListTile(
                    title: const Text('锁屏显示下一节课'),
                    subtitle: const Text('上课前 1 小时显示科目、时间、地点和教师'),
                    value: settings.showNextCourseOnLockScreen,
                    onChanged: settings.enabled
                        ? (value) => _update(
                            ref,
                            settings.copyWith(
                              showNextCourseOnLockScreen: value,
                            ),
                          )
                        : null,
                  ),
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    enabled: settings.enabled,
                    title: const Text('提醒方式'),
                    subtitle: Text(_alertModeLabel(settings.alertMode)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: settings.enabled
                        ? () => _selectAlertMode(context, ref, settings)
                        : null,
                  ),
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    enabled: settings.enabled,
                    title: const Text('提前时间'),
                    subtitle: const Text('可设置 1 到 1440 分钟'),
                    trailing: Text('${settings.advanceMinutes} 分钟'),
                    onTap: settings.enabled
                        ? () => _editAdvanceMinutes(context, ref, settings)
                        : null,
                  ),
                  const Divider(height: 1, indent: 16),
                  SwitchListTile(
                    title: const Text('仅提醒下一节'),
                    subtitle: const Text('未来 7 天只保留时间最近的一条提醒'),
                    value: settings.onlyNextCourse,
                    onChanged: settings.enabled
                        ? (value) => _update(
                            ref,
                            settings.copyWith(onlyNextCourse: value),
                          )
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('系统权限', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text('通知权限'),
                    subtitle: const Text('如果收不到提醒，请在系统中检查'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ref
                        .read(notificationServiceProvider)
                        .openNotificationSettings(),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.alarm_on_outlined),
                    title: const Text('精确闹钟权限'),
                    subtitle: const Text('保证息屏时也能准点提醒'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ref
                        .read(notificationServiceProvider)
                        .requestAndroidPermissions(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ReminderStatusCard(settings: settings),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const TutorialPage()),
              ),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('查看使用教程'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const MagicOsGuidePage(showBackButton: true),
                ),
              ),
              icon: const Icon(Icons.battery_saver_outlined),
              label: const Text('查看国产 Android 后台设置'),
            ),
            const SizedBox(height: 24),
            Text('联系作者', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Card(
              child: Column(
                children: [
                  ListTile(title: Text('QQ'), trailing: Text('22725876')),
                  Divider(height: 1, indent: 16),
                  ListTile(title: Text('微信'), trailing: Text('LJ-QWQ1144')),
                  Divider(height: 1, indent: 16),
                  ListTile(title: Text('反馈群'), trailing: Text('1103397369')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _update(WidgetRef ref, NotificationSettings settings) {
    return ref
        .read(notificationSettingsProvider.notifier)
        .saveSettings(settings);
  }

  Future<void> _editAdvanceMinutes(
    BuildContext context,
    WidgetRef ref,
    NotificationSettings settings,
  ) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) =>
          _AdvanceMinutesDialog(initialValue: settings.advanceMinutes),
    );
    if (value != null) {
      await _update(ref, settings.copyWith(advanceMinutes: value));
    }
  }

  Future<void> _selectAlertMode(
    BuildContext context,
    WidgetRef ref,
    NotificationSettings settings,
  ) async {
    final selected = await showModalBottomSheet<ReminderAlertMode>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('选择上课提醒方式'),
              subtitle: Text('锁屏课表通知始终不会发出声音或震动。'),
            ),
            for (final mode in ReminderAlertMode.values)
              ListTile(
                title: Text(_alertModeLabel(mode)),
                trailing: mode == settings.alertMode
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, mode),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await _update(ref, settings.copyWith(alertMode: selected));
    }
  }
}

class _ReminderStatusCard extends ConsumerStatefulWidget {
  const _ReminderStatusCard({required this.settings});

  final NotificationSettings settings;

  @override
  ConsumerState<_ReminderStatusCard> createState() =>
      _ReminderStatusCardState();
}

class _ReminderStatusCardState extends ConsumerState<_ReminderStatusCard> {
  late Future<({bool notifications, bool exact, int pending})> _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _status = _loadStatus();
  }

  Future<({bool notifications, bool exact, int pending})> _loadStatus() async {
    try {
      final service = ref.read(notificationServiceProvider);
      final values = await Future.wait([
        service.notificationsEnabled(),
        service.canScheduleExactNotifications(),
        service.pendingNotificationCount(),
      ]);
      return (
        notifications: values[0] as bool,
        exact: values[1] as bool,
        pending: values[2] as int,
      );
    } catch (_) {
      return (notifications: false, exact: false, pending: 0);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '提醒状态检查',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '重新检查',
                onPressed: () => setState(_refresh),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          FutureBuilder<({bool notifications, bool exact, int pending})>(
            future: _status,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final value = snapshot.data!;
              return Text(
                '通知权限：${value.notifications ? '正常' : '未开启'}\n'
                '精确闹钟：${value.exact ? '正常' : '未开启'}\n'
                '当前已排程：${value.pending} 条',
              );
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await ref
                  .read(notificationServiceProvider)
                  .sendTestNotification(widget.settings);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('测试通知已发送，请查看通知栏')));
              }
            },
            icon: const Icon(Icons.notification_add_outlined),
            label: const Text('发送测试通知'),
          ),
        ],
      ),
    ),
  );
}

String _alertModeLabel(ReminderAlertMode mode) => switch (mode) {
  ReminderAlertMode.notificationOnly => '仅通知',
  ReminderAlertMode.vibration => '通知 + 震动',
  ReminderAlertMode.soundAndVibration => '通知 + 震动 + 声音',
};

class _AdvanceMinutesDialog extends StatefulWidget {
  const _AdvanceMinutesDialog({required this.initialValue});

  final int initialValue;

  @override
  State<_AdvanceMinutesDialog> createState() => _AdvanceMinutesDialogState();
}

class _AdvanceMinutesDialogState extends State<_AdvanceMinutesDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialValue}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置提前时间'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: '分钟数',
          helperText: '例如：45 表示提前 45 分钟',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  void _submit() {
    final value = int.tryParse(_controller.text);
    if (value == null || value < 1 || value > 1440) {
      setState(() => _error = '请输入 1 到 1440');
      return;
    }
    Navigator.pop(context, value);
  }
}
