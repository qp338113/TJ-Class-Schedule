import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import 'background_crop_page.dart';

/// 主界面主题色的预设色板：沿用课程卡片原有的 6 色，再扩展 6 色。
const _presetColors = [
  0xFF607D8B, // 蓝灰（默认）
  0xFF7D9DCE, // 天蓝
  0xFF6FAFB5, // 青
  0xFF7FB69D, // 绿
  0xFF9BAF6E, // 橄榄
  0xFFD0B36C, // 金黄
  0xFFE0A34E, // 橙
  0xFFD19A8A, // 陶土
  0xFFE08A9A, // 玫瑰
  0xFFC586C0, // 品红
  0xFFB497C9, // 紫
  0xFF8E8AD1, // 靛蓝
];

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seedColor =
        ref.watch(themeSeedColorProvider).valueOrNull ??
        ThemeSeedColorController.defaultColorValue;
    final backgroundPath = ref.watch(backgroundImagePathProvider).valueOrNull;
    final overlayOpacity =
        ref.watch(backgroundOverlayOpacityProvider).valueOrNull ??
        BackgroundOverlayOpacityController.defaultOpacity;
    final cardOpacity =
        ref.watch(cardOpacityProvider).valueOrNull ??
        CardOpacityController.defaultOpacity;
    final widgetColor = ref.watch(widgetColorProvider).valueOrNull;
    final refreshMode =
        ref.watch(widgetRefreshModeProvider).valueOrNull ??
        WidgetRefreshModeController.defaultMode;
    return Scaffold(
      appBar: AppBar(title: const Text('外观设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ListTile(
                  title: Text('主题色'),
                  subtitle: Text('只影响主色，背景色、卡片色与文字色保持原样'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final value in _presetColors)
                        _ColorSwatch(
                          colorValue: value,
                          selected: value == seedColor,
                          onTap: () => ref
                              .read(themeSeedColorProvider.notifier)
                              .saveSettings(value),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('自定义颜色'),
                  subtitle: const Text('用色相、饱和度、亮度滑杆自己调'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pickCustomColor(context, ref, seedColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  '背景图',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              // 该功能仍在打磨中，先给出明确提示，避免用户以为已经稳定可用。
              const _WorkInProgressBadge(),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.wallpaper_outlined),
                  title: const Text('主界面背景图'),
                  subtitle: Text(
                    backgroundPath == null
                        ? '未设置，深色与浅色模式共用同一张图'
                        : '已设置，深色与浅色模式共用同一张图',
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('选择图片'),
                  subtitle: const Text('图片保存在本机，不会进入备份'),
                  onTap: () => _pickImage(context, ref),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  enabled: backgroundPath != null,
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('移除背景图'),
                  onTap: backgroundPath == null
                      ? null
                      : () => _clearImage(context, ref),
                ),
                const Divider(height: 1, indent: 56),
                _OpacitySlider(
                  key: const ValueKey('background-overlay-slider'),
                  title: '遮罩浓度',
                  subtitle: '提高可让课程文字更清楚；降低可让背景图更明显',
                  value: overlayOpacity,
                  min: 0,
                  max: 1,
                  enabled: backgroundPath != null,
                  onChanged: (value) => ref
                      .read(backgroundOverlayOpacityProvider.notifier)
                      .saveSettings(value),
                ),
                const Divider(height: 1, indent: 56),
                _OpacitySlider(
                  key: const ValueKey('card-opacity-slider'),
                  title: '课表透明度',
                  subtitle: '降低可透出背景图，最低仍保证文字可读',
                  value: cardOpacity,
                  min: CardOpacityController.minOpacity,
                  max: 1,
                  enabled: backgroundPath != null,
                  onChanged: (value) => ref
                      .read(cardOpacityProvider.notifier)
                      .saveSettings(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('小组件颜色', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: _WidgetColorSwatch(
                    key: const ValueKey('widget-color-default'),
                    colorValue: _defaultWidgetBackground,
                    selected: widgetColor == null,
                    onTap: () => ref
                        .read(widgetColorProvider.notifier)
                        .saveSettings(null),
                  ),
                  title: const Text('使用默认（跟随系统浅色外观）'),
                  subtitle: const Text(
                    '只影响小组件的普通状态，临近上课时的提醒色不受影响',
                  ),
                  trailing: widgetColor == null
                      ? const Icon(Icons.done_rounded)
                      : null,
                ),
                const Divider(height: 1, indent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final value in _presetColors)
                        _WidgetColorSwatch(
                          key: ValueKey('widget-color-$value'),
                          colorValue: value,
                          selected: value == widgetColor,
                          onTap: () => ref
                              .read(widgetColorProvider.notifier)
                              .saveSettings(value),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('自定义小组件颜色'),
                  subtitle: const Text('用色相、饱和度、亮度滑杆自己调'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pickCustomWidgetColor(context, ref, widgetColor),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('倒计时刷新频率'),
                  subtitle: Text(
                    '${refreshMode.label} · ${_refreshModeHint(refreshMode)}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pickRefreshMode(context, ref, refreshMode),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _refreshModeHint(WidgetRefreshMode mode) => switch (mode) {
    WidgetRefreshMode.powerSaving => '更省电，数字可能有几分钟不准',
    WidgetRefreshMode.normal => '每分钟刷新，耗电适中',
    WidgetRefreshMode.precise => '每秒刷新，最准但最耗电',
  };

  Future<void> _pickRefreshMode(
    BuildContext context,
    WidgetRef ref,
    WidgetRefreshMode current,
  ) async {
    final selected = await showModalBottomSheet<WidgetRefreshMode>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('倒计时刷新频率'),
              subtitle: Text('刷新越频繁，倒计时越准，耗电也越多。'),
            ),
            for (final mode in WidgetRefreshMode.values)
              ListTile(
                key: ValueKey('refresh-mode-${mode.name}'),
                title: Text(mode.label),
                subtitle: Text(_refreshModeHint(mode)),
                trailing: mode == current
                    ? const Icon(Icons.done_rounded)
                    : null,
                onTap: () => Navigator.pop(context, mode),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await ref.read(widgetRefreshModeProvider.notifier).saveSettings(selected);
  }

  Future<void> _pickCustomColor(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (_) => _HslColorDialog(initialColorValue: current),
    );
    if (selected == null) return;
    await ref.read(themeSeedColorProvider.notifier).saveSettings(selected);
  }

  Future<void> _pickCustomWidgetColor(
    BuildContext context,
    WidgetRef ref,
    int? current,
  ) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (_) => _HslColorDialog(
        initialColorValue: current ?? _defaultWidgetBackground,
        title: '自定义小组件颜色',
      ),
    );
    if (selected == null) return;
    await ref.read(widgetColorProvider.notifier).saveSettings(selected);
  }

  Future<void> _pickImage(BuildContext context, WidgetRef ref) async {
    Uint8List? bytes;
    try {
      bytes = await ref.read(backgroundImageSourceProvider).pickBytes();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法读取这张图片，请换一张')));
      return;
    }
    // 用户取消选图。
    if (bytes == null) return;
    if (!context.mounted) return;

    // 先让用户在取景框里截取并预览实际效果，确认后才落盘。
    final cropped = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute<Uint8List>(
        builder: (_) => BackgroundCropPage(
          imageBytes: bytes!,
          // 用当前设置还原真实观感，避免选完才发现文字看不清。
          overlayOpacity:
              ref.read(backgroundOverlayOpacityProvider).valueOrNull ??
              BackgroundOverlayOpacityController.defaultOpacity,
          cardOpacity:
              ref.read(cardOpacityProvider).valueOrNull ??
              CardOpacityController.defaultOpacity,
        ),
      ),
    );
    if (cropped == null) return;

    try {
      await ref
          .read(backgroundImagePathProvider.notifier)
          .saveBackgroundImage(cropped);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('背景图已设置')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法保存这张图片，请换一张')));
    }
  }

  Future<void> _clearImage(BuildContext context, WidgetRef ref) async {
    await ref.read(backgroundImagePathProvider.notifier).clearBackgroundImage();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已移除背景图')));
  }
}

/// 未自定义小组件颜色时，原生侧使用的默认浅色背景。
/// 与 `android/app/src/main/res/drawable/widget_background.xml` 的 solid 色一致。
const _defaultWidgetBackground = 0xFFF8FAFC;

/// 「开发中，暂不建议使用」提示。用在仍在打磨的功能旁边，避免用户误以为是
/// 稳定功能。
class _WorkInProgressBadge extends StatelessWidget {
  const _WorkInProgressBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_rounded,
            size: 13,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 4),
          Text(
            '开发中，暂不建议使用',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// 透明度滑杆：左侧标题与说明，右侧显示当前百分比，下面一条滑杆。
class _OpacitySlider extends StatelessWidget {
  const _OpacitySlider({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = enabled
        ? null
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor ?? theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: textColor),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            // 分成 20 档，拖动时手感稳、不会出现 0.4712 这种零碎值。
            divisions: 20,
            label: '${(value * 100).round()}%',
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

/// 小组件颜色的色块。做成圆角方块，与上面主题色的圆形色块区分开。
class _WidgetColorSwatch extends StatelessWidget {
  const _WidgetColorSwatch({
    super.key,
    required this.colorValue,
    required this.selected,
    required this.onTap,
  });

  final int colorValue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Color(colorValue),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : const Color(0x33000000),
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.colorValue,
    required this.selected,
    required this.onTap,
  });

  final int colorValue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: CircleAvatar(
          backgroundColor: Color(colorValue),
          radius: 18,
          child: selected
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _HslColorDialog extends StatefulWidget {
  const _HslColorDialog({
    required this.initialColorValue,
    this.title = '自定义主题色',
  });

  final int initialColorValue;
  final String title;

  @override
  State<_HslColorDialog> createState() => _HslColorDialogState();
}

class _HslColorDialogState extends State<_HslColorDialog> {
  late final HSLColor _initial;
  late double _hue;
  late double _saturation;
  late double _lightness;

  /// 用户是否真的动过滑杆。没动过就原样返回初始色，
  /// 避免 HSL 往返换算带来的细微色差。
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _initial = HSLColor.fromColor(Color(widget.initialColorValue));
    _hue = _initial.hue;
    _saturation = _initial.saturation;
    _lightness = _initial.lightness;
  }

  Color get _preview =>
      HSLColor.fromAHSL(1, _hue, _saturation, _lightness).toColor();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _preview,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _slider('色相', _hue, 0, 360, (value) => _hue = value),
            _slider(
              '饱和度',
              _saturation,
              0,
              1,
              (value) => _saturation = value,
            ),
            _slider(
              '亮度',
              _lightness,
              0,
              1,
              (value) => _lightness = value,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _changed ? _preview.toARGB32() : widget.initialColorValue,
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 48, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: (next) => setState(() {
              _changed = true;
              onChanged(next);
            }),
          ),
        ),
      ],
    );
  }
}
