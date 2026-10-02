String rangeDeadline(String startText, String endText, int year) {
  final pattern = RegExp(
    r'^(?:(\d{4})[-/.年])?(\d{1,2})[-/.月](\d{1,2})日?\s+(\d{1,2}):(\d{2})$',
  );
  final start = pattern.firstMatch(startText),
      end = pattern.firstMatch(endText);
  if (end == null || year < 2000 || year > 2100) return '';
  int value(RegExpMatch match, int index) => int.parse(match[index]!);
  var endYear =
      int.tryParse(end[1] ?? '') ?? int.tryParse(start?[1] ?? '') ?? year;
  if (end[1] == null &&
      start != null &&
      value(end, 2) * 100 + value(end, 3) <
          value(start, 2) * 100 + value(start, 3)) {
    endYear++;
  }
  final month = value(end, 2),
      day = value(end, 3),
      hour = value(end, 4),
      minute = value(end, 5);
  final date = DateTime.utc(endYear, month, day);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      date.month != month ||
      date.day != day ||
      hour > 23 ||
      minute > 59) {
    return '';
  }
  String pad(int value) => value.toString().padLeft(2, '0');
  return '$endYear-${pad(month)}-${pad(day)}T${pad(hour)}:${pad(minute)}';
}

bool canCaptureTaskPage(Uri uri) {
  if (uri.userInfo.isNotEmpty) return false;
  if (uri.scheme == 'http' &&
      uri.host == '192.168.180.213' &&
      uri.port == 18080) {
    return true;
  }
  if (uri.scheme != 'https' || uri.port != 443) return false;
  return uri.host == 'canvas.tongji.edu.cn' ||
      uri.host == 'tongji.aihaoke.net' ||
      [
        'chaoxing.com',
        'polymas.com',
        'zhihuishu.com',
      ].any((host) => uri.host == host || uri.host.endsWith('.$host'));
}
