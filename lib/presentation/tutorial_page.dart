import 'package:flutter/material.dart';

class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用教程')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: const [
          Text(
            '不用担心设置复杂，按下面顺序操作一次就可以了。课程、图片和设置都只保存在你的手机里。',
            style: TextStyle(height: 1.6),
          ),
          SizedBox(height: 18),
          _TutorialStep(
            number: '1',
            icon: Icons.school_outlined,
            title: '先添加学期',
            text:
                '填写学期名称和开学第一周的周一。你也可以点“从课表识别”，选择图片、CSV 或 XLSX，自动填写总周数和节次时间。识别后请检查一遍再保存。',
          ),
          _TutorialStep(
            number: '2',
            icon: Icons.upload_file_outlined,
            title: '导入课程',
            text:
                '回到主界面，可以点右上角导入按钮选择 CSV 或 XLSX；也可以从菜单进入“同济1系统”。网页默认用电脑模式加载完整课表，登录后直接读取“学生课表”区域，不使用截图 OCR。预览中可修改黄色单元格，也可删除误识别的整行。',
          ),
          _TutorialStep(
            number: '3',
            icon: Icons.calendar_month_outlined,
            title: '查看今天和本周',
            text:
                '日期后会显示当前教学周。点“第几周”可以快速跳到任意教学周，点左右箭头逐日切换，点日期回到今天；左右滑动“今日”和“本周”即可切换视图。',
          ),
          _TutorialStep(
            number: '4',
            icon: Icons.event_repeat_outlined,
            title: '遇到国家调休',
            text:
                'App 会检查国家公布的调休上班日。国家通知不会说明学校补哪一教学周，所以第一次遇到时，请根据学校通知同时选择目标周数和星期，例如“第 4 周周二”。之后课表、小组件和提醒会一起切换。',
          ),
          _TutorialStep(
            number: '5',
            icon: Icons.notifications_active_outlined,
            title: '设置上课提醒',
            text:
                '在“提醒设置”中点“提前时间”，可以自己输入 1 到 1440 分钟；提醒方式可选“仅通知”“通知加震动”或“通知加震动和声音”。如果提醒时间正在上另一节课，默认会延后到下课 3 分钟后。',
          ),
          _TutorialStep(
            number: '6',
            icon: Icons.widgets_outlined,
            title: '添加桌面小组件',
            text:
                '长按手机桌面空白处，进入“小组件”或“服务卡片”，找到“离线课程表”，添加“下一节课”。安装或修改课表后，请打开 App 一次让小组件同步。',
          ),
          _TutorialStep(
            number: '7',
            icon: Icons.battery_saver_outlined,
            title: '完成后台放行',
            text:
                '最后到“提醒设置”打开国产 Android 后台设置教程，允许自启动和后台活动，并关闭电池优化，否则锁屏后提醒可能延迟。',
          ),
        ],
      ),
    );
  }
}

class _TutorialStep extends StatelessWidget {
  const _TutorialStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
  });

  final String number;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 18, child: Text(number)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 19),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text,
                    style: const TextStyle(fontSize: 12, height: 1.55),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
