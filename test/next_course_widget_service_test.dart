import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/widget/next_course_widget_service.dart';

void main() {
  test('小组件只保留尚未开始的课程并按时间排序', () {
    final term = Term(
      id: 'term',
      name: '测试',
      firstWeekMonday: DateTime(2026, 9, 14),
      totalWeeks: 1,
      periodsByWeekday: {
        1: const [LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525)],
      },
    );
    final course = Course(
      id: 'course',
      name: '高等数学',
      teacher: '张老师',
      colorValue: 0,
      sessions: [
        CourseSession(
          id: 'session',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 1, endWeek: 1, type: WeekType.every),
          location: '北129',
        ),
      ],
    );

    final items = const NextCourseWidgetService().buildItems(
      ScheduleData(term: term, courses: [course]),
      DateTime(2026, 9, 14, 7, 30),
    );

    expect(items.single['name'], '高等数学');
    expect(items.single['location'], '北129');
    expect(items.single['teacher'], '张老师');
    expect(items.single['time'], '08:00');
  });
}
