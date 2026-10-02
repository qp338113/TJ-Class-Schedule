import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/task_sync_controller.dart';
import 'package:offline_course_schedule/data/platform_credential_store.dart';
import 'package:offline_course_schedule/data/platform_task_client.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeClient extends PlatformTaskClient {
  int canvasCalls = 0, haokeCalls = 0, renewals = 0;
  Future<PlatformTaskBatch> Function()? canvas;
  Future<PlatformTaskBatch> Function()? haoke;
  @override
  Future<PlatformTaskBatch> collectCanvas(String token) {
    canvasCalls++;
    return canvas?.call() ?? Future.value(batch());
  }

  @override
  Future<PlatformTaskBatch> collectHaoke(String token) {
    haokeCalls++;
    return haoke?.call() ?? Future.value(batch());
  }

  @override
  Future<HaokeCredentials> renewHaoke(HaokeCredentials credentials) async {
    renewals++;
    return const HaokeCredentials(token: 'rotated', ticket: 'new-ticket');
  }
}

PlatformTaskBatch batch({
  String account = 'a',
  List<String> warnings = const [],
}) => PlatformTaskBatch(
  accountId: account,
  tasks: const [],
  warnings: warnings,
  courseCount: 2,
  successfulCourses: warnings.isEmpty ? 2 : 1,
  syncedAt: DateTime.utc(2026, 10, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late ScheduleDatabase db;
  late FakeClient client;
  late PlatformCredentialStore store;
  late TaskSyncService service;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    client = FakeClient();
    store = PlatformCredentialStore(db);
    service = TaskSyncService(db, client: client, credentials: store);
    await db.saveSetting('task_auto_sync', 'true');
  });
  tearDown(() async {
    service.close();
    await db.close();
  });
  Future<void> connectBoth() async {
    await store.save('canvas', 'a', 'canvas-secret');
    await store.save(
      'haoke',
      'a',
      jsonEncode({'version': 1, 'token': 'old', 'ticket': 'ticket'}),
    );
  }

  test('取消账号切换保留原账号和安全存储', () async {
    await store.save('canvas', 'a', 'old');
    client.canvas = () async => batch(account: 'b');
    expect(
      await service.connectCanvas('new', confirmSwitch: (_, _) async => false),
      isFalse,
    );
    expect(await store.activeAccount('canvas'), 'a');
    expect(await store.read('canvas'), 'old');
  });
  test('断开后切换账号仍须确认，取消时保持旧作业归属', () async {
    await store.save('haoke', 'a', 'test-secret');
    await service.disconnect('haoke');
    expect(await store.activeAccount('haoke'), isNull);
    expect(await store.read('haoke'), isNull);
    client.haoke = () async => batch(account: 'b');
    var confirmed = false;
    expect(
      await service.connectHaoke(
        const HaokeCredentials(token: 'new', ticket: 'new-ticket'),
        confirmSwitch: (oldAccount, newAccount) async {
          expect(oldAccount, 'a');
          expect(newAccount, 'b');
          confirmed = true;
          return false;
        },
      ),
      isFalse,
    );
    expect(confirmed, isTrue);
    expect(await db.loadSetting('task_haoke_last_account'), 'a');
    expect(await store.read('haoke'), isNull);
  });
  test('401只续期一次，轮换先保存，后续503不丢新票据', () async {
    await store.save(
      'haoke',
      'a',
      jsonEncode({'version': 1, 'token': 'old', 'ticket': 'ticket'}),
    );
    client.haoke = () async => throw PlatformRequestException(
      '暂时失败',
      client.haokeCalls == 1 ? 401 : 503,
    );
    await service.refresh(manual: true);
    expect(client.renewals, 1);
    expect(jsonDecode((await store.read('haoke'))!)['ticket'], 'new-ticket');
    expect(await db.loadSetting('task_haoke_needs_auth'), 'false');
  });
  test('403暂停自动请求，不触发续期', () async {
    await connectBoth();
    client.haoke = () async =>
        throw const PlatformRequestException('权限不足', 403);
    await service.refresh(manual: true);
    await service.refresh();
    expect(client.haokeCalls, 1);
    expect(client.renewals, 0);
    expect(await store.activeAccount('haoke'), 'a');
  });
  test('部分成功保留上一次完全成功时间', () async {
    await store.save(
      'haoke',
      'a',
      jsonEncode({'version': 1, 'token': 'old', 'ticket': 'ticket'}),
    );
    await db.saveSetting('task_haoke_last_success', 'previous-success');
    client.haoke = () async => batch(warnings: ['一门课程失败']);
    await service.refresh(manual: true);
    expect(await db.loadSetting('task_haoke_last_success'), 'previous-success');
  });
  test('关闭自动同步时不请求平台，手动同步仍可用', () async {
    await connectBoth();
    await db.saveSetting('task_auto_sync', 'false');
    await service.refresh();
    expect(client.canvasCalls + client.haokeCalls, 0);
    await service.refresh(manual: true);
    expect(client.canvasCalls, 1);
    expect(client.haokeCalls, 1);
  });
  test('Canvas失败后重建服务保留自动间隔，手动及新令牌可立即读取', () async {
    await store.save('canvas', 'a', 'token');
    client.canvas = () async =>
        throw const PlatformRequestException('暂时限流', 429);
    await service.refresh(manual: true);
    final reopened = TaskSyncService(db, client: client, credentials: store);
    await reopened.refresh();
    expect(client.canvasCalls, 1);
    await reopened.refresh(manual: true);
    expect(client.canvasCalls, 2);
    client.canvas = () async => batch();
    expect(
      await reopened.connectCanvas(
        'new-token',
        confirmSwitch: (_, _) async => true,
      ),
      isTrue,
    );
    expect(client.canvasCalls, 3);
  });
  test('重复刷新合并，两平台并行且请求中禁止断开', () async {
    await connectBoth();
    final canvas = Completer<PlatformTaskBatch>(),
        haoke = Completer<PlatformTaskBatch>();
    client.canvas = () => canvas.future;
    client.haoke = () => haoke.future;
    final first = service.refresh(manual: true);
    final second = service.refresh(manual: true);
    expect(identical(first, second), isTrue);
    for (var i = 0; i < 30 && client.haokeCalls == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(client.canvasCalls, 1);
    expect(client.haokeCalls, 1);
    await expectLater(service.disconnect('haoke'), throwsStateError);
    canvas.complete(batch());
    haoke.complete(batch());
    await first;
  });
  test('前后台不同服务不会并发读取凭证，陈旧同步锁可恢复', () async {
    await store.save('canvas', 'a', 'fixture');
    final entered = Completer<void>();
    final response = Completer<PlatformTaskBatch>();
    client.canvas = () {
      entered.complete();
      return response.future;
    };
    final running = service.refresh(manual: true);
    await entered.future;
    final otherClient = FakeClient();
    final other = TaskSyncService(db, client: otherClient, credentials: store);
    try {
      expect(await other.refresh(manual: true), contains('同步'));
      expect(otherClient.canvasCalls, 0);
      response.complete(batch());
      await running;
      expect(await db.loadSetting('task_sync_lease'), isNull);
      await db.saveSetting(
        'task_sync_lease',
        DateTime.now()
            .subtract(const Duration(minutes: 6))
            .microsecondsSinceEpoch
            .toString(),
      );
      await other.refresh(manual: true);
      expect(otherClient.canvasCalls, 1);
      expect(await db.loadSetting('task_sync_lease'), isNull);
    } finally {
      other.close();
    }
  });
}
