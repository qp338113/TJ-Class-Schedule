import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';

class MagicOsGuidePage extends ConsumerStatefulWidget {
  const MagicOsGuidePage({super.key, this.showBackButton = false});

  final bool showBackButton;

  @override
  ConsumerState<MagicOsGuidePage> createState() => _MagicOsGuidePageState();
}

class _MagicOsGuidePageState extends ConsumerState<MagicOsGuidePage> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.showBackButton || _confirmed,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: widget.showBackButton,
          title: const Text('让提醒准时到达'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              '国产 Android 系统通常会限制后台应用。请完成下面两项通用设置，再参考下方与你手机品牌对应的路径，否则锁屏后提醒可能延迟。',
              style: TextStyle(
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            const _GuideStep(
              number: '1',
              icon: Icons.rocket_launch_outlined,
              title: '允许应用自动启动',
              lines: [
                '在系统设置中搜索“自启动”或“应用启动管理”',
                '找到“离线课程表”并关闭自动管理',
                '允许自启动、允许关联启动、允许后台活动全部打开',
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openApplicationSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('打开本应用系统设置'),
            ),
            const SizedBox(height: 22),
            const _GuideStep(
              number: '2',
              icon: Icons.battery_charging_full_outlined,
              title: '忽略电池优化',
              lines: [
                '在系统设置中搜索“电池优化”或“后台耗电管理”',
                '找到“离线课程表”',
                '选择不优化、无限制或允许后台高耗电',
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openBatteryOptimizationSettings,
              icon: const Icon(Icons.battery_saver_outlined),
              label: const Text('打开忽略电池优化列表'),
            ),
            const SizedBox(height: 26),
            Text('各品牌常见路径', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              '系统版本不同，菜单名称可能略有变化；找不到时可直接在设置顶部搜索关键词。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            const _VendorPaths(),
            const SizedBox(height: 30),
            FilledButton(
              onPressed: () => _complete(context, ref),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('我已设置好'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final current = ref.read(notificationSettingsProvider).valueOrNull;
    if (current == null) return;
    await ref
        .read(notificationSettingsProvider.notifier)
        .saveSettings(current.copyWith(magicOsGuideCompleted: true));
    if (!context.mounted) return;
    setState(() => _confirmed = true);
    Navigator.pop(context);
  }

  Future<void> _openApplicationSettings() {
    return const AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:com.offlinecourse.offline_course_schedule',
    ).launch();
  }

  Future<void> _openBatteryOptimizationSettings() {
    return const AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
    ).launch();
  }
}

class _VendorPaths extends StatelessWidget {
  const _VendorPaths();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: const [
          _VendorTile(
            name: '荣耀 · MagicOS',
            path: '设置 > 电池 > 应用启动管理；关闭自动管理并打开三个开关',
          ),
          _VendorTile(
            name: '华为 · EMUI / HarmonyOS',
            path: '设置 > 应用和服务 > 应用启动管理；改为手动管理并打开三个开关',
          ),
          _VendorTile(
            name: '小米 / Redmi · HyperOS / MIUI',
            path: '设置 > 应用设置 > 应用管理 > 离线课程表；开启自启动，省电策略选“无限制”',
          ),
          _VendorTile(
            name: 'OPPO / 一加 / realme · ColorOS',
            path: '设置 > 应用 > 自启动；允许离线课程表自启动和后台活动',
          ),
          _VendorTile(
            name: 'vivo / iQOO · OriginOS',
            path: '设置 > 应用与权限 > 权限管理 > 自启动；后台耗电管理选“允许后台高耗电”',
          ),
          _VendorTile(name: '魅族 · Flyme', path: '设置 > 应用管理 > 权限管理；允许自启动和后台运行'),
        ],
      ),
    );
  }
}

class _VendorTile extends StatelessWidget {
  const _VendorTile({required this.name, required this.path});

  final String name;
  final String path;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      dense: true,
      title: Text(name, style: const TextStyle(fontSize: 13)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(path, style: const TextStyle(fontSize: 12, height: 1.5)),
        ),
      ],
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.lines,
  });

  final String number;
  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              child: Text(
                number,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...lines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• $line',
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
