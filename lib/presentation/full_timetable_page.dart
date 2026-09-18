import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../domain/schedule_models.dart';
import 'course_detail_sheet.dart';

/// 把平移量夹到合法范围，是整周课表缩放/拖动行为的唯一裁剪入口。
///
/// 内容比视口大时，把内容边缘夹到视口边缘（不允许拖出空白）；
/// 内容比视口小时，在那一侧居中，避免出现一块偏移的空档。
///
/// 抽成顶层纯函数是为了能直接做单元测试——"回弹"这类问题都出在这里。
Offset clampTimetableOffset({
  required Offset offset,
  required double scale,
  required Size content,
  required Size viewport,
}) {
  final scaledWidth = content.width * scale;
  final scaledHeight = content.height * scale;
  final double dx;
  final double dy;
  if (scaledWidth <= viewport.width) {
    dx = (viewport.width - scaledWidth) / 2;
  } else {
    dx = offset.dx.clamp(viewport.width - scaledWidth, 0.0);
  }
  if (scaledHeight <= viewport.height) {
    dy = (viewport.height - scaledHeight) / 2;
  } else {
    dy = offset.dy.clamp(viewport.height - scaledHeight, 0.0);
  }
  return Offset(dx, dy);
}

/// 整周课表：把整个学期的课程按「周几 × 节次」铺在一张网格上。
///
/// 只显示课程，不显示备忘录。卡片自带周次文本（如 `1-16周(单)`）。
/// 网格尺寸固定，支持双指缩放与拖动；缩到最小正好能看全整张表。
///
/// 这里**没有**使用 [InteractiveViewer]：它内部有一个隐式的缩放下限
/// `max(视口宽/内容宽, 视口高/内容高)`（即"铺满"比例），该值大于"装下"比例。
/// 两者同时存在时，缩放到"看全"会在手势中被顶回去，快速滑动触发惯性时更明显，
/// 表现为回弹。改用自己处理手势 + [clampTimetableOffset] 夹紧，行为完全确定，
/// 任何速度下都不会回弹。
class FullTimetablePage extends StatefulWidget {
  const FullTimetablePage({required this.term, required this.courses, super.key});

  final Term term;
  final List<Course> courses;

  /// 节次列宽、每周几列宽、每节行高、表头高度。
  /// 节次列要放下「第10节」和「08:00-09:40」两行，66 太窄会截断时间。
  static const double _periodColumnWidth = 80;
  static const double _dayColumnWidth = 132;
  static const double _rowHeight = 74;
  static const double _headerHeight = 38;
  static const double _cellPadding = 3;

  @override
  State<FullTimetablePage> createState() => _FullTimetablePageState();
}

class _FullTimetablePageState extends State<FullTimetablePage>
    with SingleTickerProviderStateMixin {
  /// 最大放大倍数。
  static const double _maxScale = 3;

  /// 默认进入时的缩放：优先保证文字可读。整张表缩到"看全"时字会小到读不出，
  /// 所以取一个舒适值；想看全可以自己缩小或点标题栏的看全按钮。
  static const double _comfortableScale = 0.7;

  /// 惯性滑行的手感参数，值越大停得越快。
  static const double _flingDrag = 0.135;

  double _scale = 1;
  Offset _offset = Offset.zero;

  /// "看全整张表"所需的缩放比，同时作为缩放下限。
  double _minScale = 1;

  Size _viewport = Size.zero;
  Size _content = Size.zero;
  bool _initialized = false;

  // 手势起点快照。
  double _startScale = 1;
  Offset _startContentFocal = Offset.zero;

  late final _ticker = createTicker(_onFlingTick);
  FrictionSimulation? _flingX;
  FrictionSimulation? _flingY;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// 回到「整张课表恰好装进一屏」的状态。
  void _zoomToFit() {
    _ticker.stop();
    setState(() {
      _scale = _minScale;
      _offset = clampTimetableOffset(
        offset: Offset.zero,
        scale: _scale,
        content: _content,
        viewport: _viewport,
      );
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _ticker.stop();
    _startScale = _scale;
    // 记下手指按住的那个内容点，缩放与拖动时让它始终跟着手指走。
    _startContentFocal = (details.localFocalPoint - _offset) / _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final nextScale = (_startScale * details.scale).clamp(_minScale, _maxScale);
    final nextOffset =
        details.localFocalPoint - _startContentFocal * nextScale;
    setState(() {
      _scale = nextScale;
      _offset = clampTimetableOffset(
        offset: nextOffset,
        scale: nextScale,
        content: _content,
        viewport: _viewport,
      );
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    // 速度慢到看不出滑行就不启动惯性，避免无谓的动画。
    if (velocity.distance < kMinFlingVelocity) return;
    _flingX = FrictionSimulation(_flingDrag, _offset.dx, velocity.dx);
    _flingY = FrictionSimulation(_flingDrag, _offset.dy, velocity.dy);
    _ticker.start();
  }

  void _onFlingTick(Duration elapsed) {
    final x = _flingX;
    final y = _flingY;
    if (x == null || y == null) return;
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final target = Offset(x.x(seconds), y.x(seconds));
    final clamped = clampTimetableOffset(
      offset: target,
      scale: _scale,
      content: _content,
      viewport: _viewport,
    );
    // 滑到边界就停下：继续跑只会反复被夹住，看起来就是回弹。
    // （内容比视口小的方向本来就没得滑，同样在这里立即结束。）
    if (clamped != target || (x.isDone(seconds) && y.isDone(seconds))) {
      _ticker.stop();
    }
    setState(() => _offset = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final layout = _GridLayout.build(widget.term, widget.courses);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('整周课表'),
        actions: [
          IconButton(
            tooltip: '看全整张课表',
            onPressed: _zoomToFit,
            icon: const Icon(Icons.fit_screen_outlined),
          ),
        ],
        // 学期信息放进标题栏，把下面的整块空间都留给网格。
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.term.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  '共 ${widget.term.totalWeeks} 周',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
      body: layout.isEmpty
          ? const Center(child: Text('本学期还没有课程'))
          : ColoredBox(
              // 铺满底色，避免深色模式下网格四周露出纯黑边。
              color: theme.colorScheme.surface,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  final content =
                      Size(layout.totalWidth, layout.totalHeight);
                  _viewport = viewport;
                  _content = content;
                  // 缩放下限 = 整张表恰好装进一屏（两轴取较小者）。
                  // 上限 1.0：网格本身已是"阅读尺寸"，再放大没有意义。
                  _minScale = math
                      .min(
                        viewport.width / content.width,
                        viewport.height / content.height,
                      )
                      .clamp(0.05, 1.0);
                  if (!_initialized) {
                    _initialized = true;
                    _scale = math.max(_minScale, _comfortableScale);
                    _offset = clampTimetableOffset(
                      offset: Offset.zero,
                      scale: _scale,
                      content: content,
                      viewport: viewport,
                    );
                  } else {
                    // 视口变化（旋转屏幕等）后重新夹紧，避免停在越界位置。
                    final clampedScale = _scale.clamp(_minScale, _maxScale);
                    _scale = clampedScale;
                    _offset = clampTimetableOffset(
                      offset: _offset,
                      scale: clampedScale,
                      content: content,
                      viewport: viewport,
                    );
                  }
                  return ClipRect(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onScaleEnd: _onScaleEnd,
                      // OverflowBox 必须在 Transform **外面**，顺序不能反。
                      //
                      // 命中测试时 RenderBox 会先判断「点是否落在自身尺寸内」。
                      // OverflowBox 的尺寸被父约束夹到视口大小（内容比视口大时
                      // 它只会溢出、不会撑大自己）。若 Transform 在外，传进来的
                      // 已是反变换后的**内容坐标**，一旦超出视口尺寸就被拦掉，
                      // 表现为只有靠左上角的卡片能点开，右下角的点不动。
                      // 官方 InteractiveViewer 也是这个顺序：先过 OverflowBox
                      // （拿到视口坐标，必定通过），再由 Transform 反变换成内容坐标。
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: 0,
                        maxWidth: double.infinity,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Transform(
                          transform: Matrix4.identity()
                            ..translateByDouble(
                              _offset.dx,
                              _offset.dy,
                              0,
                              1,
                            )
                            ..scaleByDouble(_scale, _scale, 1, 1),
                          child: SizedBox(
                            width: content.width,
                            height: content.height,
                            child: _GridBody(layout: layout),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// 网格尺寸与每张卡片的位置；由 [build] 一次性算好，避免在 widget 树里重复计算。
class _GridLayout {
  _GridLayout({
    required this.periodNumbers,
    required this.totalWidth,
    required this.totalHeight,
    required this.cards,
    required this.periodLabels,
  });

  final List<int> periodNumbers;
  final double totalWidth;
  final double totalHeight;
  final List<_CardPlacement> cards;
  final List<LessonPeriod?> periodLabels;

  bool get isEmpty => cards.isEmpty;

  double get _periodColumnWidth => FullTimetablePage._periodColumnWidth;
  double get _dayColumnWidth => FullTimetablePage._dayColumnWidth;

  double get _bodyTop => FullTimetablePage._headerHeight;

  /// 周几列（1-7，始终 7 列）的左边缘。
  double dayLeft(int weekday) =>
      _periodColumnWidth + (weekday - 1) * _dayColumnWidth;

  /// 节次行的上边缘。
  double rowTop(int rowIndex) =>
      _bodyTop + rowIndex * FullTimetablePage._rowHeight;

  static _GridLayout build(Term term, List<Course> courses) {
    // 节次号取所有星期的并集，避免某个星期节次更多时被截断。
    final byNumber = <int, LessonPeriod>{};
    for (final entry in term.periodsByWeekday.entries) {
      for (final period in entry.value) {
        byNumber.putIfAbsent(period.number, () => period);
      }
    }
    final periodNumbers = byNumber.keys.toList()..sort();
    if (periodNumbers.isEmpty) {
      periodNumbers.addAll(List<int>.generate(11, (index) => index + 1));
    }
    final rowIndexOf = <int, int>{
      for (var index = 0; index < periodNumbers.length; index++)
        periodNumbers[index]: index,
    };

    final cards = <_CardPlacement>[];
    for (var weekday = 1; weekday <= 7; weekday++) {
      final sessions = <_SessionRef>[];
      for (final course in courses) {
        for (final session in course.sessions) {
          if (session.weekday != weekday) continue;
          final start =
              rowIndexOf[session.startPeriod] ?? session.startPeriod - 1;
          final end = rowIndexOf[session.endPeriod] ?? session.endPeriod - 1;
          sessions.add(
            _SessionRef(
              term: term,
              course: course,
              session: session,
              startRow: start < 0 ? 0 : start,
              endRow: end < start ? start : end,
            ),
          );
        }
      }
      if (sessions.isEmpty) continue;
      sessions.sort((a, b) {
        final byStart = a.startRow.compareTo(b.startRow);
        if (byStart != 0) return byStart;
        return b.endRow.compareTo(a.endRow);
      });

      // 先按节次重叠切成互不相干的簇，再在簇内用首次适应分配轨道。
      // 这样同一星期里互不重叠的课能各占满整列宽度，只有真正重叠的才并排。
      var clusterStart = 0;
      var clusterMaxEnd = sessions.first.endRow;
      for (var index = 1; index <= sessions.length; index++) {
        final isBreak =
            index == sessions.length || sessions[index].startRow > clusterMaxEnd;
        if (!isBreak) {
          if (sessions[index].endRow > clusterMaxEnd) {
            clusterMaxEnd = sessions[index].endRow;
          }
          continue;
        }
        _placeCluster(
          sessions.sublist(clusterStart, index),
          weekday: weekday,
          cards: cards,
        );
        if (index < sessions.length) {
          clusterStart = index;
          clusterMaxEnd = sessions[index].endRow;
        }
      }
    }

    final rowCount = periodNumbers.length;
    return _GridLayout(
      periodNumbers: periodNumbers,
      totalWidth: FullTimetablePage._periodColumnWidth +
          7 * FullTimetablePage._dayColumnWidth,
      totalHeight:
          FullTimetablePage._headerHeight + rowCount * FullTimetablePage._rowHeight,
      cards: cards,
      periodLabels: [
        for (final number in periodNumbers) byNumber[number],
      ],
    );
  }

  static void _placeCluster(
    List<_SessionRef> cluster, {
    required int weekday,
    required List<_CardPlacement> cards,
  }) {
    // 首次适应：能塞进已有轨道的就塞，塞不进才新开一条。
    final trackEnds = <int>[];
    final trackOf = <int, int>{};
    for (var index = 0; index < cluster.length; index++) {
      final session = cluster[index];
      var track = -1;
      for (var candidate = 0; candidate < trackEnds.length; candidate++) {
        if (session.startRow > trackEnds[candidate]) {
          track = candidate;
          break;
        }
      }
      if (track == -1) {
        track = trackEnds.length;
        trackEnds.add(session.endRow);
      } else {
        trackEnds[track] = session.endRow;
      }
      trackOf[index] = track;
    }
    final trackCount = trackEnds.length;
    final available =
        FullTimetablePage._dayColumnWidth - 2 * FullTimetablePage._cellPadding;
    final slotWidth = available / trackCount;
    final dayLeft = FullTimetablePage._periodColumnWidth +
        (weekday - 1) * FullTimetablePage._dayColumnWidth;

    for (var index = 0; index < cluster.length; index++) {
      final session = cluster[index];
      final track = trackOf[index]!;
      cards.add(
        _CardPlacement(
          ref: session,
          left: dayLeft +
              FullTimetablePage._cellPadding +
              track * slotWidth,
          top: FullTimetablePage._headerHeight +
              session.startRow * FullTimetablePage._rowHeight +
              FullTimetablePage._cellPadding,
          width: slotWidth - 2,
          height: (session.endRow - session.startRow + 1) *
                  FullTimetablePage._rowHeight -
              2 * FullTimetablePage._cellPadding,
        ),
      );
    }
  }
}

class _SessionRef {
  const _SessionRef({
    required this.term,
    required this.course,
    required this.session,
    required this.startRow,
    required this.endRow,
  });

  /// 点开课程详情时要用学期来换算节次对应的钟点，随卡片一起带着。
  final Term term;
  final Course course;
  final CourseSession session;
  final int startRow;
  final int endRow;
}

class _CardPlacement {
  const _CardPlacement({
    required this.ref,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final _SessionRef ref;
  final double left;
  final double top;
  final double width;
  final double height;
}

class _GridBody extends StatelessWidget {
  const _GridBody({required this.layout});

  final _GridLayout layout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineColor = scheme.outlineVariant.withValues(alpha: 0.5);
    final headerColor = scheme.surfaceContainerHighest.withValues(alpha: 0.6);

    return Stack(
      children: [
        // 表头与节次列的底色。
        Positioned(
          left: 0,
          top: 0,
          width: layout.totalWidth,
          height: FullTimetablePage._headerHeight,
          child: ColoredBox(color: headerColor),
        ),
        Positioned(
          left: 0,
          top: FullTimetablePage._headerHeight,
          width: FullTimetablePage._periodColumnWidth,
          height: layout.totalHeight - FullTimetablePage._headerHeight,
          child: ColoredBox(color: headerColor.withValues(alpha: 0.5)),
        ),
        // 周几标题。
        for (var weekday = 1; weekday <= 7; weekday++)
          Positioned(
            left: layout.dayLeft(weekday),
            top: 0,
            width: FullTimetablePage._dayColumnWidth,
            height: FullTimetablePage._headerHeight,
            child: Center(
              child: Text(
                _weekdayLabel(weekday),
                maxLines: 1,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        // 节次标签（含起止时间，保持克制）。
        for (var index = 0; index < layout.periodNumbers.length; index++)
          Positioned(
            left: 0,
            top: layout.rowTop(index),
            width: FullTimetablePage._periodColumnWidth,
            height: FullTimetablePage._rowHeight,
            child: _PeriodLabel(
              period: layout.periodLabels[index],
              number: layout.periodNumbers[index],
            ),
          ),
        // 网格线。
        for (var weekday = 1; weekday <= 7; weekday++)
          Positioned(
            left: layout.dayLeft(weekday),
            top: 0,
            width: 1,
            height: layout.totalHeight,
            child: ColoredBox(color: lineColor),
          ),
        for (var index = 0; index <= layout.periodNumbers.length; index++)
          Positioned(
            left: 0,
            top: FullTimetablePage._headerHeight +
                index * FullTimetablePage._rowHeight,
            width: layout.totalWidth,
            height: 1,
            child: ColoredBox(color: lineColor),
          ),
        // 课程卡片。
        for (final card in layout.cards)
          Positioned(
            left: card.left,
            top: card.top,
            width: card.width,
            height: card.height,
            child: _CourseBlock(card: card),
          ),
      ],
    );
  }
}

class _PeriodLabel extends StatelessWidget {
  const _PeriodLabel({required this.period, required this.number});

  final LessonPeriod? period;
  final int number;

  @override
  Widget build(BuildContext context) {
    final period = this.period;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '第$number节',
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (period != null) ...[
            const SizedBox(height: 2),
            Text(
              '${_timeText(period.startMinutes)}-${_timeText(period.endMinutes)}',
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({required this.card});

  final _CardPlacement card;

  @override
  Widget build(BuildContext context) {
    final course = card.ref.course;
    final session = card.ref.session;
    final color = Color(course.colorValue);
    final teacher = session.teacherOverride?.trim();
    final teacherText =
        (teacher == null || teacher.isEmpty) ? course.teacher : teacher;
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      // 点一下看详情，便于和 1 系统的「排课信息」逐行对照排查识别问题。
      // 这里用 onTap 而不是 InkWell：整周课表整体由外层手势负责缩放拖动，
      // 内层只加一个轻量的点击识别，不影响缩放与惯性滑动。
      onTap: () => showCourseDetailSheet(
        context,
        term: card.ref.term,
        course: course,
        session: session,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // 淡色底 + 同色描边，深浅色模式下文字都保持清晰。
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.75)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 5, 6, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 单节课的卡片只有几十像素高，课程名 + 教师 + 地点往往放不下。
              // OverflowBox 让内容按自然高度排版（因此不会报 RenderFlex 溢出），
              // 再由 ClipRect 裁掉超出部分；周次固定在底部保证始终可见。
              Expanded(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    maxHeight: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          course.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                        ),
                        if (teacherText.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          _BlockLine(
                            text: teacherText,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                        if (session.location.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          _BlockLine(
                            text: session.location,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              _BlockLine(
                text: session.weekRule.displayText,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockLine extends StatelessWidget {
  const _BlockLine({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: color,
          ),
    );
  }
}

String _weekdayLabel(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

String _timeText(int minutes) {
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
