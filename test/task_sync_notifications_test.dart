import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/data/platform_credential_store.dart';
import 'package:offline_course_schedule/data/platform_task_client.dart';
import 'package:offline_course_schedule/application/task_sync_controller.dart';
import 'package:offline_course_schedule/notifications/notification_service.dart';
import 'package:offline_course_schedule/notifications/task_sync_notifications.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'task_sync_service_test.dart' show FakeClient;

class Notices extends NotificationService {
  bool allowed = true;
  bool fail = false;
  final shown = <String>[];
  @override
  Future<bool> notificationsEnabled() async => allowed;
  @override
  Future<void> showTaskNotice({
    required int id,
    required String title,
    required String body,
  }) async {
    if (fail) throw StateError('fixture notification failure');
    shown.add(title);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late ScheduleDatabase db;
  late Notices notices;
  late PlatformCredentialStore store;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    notices = Notices();
    store = PlatformCredentialStore(db);
    await store.save('canvas', 'a', 'fixture');
    await db.saveSetting('task_auto_sync', 'true');
    await db.saveSetting('task_canvas_needs_auth', 'true');
  });
  tearDown(() async {
    await notices.dispose();
    await db.close();
  });
  test('每轮认证失效仅通知一次，重建与并发不重复，新凭证后重新提醒', () async {
    final notifier = TaskSyncNotifications(db, notices);
    await Future.wait([
      notifier.authRequired('canvas'),
      TaskSyncNotifications(db, notices).authRequired('canvas'),
    ]);
    await TaskSyncNotifications(db, notices).authRequired('canvas');
    expect(notices.shown, ['Canvas 连接需要更新']);
    await store.save('canvas', 'a', 'new fixture');
    await db.saveSetting('task_canvas_needs_auth', 'true');
    await notifier.authRequired('canvas');
    expect(notices.shown.length, 2);
  });
  test('未授权和发送失败不吞掉失效提醒，成功同步后不发送过期失效提示', () async {
    final notifier = TaskSyncNotifications(db, notices);
    notices.allowed = false;
    await notifier.authRequired('canvas');
    expect(await db.loadSetting('task_canvas_auth_notified'), isNull);
    notices.allowed = true;
    notices.fail = true;
    await expectLater(notifier.authRequired('canvas'), throwsStateError);
    notices.fail = false;
    await notifier.authRequired('canvas');
    expect(notices.shown.length, 1);
    await db.saveSetting('task_canvas_needs_auth', 'false');
    await db.deleteSetting('task_canvas_auth_notified');
    await notifier.authRequired('canvas');
    expect(notices.shown.length, 1);
  });
  test('自动同步只通知变化的作业，时间戳变化和手动刷新不会发更新通知', () async {
    final client = FakeClient();
    var title = '数学作业';
    var synced = DateTime.utc(2026, 10, 2);
    client.canvas = () async => PlatformTaskBatch(
      accountId: 'a',
      tasks: [
        TaskRecord(
          id: 'canvas:a:1',
          title: title,
          course: '数学',
          platform: 'canvas',
          source: 'canvas',
          accountId: 'a',
          createdAt: DateTime.utc(2026, 10, 1),
          syncedAt: synced,
        ),
      ],
      warnings: [],
      courseCount: 1,
      successfulCourses: 1,
      syncedAt: synced,
    );
    final notifier = TaskSyncNotifications(db, notices);
    final service = TaskSyncService(
      db,
      client: client,
      credentials: store,
      onAutomaticUpdate: notifier.updated,
      onAuthRequired: notifier.authRequired,
    );
    await db.saveSetting('task_canvas_needs_auth', 'false');
    await service.refresh();
    expect(notices.shown, ['Canvas 作业有更新']);
    synced = synced.add(const Duration(minutes: 30));
    await db.deleteSetting('task_canvas_attempt');
    await service.refresh();
    expect(notices.shown.length, 1);
    title = '更改标题';
    await service.refresh(manual: true);
    expect(notices.shown.length, 1);
    title = '再次更改';
    await db.deleteSetting('task_canvas_attempt');
    await service.refresh();
    expect(notices.shown.length, 2);
    service.close();
  });
  test('认证暂停的自动任务仍补发单次提醒；网络错误不误报 Token 失效', () async {
    final client = FakeClient();
    final notifier = TaskSyncNotifications(db, notices);
    final service = TaskSyncService(
      db,
      client: client,
      credentials: store,
      onAutomaticUpdate: notifier.updated,
      onAuthRequired: notifier.authRequired,
    );
    await service.refresh();
    await service.refresh();
    expect(client.canvasCalls, 0);
    expect(notices.shown.length, 1);
    await store.save('canvas', 'a', 'new fixture');
    client.canvas = () async =>
        throw const PlatformRequestException('网络错误', 503);
    await service.refresh();
    expect(notices.shown.length, 1);
    expect(await db.loadSetting('task_canvas_needs_auth'), 'false');
    service.close();
  });
}
