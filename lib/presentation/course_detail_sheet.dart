import 'package:flutter/material.dart';

import '../domain/schedule_models.dart';

/// 打开课程详情。
///
/// [session] 用于标出你点的那一节；[date] 用于显示这节课对应的具体日期。
Future<void> showCourseDetailSheet(
  BuildContext context, {
  required Term term,
  required Course course,
  CourseSession? session,
  DateTime? date,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _CourseDetailSheet(
      term: term,
      course: course,
      session: session,
      date: date,
    ),
  );
}

/// 课程详情：把 App **实际存储**的字段逐项列出来。
///
/// 不只是用来看信息。导入识别出错时，这里显示的就是 App 真正存下来的内容，
/// 与同济 1 系统的「排课信息」浮层一对照，就能立刻看出是哪一项解析错了
/// ——星期、节次、周次、教师还是地点。
class _CourseDetailSheet extends StatelessWidget {
  const _CourseDetailSheet({
    required this.term,
    required this.course,
    this.session,
    this.date,
  });

  final Term term;
  final Course course;
  final CourseSession? session;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(course.colorValue);
    final focused = session;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 5,
                    height: 22,
                    margin: const EdgeInsets.only(top: 3, right: 10),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      course.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (focused != null) ...[
                const SizedBox(height: 4),
                Text(
                  '你点的是这一节：${periodRangeText(focused)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _TextBlock(
                title: '信息摘要（与 1 系统的「排课信息」同样写法）',
                lines: [
                  if (focused != null) '[${weekdayName(focused.weekday)}] 排课信息',
                  for (final item in _orderedSessions())
                    '[${periodRangeText(item)}] '
                        '[${item.weekRule.displayText}] '
                        '${course.name} '
                        '${effectiveTeacher(course, item)} '
                        '${item.location}',
                ],
              ),
              const SizedBox(height: 16),
              if (focused != null) ...[
                _Field('教师', effectiveTeacher(course, focused)),
                _Field('地点', focused.location),
                _Field('星期', weekdayName(focused.weekday)),
                _Field('节次', periodRangeText(focused)),
                _Field(
                  '周次',
                  '${focused.weekRule.displayText}'
                  '（实际 ${weekCount(focused.weekRule, term.totalWeeks)} 周）',
                ),
                _Field('上课周', weeksText(focused.weekRule, term.totalWeeks)),
                _Field('时间段起止', clockRangeText(term, focused)),
              ],
              if (date != null)
                _Field(
                  '日期',
                  '${date!.year}年${date!.month}月${date!.day}日'
                  ' ${weekdayName(date!.weekday)}'
                  ' · 第 ${term.weekOf(date!) ?? '?'} 周',
                ),
              const SizedBox(height: 10),
              Text(
                '这门课的全部时间段（${course.sessions.length} 条）',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              for (final item in _orderedSessions())
                _SessionRow(
                  term: term,
                  session: item,
                  highlighted: item == focused,
                  color: color,
                ),
              const SizedBox(height: 14),
              Text(
                '以上是 App 实际保存的内容。若与网页上的「排课信息」不一致，'
                '照着逐行比对，就能看出是星期、节次、周次、教师还是地点解析错了。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 把被点击的那一节排在前面，方便先看自己点的那条。
  List<CourseSession> _orderedSessions() {
    final focused = session;
    if (focused == null) return course.sessions;
    return [
      focused,
      for (final item in course.sessions)
        if (item != focused) item,
    ];
  }
}

/// 该时间段实际生效的教师：优先用它自己的覆盖值，否则用课程级教师。
///
/// 同一门课不同周次由不同老师上时，教师记在时间段上；否则记在课程上。
String effectiveTeacher(Course course, CourseSession session) {
  final override = session.teacherOverride?.trim();
  return override == null || override.isEmpty ? course.teacher : override;
}

String weekdayName(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

/// 该时间段实际上课的周次列表，例如 `1, 3, 5, 7`。
///
/// 逐周判定而不是直接读 [WeekRule.startWeek]/[endWeek]，因为规则可能带单双周
/// 或自定义周次；这里要的是"实际哪几周来上课"。
List<int> weeksOf(WeekRule rule, int totalWeeks) => [
  for (var week = 1; week <= totalWeeks; week++)
    if (rule.includes(week)) week,
];

String weeksText(WeekRule rule, int totalWeeks) =>
    weeksOf(rule, totalWeeks).join(', ');

int weekCount(WeekRule rule, int totalWeeks) =>
    weeksOf(rule, totalWeeks).length;

String periodRangeText(CourseSession session) =>
    '第 ${session.startPeriod}-${session.endPeriod} 节';

/// 该节次对应的具体钟点，例如 `08:00-09:40`；学期里没定义时返回空串。
String clockRangeText(Term term, CourseSession session) {
  final start = term.periodFor(session.weekday, session.startPeriod);
  final end = term.periodFor(session.weekday, session.endPeriod);
  if (start == null || end == null) return '';
  return '${clockText(start.startMinutes)}-${clockText(end.endMinutes)}';
}

/// 把「距零点分钟数」格式化成 `HH:mm`。
String clockText(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.term,
    required this.session,
    required this.highlighted,
    required this.color,
  });

  final Term term;
  final CourseSession session;
  final bool highlighted;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? color.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${weekdayName(session.weekday)} ${periodRangeText(session)}'
            '${clockRangeText(term, session).isEmpty ? '' : '  ${clockRangeText(term, session)}'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [
              session.weekRule.displayText,
              if (session.location.isNotEmpty) session.location,
              if ((session.teacherOverride ?? '').trim().isNotEmpty)
                session.teacherOverride!.trim(),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 等宽文本块，用来复刻 1 系统浮层的排版，便于逐行比对。
class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelSmall),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                line,
                style: const TextStyle(fontSize: 12.5, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '（空）' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
