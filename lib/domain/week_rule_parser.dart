import 'schedule_models.dart';

class ParseResult<T> {
  const ParseResult.success(this.value) : error = null;
  const ParseResult.failure(this.error) : value = null;

  final T? value;
  final String? error;
  bool get isSuccess => value != null;
}

class WeekRuleParser {
  const WeekRuleParser();

  ParseResult<WeekRule> parse(String input) {
    var text = _normalize(input);
    if (text.isEmpty) return const ParseResult.failure('周次不能为空');

    final hasOdd = RegExp(r'单').hasMatch(text);
    final hasEven = RegExp(r'双').hasMatch(text);
    if (hasOdd && hasEven) {
      return const ParseResult.failure('周次不能同时指定单周和双周');
    }

    text = text
        .replaceAll(RegExp(r'[第周]'), '')
        .replaceAll(RegExp(r'[单双]'), '')
        .replaceAll(RegExp(r'[()（）]'), '');
    if (text.isEmpty) return const ParseResult.failure('没有识别到周数');

    final weeks = <int>{};
    var hasListOrGap = false;
    final pieces = text.split(',');
    for (final piece in pieces) {
      if (piece.isEmpty) return const ParseResult.failure('周次列表存在空项');
      final range = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(piece);
      if (range == null) return ParseResult.failure('无法识别周次“$input”');
      final start = int.parse(range.group(1)!);
      final end = int.parse(range.group(2) ?? range.group(1)!);
      if (start < 1 || end < start || end > 60) {
        return ParseResult.failure('周次范围无效“$piece”');
      }
      if (pieces.length > 1 || start == end) hasListOrGap = true;
      for (var week = start; week <= end; week++) {
        weeks.add(week);
      }
    }

    final sorted = weeks.toList()..sort();
    final parityType = hasOdd
        ? WeekType.odd
        : hasEven
        ? WeekType.even
        : null;
    final isContinuous = sorted.last - sorted.first + 1 == sorted.length;
    final explicit =
        (!isContinuous ||
            pieces.length > 1 ||
            (hasListOrGap && sorted.length == 1))
        ? weeks
        : null;
    return ParseResult.success(
      WeekRule(
        startWeek: sorted.first,
        endWeek: sorted.last,
        type:
            parityType ?? (explicit == null ? WeekType.every : WeekType.custom),
        explicitWeeks: explicit,
      ),
    );
  }

  String _normalize(String input) => input
      .trim()
      .replaceAll('，', ',')
      .replaceAll('、', ',')
      .replaceAll('－', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll(RegExp(r'\s+'), '');
}
