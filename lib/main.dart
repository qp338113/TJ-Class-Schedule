import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications/notification_lifecycle.dart';
import 'notifications/notification_service.dart';
import 'presentation/app_theme.dart';
import 'presentation/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationService = NotificationService();
  final initialDate = await notificationService.initialize();
  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: CourseScheduleApp(
        notificationService: notificationService,
        initialDate: initialDate,
      ),
    ),
  );
}

class CourseScheduleApp extends StatelessWidget {
  const CourseScheduleApp({
    super.key,
    this.notificationService,
    this.initialDate,
  });

  final NotificationService? notificationService;
  final DateTime? initialDate;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TJ Class Schedule',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: notificationService == null
          ? const HomePage()
          : NotificationLifecycle(
              service: notificationService!,
              initialDate: initialDate,
              child: const HomePage(),
            ),
    );
  }
}
