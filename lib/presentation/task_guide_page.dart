import 'package:flutter/material.dart';

class TaskGuidePage extends StatelessWidget {
  const TaskGuidePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('作业与 Token 使用教程')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final (title, body) in const [
          (
            '导入 Canvas Token',
            '课表右上角点“作业”，再点右上角“平台连接”→ Canvas“连接”。在官方设置页正常登录，找到个人访问令牌并生成新令牌。令牌显示时点“读取并确认”，也可粘贴到输入框。确认后验证连接并导入作业。已经隐藏的旧令牌不能重新读取；请生成新的令牌。',
          ),
          (
            '连接好课',
            '平台连接→好课“连接”，在内置官方页面正常登录，再点“读取并确认”。App 会将 token 与配对续期票据加密保存在本机；登录密码不由 App 读取。好课认证失败时会尝试一次续期，仍失败则引导重新登录。',
          ),
          (
            'Token 失效怎么办',
            '平台返回认证或授权错误后，作业页会持续显示“平台连接需更新”，同步提示也有“更新 Token”入口。点“重新加载 Token”进入平台连接，生成新 Canvas Token 或重新登录好课，再读取确认。403 也可能表示授权不足，请核对账号权限。已有作业保留，更新 Token 后立即验证连接。',
          ),
          (
            '同步与手动完成',
            'Canvas 自动同步默认间隔半小时，重启 App 后沿用上次读取时间。手动刷新、导入新 Token 会立即尝试，不受自动间隔限制；平台自身限频仍会提示。手动确认完成只改本机状态，不会代交作业，后续同步会保留。平台连接中开启自动检查后，Android 会安排后台同步，有作业变化发通知；凭证失效每轮只提醒一次，更新凭证或恢复后重置。强行停止或省电限制可能暂停执行。作业页“通知测试”可验证系统通知。其他平台可通过官方页面采集或 JSON 核对导入。',
          ),
          (
            '设置作业截止提醒',
            '作业页点“截止提醒”，开启并选择提前几小时，支持自定义整小时数。允许系统通知，Android 的精确闹钟权限可使提醒更准时；未允许时使用系统近似时间。已完成、删除或换账号后会取消对应预约。已错过所选提前时间的作业不会补发，可调整提前小时数。手机省电限制可能推迟通知。',
          ),
          (
            '查看倒计时与颜色',
            '作业主界面直接显示剩余天、小时、分钟或逾期时间，每分钟更新显示，不因此请求平台。同科目使用相同边框颜色；与课表课程名称一致时沿用课程颜色。点作业卡片查看完整标题、截止时间和平台链接。',
          ),
          (
            '添加桌面小组件',
            '长按安卓桌面空白处→小组件→ TJ Schedule，选择“下一节课”或“作业倒计时”。可拖动边缘调整组件占用区域；本版恢复固定字号和完整布局，避免上一版自动缩放效果不佳。作业小组件优先显示最近一项未完成、尚未截止的作业，同时显示逾期数量；点击打开作业。无需额外安装 Selenium。',
          ),
        ]) ...[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body),
          const SizedBox(height: 24),
        ],
      ],
    ),
  );
}
