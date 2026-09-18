enum ReminderAlertMode { notificationOnly, vibration, soundAndVibration }

class NotificationSettings {
  const NotificationSettings({
    this.enabled = true,
    this.advanceMinutes = 30,
    this.memoAdvanceMinutes = 30,
    this.onlyNextCourse = false,
    this.delayWhenInClass = true,
    this.showNextCourseOnLockScreen = false,
    this.alertMode = ReminderAlertMode.soundAndVibration,
    this.magicOsGuideCompleted = false,
    this.tutorialPromptCompleted = false,
  });

  final bool enabled;
  final int advanceMinutes;

  /// 备忘录的全局提醒提前时间，与课程的 [advanceMinutes] 相互独立。
  final int memoAdvanceMinutes;
  final bool onlyNextCourse;
  final bool delayWhenInClass;
  final bool showNextCourseOnLockScreen;
  final ReminderAlertMode alertMode;
  final bool magicOsGuideCompleted;
  final bool tutorialPromptCompleted;

  NotificationSettings copyWith({
    bool? enabled,
    int? advanceMinutes,
    int? memoAdvanceMinutes,
    bool? onlyNextCourse,
    bool? delayWhenInClass,
    bool? showNextCourseOnLockScreen,
    ReminderAlertMode? alertMode,
    bool? magicOsGuideCompleted,
    bool? tutorialPromptCompleted,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      advanceMinutes: advanceMinutes ?? this.advanceMinutes,
      memoAdvanceMinutes: memoAdvanceMinutes ?? this.memoAdvanceMinutes,
      onlyNextCourse: onlyNextCourse ?? this.onlyNextCourse,
      delayWhenInClass: delayWhenInClass ?? this.delayWhenInClass,
      showNextCourseOnLockScreen:
          showNextCourseOnLockScreen ?? this.showNextCourseOnLockScreen,
      alertMode: alertMode ?? this.alertMode,
      magicOsGuideCompleted:
          magicOsGuideCompleted ?? this.magicOsGuideCompleted,
      tutorialPromptCompleted:
          tutorialPromptCompleted ?? this.tutorialPromptCompleted,
    );
  }
}
