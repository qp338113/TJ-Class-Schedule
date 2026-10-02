import '../data/schedule_database.dart';
import 'notification_service.dart';

class TaskSyncNotifications {
  const TaskSyncNotifications(this.database, this.notifications);
  final ScheduleDatabase database;
  final NotificationService notifications;

  Future<void> updated(String platform, int count) async {
    if (count == 0 || !await notifications.notificationsEnabled()) return;
    await notifications.showTaskNotice(
      id: platform == 'canvas' ? 910010 : 910011,
      title: '${platform == 'canvas' ? 'Canvas' : '好课'} 作业有更新',
      body: '$count 项作业新增或有变化，点击查看最新作业。',
    );
  }

  Future<void> authRequired(String platform) async {
    if (!await notifications.notificationsEnabled()) return;
    final key = 'task_${platform}_auth_notified';
    final claimed = await database.database.transaction((txn) async {
      final state = await txn.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['task_${platform}_needs_auth'],
      );
      if (state.isEmpty || state.single['value'] != 'true') return false;
      final old = await txn.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      if (old.isNotEmpty) return false;
      await txn.insert('app_settings', {'key': key, 'value': 'true'});
      return true;
    });
    if (!claimed) return;
    try {
      await notifications.showTaskNotice(
        id: platform == 'canvas' ? 910020 : 910021,
        title: '${platform == 'canvas' ? 'Canvas' : '好课'} 连接需要更新',
        body: '后台同步未成功：登录凭证无法验证或权限不足。已有作业保留，请打开作业→平台连接重新加载 Token。',
      );
    } catch (_) {
      await database.deleteSetting(key);
      rethrow;
    }
  }
}
