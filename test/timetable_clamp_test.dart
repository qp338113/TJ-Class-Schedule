import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/presentation/full_timetable_page.dart';

void main() {
  // 内容 900x600，视口 400x800。
  const content = Size(900, 600);
  const viewport = Size(400, 800);

  group('平移边界夹紧', () {
    test('内容比视口宽时，横向夹在 [视口宽-内容宽, 0]', () {
      // 放大到 0.5：内容变成 450x300，横向可滑 50px。
      const scale = 0.5;
      expect(
        clampTimetableOffset(
          offset: const Offset(100, 0),
          scale: scale,
          content: content,
          viewport: viewport,
        ).dx,
        0,
        reason: '往右拖超过左边界应收回到 0',
      );
      expect(
        clampTimetableOffset(
          offset: const Offset(-500, 0),
          scale: scale,
          content: content,
          viewport: viewport,
        ).dx,
        closeTo(400 - 450, 0.001),
        reason: '往左拖超过右边界应收回到最右',
      );
      expect(
        clampTimetableOffset(
          offset: const Offset(-20, 0),
          scale: scale,
          content: content,
          viewport: viewport,
        ).dx,
        -20,
        reason: '范围内不动',
      );
    });

    test('内容比视口小时那一侧居中，不留下偏移空档', () {
      // 缩到 0.3：内容 270x180，横向小于 400，纵向小于 800。
      const scale = 0.3;
      final offset = clampTimetableOffset(
        offset: const Offset(-80, 120),
        scale: scale,
        content: content,
        viewport: viewport,
      );
      expect(offset.dx, closeTo((400 - 270) / 2, 0.001));
      expect(offset.dy, closeTo((800 - 180) / 2, 0.001));
    });

    test('两轴独立夹紧：一轴可滑、另一轴居中', () {
      // 缩到 0.6：内容 540x360。横向 540>400 可滑；纵向 360<800 居中。
      const scale = 0.6;
      final offset = clampTimetableOffset(
        offset: const Offset(-60, -200),
        scale: scale,
        content: content,
        viewport: viewport,
      );
      expect(offset.dx, -60, reason: '横向在范围内保持');
      expect(offset.dy, closeTo((800 - 360) / 2, 0.001), reason: '纵向居中');
    });

    test('恰好等于视口时不产生偏移', () {
      // 内容 400x800 正好等于视口。
      final offset = clampTimetableOffset(
        offset: const Offset(30, 30),
        scale: 1,
        content: const Size(400, 800),
        viewport: viewport,
      );
      expect(offset, Offset.zero);
    });

    test('反复夹紧结果稳定（幂等），不会来回抖动', () {
      // 幂等是"不回弹"的数学保证：同一个输入永远得到同一个输出，
      // 连续调用不会产生方向相反的变化。
      const scale = 0.5;
      final first = clampTimetableOffset(
        offset: const Offset(-500, 300),
        scale: scale,
        content: content,
        viewport: viewport,
      );
      final second = clampTimetableOffset(
        offset: first,
        scale: scale,
        content: content,
        viewport: viewport,
      );
      expect(second, first);
    });
  });
}
