import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/task_state.dart';
import '../notifications/notification_service.dart';

class TaskReminderSettingsPage extends ConsumerStatefulWidget {
  const TaskReminderSettingsPage({super.key});
  @override
  ConsumerState<TaskReminderSettingsPage> createState() =>
      _TaskReminderSettingsPageState();
}

class _TaskReminderSettingsPageState
    extends ConsumerState<TaskReminderSettingsPage> {
  final _hours = TextEditingController();
  bool? _enabled;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final hours = int.tryParse(_hours.text.trim());
    if (hours == null || hours < 1 || hours > 8760) {
      setState(() => _error = '请输入 1–8760 的整小时数');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_enabled == true) {
        final service = ref.read(notificationServiceProvider);
        await service.requestAndroidPermissions();
        if (!await service.notificationsEnabled()) {
          if (!mounted) return;
          setState(() => _error = '系统通知尚未允许，请先打开系统通知设置');
          return;
        }
      }
      await ref
          .read(taskReminderSettingsProvider.notifier)
          .save(TaskReminderSettings(enabled: _enabled!, hours: hours));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('作业提醒设置已保存')));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '设置未保存，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(taskReminderSettingsProvider);
    final settings = value.valueOrNull;
    if (settings != null && _enabled == null) {
      _enabled = settings.enabled;
      _hours.text = '${settings.hours}';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('作业截止提醒')),
      body: settings == null
          ? Center(
              child: value.hasError
                  ? const Text('读取设置失败，请重新进入')
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开启作业截止通知'),
                  value: _enabled!,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
                const Text('统一提醒所有未完成且有截止时间的作业。'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final hours in [1, 3, 6, 12, 24, 48])
                      ChoiceChip(
                        label: Text('$hours 小时'),
                        selected: _hours.text == '$hours',
                        onSelected: _saving
                            ? null
                            : (_) => setState(() => _hours.text = '$hours'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _hours,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '截止前几小时提醒',
                    helperText: '自定义 1–8760 整小时',
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '只预约未来的提醒时间，已错过的提前时间不补发。完成或删除作业会取消其预约。系统省电策略可能推迟通知。',
                ),
                TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(notificationServiceProvider)
                        .openNotificationSettings();
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('系统通知设置'),
                ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中' : '保存'),
                ),
              ],
            ),
    );
  }
}
