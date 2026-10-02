import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'schedule_database.dart';

class PlatformCredentialStore {
  const PlatformCredentialStore(
    this.database, [
    this.storage = const FlutterSecureStorage(),
  ]);

  final ScheduleDatabase database;
  final FlutterSecureStorage storage;

  Future<String?> activeAccount(String platform) =>
      database.loadSetting('task_${platform}_account');

  Future<String?> read(String platform) async {
    final account = await activeAccount(platform);
    if (account == null) return null;
    return storage.read(key: _key(platform, account));
  }

  Future<void> save(String platform, String account, String credential) async {
    if (account.isEmpty || credential.isEmpty) throw ArgumentError('账号或凭证为空');
    // 先加密落盘，再切换账号指针；写入中断时仍可使用旧账号。
    await storage.write(key: _key(platform, account), value: credential);
    await database.saveSetting('task_${platform}_account', account);
    await database.saveSetting('task_${platform}_needs_auth', 'false');
    await database.deleteSetting('task_${platform}_auth_notified');
  }

  Future<void> remove(String platform) async {
    final account = await activeAccount(platform);
    if (account != null) {
      await database.saveSetting('task_${platform}_last_account', account);
      await storage.delete(key: _key(platform, account));
    }
    await database.deleteSetting('task_${platform}_account');
    await database.deleteSetting('task_${platform}_needs_auth');
    await database.deleteSetting('task_${platform}_auth_notified');
  }

  String _key(String platform, String account) =>
      'task:$platform:${base64Url.encode(utf8.encode(account))}';
}
