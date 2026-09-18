import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/presentation/background_crop_page.dart';

void main() {
  // 裁剪数学是纯函数，但需要一个 ui.Image 提供原图尺寸。
  // 用 4x2 的纯色位图即可，只关心宽高。
  late ui.Image image;

  setUpAll(() async {
    final pixels = Uint8List(4 * 2 * 4);
    for (var index = 0; index < 4 * 2; index++) {
      pixels[index * 4] = 255;
      pixels[index * 4 + 3] = 255;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, 4, 2, ui.PixelFormat.rgba8888, (result) {
      completer.complete(result);
    });
    image = await completer.future;
  });

  tearDownAll(() => image.dispose());

  group('取景框映射回原图矩形', () {
    test('未缩放时取景框等于整张图的可见区域', () {
      // 取景框 4:2 与原图同比例，cover 不产生额外裁切，映射结果应为整张图。
      const frame = Size(200, 100);
      final rect = cropRectFor(
        matrix: Matrix4.identity(),
        frame: frame,
        image: image,
      );

      expect(rect.left, closeTo(0, 0.001));
      expect(rect.top, closeTo(0, 0.001));
      expect(rect.width, closeTo(4, 0.001));
      expect(rect.height, closeTo(2, 0.001));
    });

    test('横向放大两倍后只取中间一半宽度', () {
      const frame = Size(200, 100);
      // 以取景框中心为锚点放大 2 倍，可见区域缩小到一半。
      final matrix = Matrix4.identity()
        ..translateByDouble(100, 50, 0, 1)
        ..scaleByDouble(2, 2, 1, 1)
        ..translateByDouble(-100, -50, 0, 1);
      final rect = cropRectFor(matrix: matrix, frame: frame, image: image);

      expect(rect.width, closeTo(2, 0.001));
      expect(rect.height, closeTo(1, 0.001));
      // 居中缩放，取的是正中间那块。
      expect(rect.center.dx, closeTo(2, 0.001));
      expect(rect.center.dy, closeTo(1, 0.001));
    });

    test('平移后取到的区域跟着移动且不出原图边界', () {
      const frame = Size(200, 100);
      // 放大 2 倍后往左上拖：视野应贴到原图左上角，不会越界成负值。
      final matrix = Matrix4.identity()
        ..translateByDouble(100, 50, 0, 1)
        ..scaleByDouble(2, 2, 1, 1)
        ..translateByDouble(-100, -50, 0, 1)
        ..translateByDouble(-500, -500, 0, 1);
      final rect = cropRectFor(matrix: matrix, frame: frame, image: image);

      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(4.001));
      expect(rect.bottom, lessThanOrEqualTo(2.001));
    });

    test('取景框比原图更宽时，cover 会裁掉原图上下', () {
      // 取景框 4:1 比原图 2:1 更宽，cover 按宽度铺满，高度方向被裁。
      const frame = Size(400, 100);
      final rect = cropRectFor(
        matrix: Matrix4.identity(),
        frame: frame,
        image: image,
      );

      expect(rect.left, closeTo(0, 0.001));
      expect(rect.width, closeTo(4, 0.001));
      // 高度被裁到取景框比例对应的值：4 * (100/400) = 1。
      expect(rect.height, closeTo(1, 0.001));
    });
  });

  test('裁剪结果是非空 PNG 字节', () async {
    final bytes = await cropBackgroundImage(
      image: image,
      matrix: Matrix4.identity(),
      frame: const Size(200, 100),
    );

    expect(bytes, isNotEmpty);
    // PNG 魔数，确认真的编码成图片而不是空缓冲。
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('输出尺寸受最大边长约束', () async {
    final bytes = await cropBackgroundImage(
      image: image,
      matrix: Matrix4.identity(),
      frame: const Size(200, 100),
      // 原图只有 4x2，这里给一个比它还小的上限，确认缩放生效。
      maxOutputSide: 2,
    );

    // 直接解码回来核对尺寸，避免只看字节长度这种弱断言。
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, lessThanOrEqualTo(2));
    expect(frame.image.height, lessThanOrEqualTo(2));
    frame.image.dispose();
  });

  testWidgets('裁剪页能加载图片并显示取景框与遮罩预览开关', (tester) async {
    // 图片解码是真实异步 I/O，在 flutter_test 的 fake-async 里不会自行完成，
    // 必须放进 runAsync，否则测试会一直等下去。
    late Uint8List source;
    await tester.runAsync(() async {
      source = await _pngBytes(4, 2);
    });

    await tester.pumpWidget(
      MaterialApp(home: BackgroundCropPage(imageBytes: source)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('裁剪背景图'), findsOneWidget);
    expect(find.text('使用这一部分'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    // 默认开启遮罩预览，标题栏有切换按钮。
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('图片损坏时给出中文提示而不是崩溃', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackgroundCropPage(imageBytes: Uint8List.fromList([1, 2, 3])),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('无法读取这张图片，请换一张'), findsOneWidget);
  });
}

/// 编码一张指定尺寸的纯色 PNG。
Future<Uint8List> _pngBytes(int width, int height) async {
  final pixels = Uint8List(width * height * 4);
  for (var index = 0; index < width * height; index++) {
    pixels[index * 4] = 120;
    pixels[index * 4 + 1] = 90;
    pixels[index * 4 + 2] = 190;
    pixels[index * 4 + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (
    result,
  ) {
    completer.complete(result);
  });
  final decoded = await completer.future;
  try {
    final data = await decoded.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    decoded.dispose();
  }
}
