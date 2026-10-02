import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/platform_credential_store.dart';
import '../data/platform_task_client.dart';
import '../data/schedule_database.dart';
import '../data/task_repository.dart';
import 'schedule_controller.dart';
import 'task_state.dart';
import '../notifications/notification_service.dart';
import '../notifications/task_sync_notifications.dart';

final taskSyncServiceProvider = FutureProvider<TaskSyncService>((ref) async {
  final database = await ref.watch(databaseProvider.future);
  var alive = true;
  final notifier = TaskSyncNotifications(
    database,
    ref.read(notificationServiceProvider),
  );
  final service = TaskSyncService(
    database,
    onAutomaticUpdate: notifier.updated,
    onAuthRequired: notifier.authRequired,
    onChanged: () {
      if (alive) ref.read(taskRevisionProvider.notifier).state++;
    },
  );
  ref.onDispose(() => alive = false);
  ref.onDispose(service.close);
  return service;
});

class TaskSyncService {
  TaskSyncService(
    this.database, {
    PlatformTaskClient? client,
    PlatformCredentialStore? credentials,
    this.onChanged,
    this.onAutomaticUpdate,
    this.onAuthRequired,
  }) : client = client ?? PlatformTaskClient(),
       credentials = credentials ?? PlatformCredentialStore(database),
       repository = TaskRepository(database.database);

  final void Function()? onChanged;
  final Future<void> Function(String platform, int count)? onAutomaticUpdate;
  final Future<void> Function(String platform)? onAuthRequired;

  final ScheduleDatabase database;
  final PlatformTaskClient client;
  final PlatformCredentialStore credentials;
  final TaskRepository repository;
  Future<Map<String, String>>? _running;
  bool _changing = false;
  String? _leaseOwner;
  Future<bool> _takeLease() async {
    final now = DateTime.now();
    final owner = now.microsecondsSinceEpoch.toString();
    final claimed = await database.database.transaction((txn) async {
      final rows = await txn.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['task_sync_lease'],
      );
      if (rows.isNotEmpty) {
        final previous = int.tryParse(rows.single['value'] as String);
        if (previous != null &&
            now.difference(DateTime.fromMicrosecondsSinceEpoch(previous)) <
                const Duration(minutes: 5)) {
          return false;
        }
      }
      await txn.rawInsert(
        'INSERT OR REPLACE INTO app_settings (key,value) VALUES (?,?)',
        ['task_sync_lease', owner],
      );
      return true;
    });
    if (claimed) _leaseOwner = owner;
    return claimed;
  }

  Future<void> _releaseLease() async {
    final owner = _leaseOwner;
    if (owner == null) return;
    await database.database.delete(
      'app_settings',
      where: 'key = ? AND value = ?',
      whereArgs: ['task_sync_lease', owner],
    );
    _leaseOwner = null;
  }

  void _checkIdle() {
    if (_running != null || _changing) throw StateError('同步正在进行，请稍后操作连接');
  }

  Future<void> _claimCanvas({bool manual = false}) async {
    await database.database.transaction((txn) async {
      final rows = await txn.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['task_canvas_attempt'],
      );
      final last = rows.isEmpty
          ? null
          : DateTime.tryParse(rows.single['value'] as String);
      final now = DateTime.now();
      if (!manual &&
          last != null &&
          now.difference(last) < const Duration(minutes: 30)) {
        final minutes = (30 - now.difference(last).inSeconds / 60).ceil();
        throw PlatformRequestException('Canvas 自动同步将在 $minutes 分钟后刷新；可随时手动刷新');
      }
      await txn.rawInsert(
        'INSERT OR REPLACE INTO app_settings (key,value) VALUES (?,?)',
        ['task_canvas_attempt', now.toIso8601String()],
      );
    });
  }

  void close() => client.close();

  Future<bool> connectCanvas(
    String token, {
    required Future<bool> Function(String oldAccount, String newAccount)
    confirmSwitch,
  }) async {
    _checkIdle();
    _changing = true;
    try {
      if (!await _takeLease()) throw StateError('后台同步正在进行，请稍后操作连接');
      await _claimCanvas(manual: true);
      final batch = await client.collectCanvas(token);
      final old =
          await credentials.activeAccount('canvas') ??
          await database.loadSetting('task_canvas_last_account');
      if (old != null &&
          old != batch.accountId &&
          !await confirmSwitch(old, batch.accountId)) {
        return false;
      }
      await credentials.save('canvas', batch.accountId, token);
      await _saveBatch('canvas', batch);
      return true;
    } finally {
      await _releaseLease();
      _changing = false;
    }
  }

  Future<bool> connectHaoke(
    HaokeCredentials pair, {
    required Future<bool> Function(String oldAccount, String newAccount)
    confirmSwitch,
  }) async {
    _checkIdle();
    _changing = true;
    try {
      if (!await _takeLease()) throw StateError('后台同步正在进行，请稍后操作连接');
      final batch = await client.collectHaoke(pair.token);
      final old =
          await credentials.activeAccount('haoke') ??
          await database.loadSetting('task_haoke_last_account');
      if (old != null &&
          old != batch.accountId &&
          !await confirmSwitch(old, batch.accountId)) {
        return false;
      }
      await credentials.save('haoke', batch.accountId, _encodePair(pair));
      await _saveBatch('haoke', batch);
      return true;
    } finally {
      await _releaseLease();
      _changing = false;
    }
  }

  Future<void> disconnect(String platform) async {
    _checkIdle();
    _changing = true;
    try {
      if (!await _takeLease()) throw StateError('后台同步正在进行，请稍后操作连接');
      await credentials.remove(platform);
      onChanged?.call();
    } finally {
      await _releaseLease();
      _changing = false;
    }
  }

  Future<Map<String, String>> refresh({bool manual = false}) =>
      _running ??= _refresh(manual: manual).whenComplete(() {
        _running = null;
        onChanged?.call();
      });

  Future<Map<String, String>> _refresh({required bool manual}) async {
    if (_changing) return {};
    if (!await _takeLease()) return manual ? {'同步': '后台同步正在进行，稍后重试即可'} : {};
    try {
      return await _collect(manual: manual);
    } finally {
      await _releaseLease();
    }
  }

  Future<Map<String, String>> _collect({required bool manual}) async {
    final results = <String, String>{};
    if (_changing) return results;
    if (!manual && await database.loadSetting('task_auto_sync') != 'true') {
      return results;
    }
    await Future.wait(
      ['canvas', 'haoke'].map((platform) async {
        final active = await credentials.activeAccount(platform);
        final secret = await credentials.read(platform);
        if (active == null || secret == null) return;
        if (!manual &&
            await database.loadSetting('task_${platform}_needs_auth') ==
                'true') {
          results[platform] = '需要重新登录';
          await _notifyAuth(platform);
          return;
        }
        try {
          PlatformTaskBatch batch;
          if (platform == 'canvas') {
            await _claimCanvas(manual: manual);
            batch = await client.collectCanvas(secret);
          } else {
            final last = DateTime.tryParse(
              await database.loadSetting('task_haoke_attempt') ?? '',
            );
            if (!manual &&
                last != null &&
                DateTime.now().difference(last) < const Duration(minutes: 1)) {
              return;
            }
            await database.saveSetting(
              'task_haoke_attempt',
              DateTime.now().toIso8601String(),
            );
            var pair = _decodePair(secret);
            try {
              batch = await client.collectHaoke(pair.token);
            } on PlatformRequestException catch (error) {
              if (error.statusCode != 401 || pair.ticket.isEmpty) rethrow;
              pair = await client.renewHaoke(pair);
              // 轮换凭证先安全落盘；即使后续读取失败，也不能丢失新票据。
              await credentials.save('haoke', active, _encodePair(pair));
              batch = await client.collectHaoke(pair.token);
            }
          }
          if (batch.accountId != active) {
            results[platform] = '平台账号已变化，请重新连接并确认切换';
            await database.saveSetting('task_${platform}_needs_auth', 'true');
            await database.saveSetting(
              'task_${platform}_error',
              results[platform]!,
            );
            if (!manual) await _notifyAuth(platform);
            return;
          }
          final old = {
            for (final task in await repository.loadVisible())
              task.id: task.toRow(),
          };
          final changed = batch.tasks.where((task) {
            final previous = old[task.id];
            final next = task.toRow();
            return previous == null ||
                [
                  'title',
                  'course',
                  'due_at',
                  'url',
                  'note',
                  'submission_state',
                ].any((key) => previous[key] != next[key]) ||
                (previous['manual_completed'] == null &&
                    previous['completed'] != next['completed']);
          }).length;
          await _saveBatch(platform, batch);
          if (!manual && changed > 0) {
            try {
              await onAutomaticUpdate?.call(platform, changed);
            } catch (_) {
              // 通知失败不能把已成功的同步标成失败。
            }
          }
          results[platform] = batch.warnings.isEmpty
              ? '同步完成：${batch.tasks.length} 项作业'
              : '同步完成，${batch.warnings.length} 项需核对：${batch.warnings.join('；')}';
        } on PlatformRequestException catch (error) {
          if ([401, 403].contains(error.statusCode)) {
            await database.saveSetting('task_${platform}_needs_auth', 'true');
          }
          await database.saveSetting('task_${platform}_error', error.message);
          results[platform] = error.message;
          if (!manual && [401, 403].contains(error.statusCode)) {
            await _notifyAuth(platform);
          }
        } catch (_) {
          const message = '同步暂时失败，已保存的作业和连接不受影响';
          await database.saveSetting('task_${platform}_error', message);
          results[platform] = message;
        }
      }),
    );
    return results;
  }

  Future<void> _notifyAuth(String platform) async {
    try {
      await onAuthRequired?.call(platform);
    } catch (_) {
      // 下次自动检查会重试未成功发送的失效提醒。
    }
  }

  Future<void> _saveBatch(String platform, PlatformTaskBatch batch) async {
    await repository.mergePlatform(batch.tasks);
    if (batch.warnings.isEmpty) {
      await database.saveSetting(
        'task_${platform}_last_success',
        batch.syncedAt.toIso8601String(),
      );
    }
    await database.saveSetting(
      'task_${platform}_error',
      batch.warnings.join('；'),
    );
    await database.saveSetting('task_${platform}_needs_auth', 'false');
    await database.deleteSetting('task_${platform}_auth_notified');
    onChanged?.call();
  }

  String _encodePair(HaokeCredentials value) =>
      jsonEncode({'version': 1, 'token': value.token, 'ticket': value.ticket});

  HaokeCredentials _decodePair(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['token'] is! String ||
        decoded['ticket'] is! String) {
      throw const FormatException('本机好课连接格式无效');
    }
    return HaokeCredentials(
      token: decoded['token'] as String,
      ticket: decoded['ticket'] as String,
    );
  }
}
