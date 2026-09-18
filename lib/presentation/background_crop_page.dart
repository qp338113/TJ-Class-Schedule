import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 背景图裁剪页：在一个与屏幕同比例的取景框里拖动/缩放图片，框内所见即最终效果。
///
/// 顶部可切换遮罩预览——主界面会在背景图上叠一层固定的半透明黑遮罩，
/// 打开遮罩时看到的就是实际观感。确认后返回裁剪好的 PNG 字节（取消返回 null）。
class BackgroundCropPage extends StatefulWidget {
  const BackgroundCropPage({
    required this.imageBytes,
    this.overlayOpacity = 0.55,
    this.cardOpacity = 1.0,
    super.key,
  });

  final Uint8List imageBytes;

  /// 主界面遮罩浓度，用于预览时还原真实观感。
  final double overlayOpacity;

  /// 课程卡片不透明度，用于预览时还原真实观感。
  final double cardOpacity;

  @override
  State<BackgroundCropPage> createState() => _BackgroundCropPageState();
}

class _BackgroundCropPageState extends State<BackgroundCropPage> {
  final _controller = TransformationController();
  ui.Image? _image;
  String? _error;
  bool _showOverlay = true;
  bool _busy = false;

  /// 输出图片的最大边长，避免整张 4K 图原样存进手机。
  static const _maxOutputSide = 2400.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '无法读取这张图片，请换一张');
    }
  }

  Future<void> _confirm(Size frame) async {
    final image = _image;
    if (image == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await cropBackgroundImage(
        image: image,
        matrix: _controller.value,
        frame: frame,
        maxOutputSide: _maxOutputSide,
      );
      if (!mounted) return;
      Navigator.pop(context, bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '裁剪失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      appBar: AppBar(
        title: const Text('裁剪背景图'),
        actions: [
          if (image != null)
            IconButton(
              tooltip: _showOverlay ? '隐藏遮罩预览' : '显示遮罩预览',
              onPressed: () => setState(() => _showOverlay = !_showOverlay),
              icon: Icon(
                _showOverlay
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : image == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final frame = _frameSize(context, constraints);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Text(
                        '拖动或双指缩放，让框内显示你想要的部分。'
                        '框内的样子就是主界面的实际效果。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _CropFrame(
                          controller: _controller,
                          frame: frame,
                          showOverlay: _showOverlay,
                          overlayColor: Color.fromRGBO(
                            0,
                            0,
                            0,
                            widget.overlayOpacity.clamp(0.0, 1.0),
                          ),
                          preview: _showOverlay
                              ? _TimetablePreview(
                                  cardOpacity: widget.cardOpacity,
                                )
                              : null,
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _confirm(frame),
                                child: const Text('使用这一部分'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  /// 取景框尺寸：与整屏同比例，并缩放到可用区域内。
  Size _frameSize(BuildContext context, BoxConstraints constraints) {
    final screen = MediaQuery.sizeOf(context);
    final ratio = screen.width / screen.height;
    var width = constraints.maxWidth - 24;
    var height = width / ratio;
    if (height > constraints.maxHeight - 12) {
      height = constraints.maxHeight - 12;
      width = height * ratio;
    }
    return Size(width, height);
  }
}

class _CropFrame extends StatelessWidget {
  const _CropFrame({
    required this.controller,
    required this.frame,
    required this.showOverlay,
    required this.overlayColor,
    required this.preview,
    required this.child,
  });

  final TransformationController controller;
  final Size frame;
  final bool showOverlay;
  final Color overlayColor;

  /// 叠在遮罩之上、按真实不透明度绘制的课表示意，用来判断文字是否看得清。
  final Widget? preview;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: frame.width,
      height: frame.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              transformationController: controller,
              minScale: 1,
              maxScale: 6,
              clipBehavior: Clip.none,
              child: child,
            ),
            if (showOverlay)
              IgnorePointer(child: ColoredBox(color: overlayColor)),
            if (preview != null) preview!,
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 取景框内的课表示意：让用户直接看到「背景图 + 遮罩 + 课程卡片」叠起来之后
/// 文字是否清楚，不用来回切到主界面反复试。
class _TimetablePreview extends StatelessWidget {
  const _TimetablePreview({required this.cardOpacity});

  final double cardOpacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部标题栏与标签栏的示意。
            Row(
              children: [
                Expanded(
                  child: Text(
                    '9月18日 · 第 4 周',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  '今日',
                  style: TextStyle(fontSize: 11, color: scheme.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _previewCard(scheme, '高等数学', '08:00-09:40 · 南129', 0xFF7D9DCE),
            const SizedBox(height: 6),
            _previewCard(scheme, '大学物理B2', '10:00-11:40 · 瑞安楼阶1', 0xFF7FB69D),
            const SizedBox(height: 6),
            _previewCard(scheme, '英语写作III', '13:30-15:10 · 彰武北 409', 0xFFD0B36C),
          ],
        ),
      ),
    );
  }

  Widget _previewCard(
    ColorScheme scheme,
    String title,
    String subtitle,
    int colorValue,
  ) {
    final color = Color(colorValue);
    return DecoratedBox(
      decoration: BoxDecoration(
        // 按用户设置的卡片不透明度绘制，所见即主界面所得。
        color: scheme.surface.withValues(alpha: cardOpacity),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 把取景框内的内容裁剪成 PNG 字节。
///
/// [matrix] 是取景框内的变换（子坐标 → 取景框坐标）。取景框尺寸为 [frame]，
/// 原图尺寸取自 [image]，子控件用 `BoxFit.cover` 摆放，所以先反推出取景框在
/// 原图上的对应矩形，再按该矩形重新绘制。抽成独立函数便于直接测试裁剪数学。
Future<Uint8List> cropBackgroundImage({
  required ui.Image image,
  required Matrix4 matrix,
  required Size frame,
  double maxOutputSide = 2400,
}) async {
  final rect = cropRectFor(matrix: matrix, frame: frame, image: image);
  final scale = (maxOutputSide / (rect.width > rect.height ? rect.width : rect.height))
      .clamp(0.0, 1.0);
  final outputWidth = (rect.width * scale).round().clamp(1, 1 << 16);
  final outputHeight = (rect.height * scale).round().clamp(1, 1 << 16);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    rect,
    Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final cropped = await picture.toImage(outputWidth, outputHeight);
  picture.dispose();
  try {
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('无法编码裁剪结果');
    return data.buffer.asUint8List();
  } finally {
    cropped.dispose();
  }
}

/// 计算取景框对应的原图矩形（原图坐标系，已按原图边界收拢）。
Rect cropRectFor({
  required Matrix4 matrix,
  required Size frame,
  required ui.Image image,
}) {
  final imageWidth = image.width.toDouble();
  final imageHeight = image.height.toDouble();
  // 子控件用 BoxFit.cover：等比放大到铺满取景框，多出的部分居中裁掉。
  final coverScale = (frame.width / imageWidth) > (frame.height / imageHeight)
      ? frame.width / imageWidth
      : frame.height / imageHeight;
  final displayedWidth = imageWidth * coverScale;
  final displayedHeight = imageHeight * coverScale;
  final offsetX = (frame.width - displayedWidth) / 2;
  final offsetY = (frame.height - displayedHeight) / 2;

  // 取景框四角映射回子坐标（只含缩放与平移，矩形保持矩形）。
  final inverse = Matrix4.inverted(matrix);
  final storage = inverse.storage;
  Offset toChild(double x, double y) => Offset(
    storage[0] * x + storage[4] * y + storage[12],
    storage[1] * x + storage[5] * y + storage[13],
  );
  final topLeft = toChild(0, 0);
  final bottomRight = toChild(frame.width, frame.height);

  double toImageX(double childX) =>
      ((childX - offsetX) / coverScale).clamp(0.0, imageWidth);
  double toImageY(double childY) =>
      ((childY - offsetY) / coverScale).clamp(0.0, imageHeight);

  final left = toImageX(topLeft.dx);
  final top = toImageY(topLeft.dy);
  final right = toImageX(bottomRight.dx);
  final bottom = toImageY(bottomRight.dy);
  // 极端缩放或平移时左右/上下可能互换或塌缩到边界外。先归一顺序，再收拢到
  // 原图范围内并保证至少 1px：直接对可能反转的区间取 clamp 会抛 Invalid argument。
  final minX = math.min(left, right).clamp(0.0, imageWidth - 1);
  final minY = math.min(top, bottom).clamp(0.0, imageHeight - 1);
  final maxX = math.max(left, right).clamp(minX + 1, imageWidth);
  final maxY = math.max(top, bottom).clamp(minY + 1, imageHeight);
  return Rect.fromLTWH(minX, minY, maxX - minX, maxY - minY);
}
