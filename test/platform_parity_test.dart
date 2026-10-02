import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/platform_task_client.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:offline_course_schedule/import/task_capture.dart';

void main() {
  final fixtures =
      jsonDecode(File('test/fixtures/platform-parity.json').readAsStringSync())
          as Map;
  test('好课页面截止年份、跨年及非法日期与网页一致', () {
    for (final row in fixtures['rangeDeadline']) {
      expect(
        rangeDeadline(row['start'], row['end'], row['year']),
        row['expected'],
      );
    }
  });
  test('Canvas 提交状态与网页全部样例一致', () {
    for (final row in fixtures['canvasSubmission']) {
      final actual = canvasSubmissionStatus(row['input']);
      expect(actual.state, row['expected']['state']);
      expect(actual.completed, row['expected']['status'] == 'completed');
    }
  });
  test('好课退回、豁免、截止时间与网页样例一致', () {
    for (final row in fixtures['haokeTask']) {
      final expected = row['expected'];
      final actual = normalizeHaokeTask(
        row['input'],
        row['course'],
        row['column'],
        'fixture-account',
        DateTime.parse(row['syncedAt']),
      );
      expect(actual.title, expected['title']);
      expect(actual.course, expected['course']);
      expect(actual.completed, expected['status'] == 'completed');
      expect(actual.submissionState, expected['submissionState']);
      expect(
        actual.dueAt,
        expected['dueAt'] == null ? null : DateTime.parse(expected['dueAt']),
      );
      expect(actual.note, expected['note']);
      expect(Uri.parse(actual.url), Uri.parse(expected['url']));
    }
  });
  test('好课日期样例与网页一致', () {
    for (final row in fixtures['haokeDeadline']) {
      if (row['expected']['reject'] == true) {
        expect(
          () => haokeDeadline(row['input']),
          throwsA(isA<PlatformRequestException>()),
        );
      } else {
        final value = row['expected']['value'];
        expect(
          haokeDeadline(row['input']),
          value == null ? null : DateTime.parse(value),
        );
      }
    }
  });
  test('安全链接与网页样例一致，包括编码后的凭证参数', () {
    for (final row in fixtures['safeTaskUrl']) {
      if (row['expected']['reject'] == true) {
        expect(() => safeTaskUrl(row['input']), throwsFormatException);
      } else {
        final actual = safeTaskUrl(row['input']);
        expect(
          actual.isEmpty ? '' : Uri.parse(actual),
          row['expected']['value'] == ''
              ? ''
              : Uri.parse(row['expected']['value']),
        );
      }
    }
  });
}
