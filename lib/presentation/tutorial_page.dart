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
                '日期后会显示当前教学周。点左右箭头逐日切换，点日期回到今天，点“第几周”可快速跳到任意教学周。'
                '在课表区域左右滑动也能切换日期；想一次滑一周，可在右上角菜单里把“滑动切换”改成“一周”。'
                '顶部“今日”和“本周”两个标签直接点选即可。当天课程都上完后重新进入 App，会自动显示第二天的课表。',
          ),
          _TutorialStep(
            number: '4',
            icon: Icons.grid_view_rounded,
            title: '看整周课表',
            text:
                '点主界面左下角的“整周课表”，可以把整个学期的课铺在一张网格上，每张卡片都写着周次（例如 1-16周、1-16周(单)）。'
                '可以双指缩放、拖动查看；缩到最小正好看全整张表，点标题栏的方框图标也能一键看全。',
          ),
          _TutorialStep(
            number: '5',
            icon: Icons.info_outline,
            title: '点课程看详细信息',
            text:
                '在课表里点一下任意课程，会显示这门课的详细信息：教师、地点、星期、节次、周次和具体日期，'
                '并给出这个时间段对应的钟点；同一门课有多个时间段时会全部列出。'
                '万一从 1 系统导入的课程和网页上不一致，打开这里对照最上面的「信息摘要」，'
                '就能看出是星期、节次、周次、教师还是地点读错了。长按课程卡片才是修改。',
          ),
          _TutorialStep(
            number: '6',
            icon: Icons.event_note_outlined,
            title: '添加备忘录',
            text:
                '在“添加课程”页面顶部可以切换成“备忘录”，用来记录开会、交作业这类非课程安排。'
                '时间可以选“按周重复”（周几加节次）或“一次性”（具体日期加时刻）。'
                '备忘录会显示在课表里、桌面小组件里，也会按你设置的提前时间提醒。',
          ),
          _TutorialStep(
            number: '7',
            icon: Icons.palette_outlined,
            title: '换成自己喜欢的样式',
            text:
                '右上角菜单进入“外观设置”，可以改主题色（12 个预设色或自己调滑杆）、换主界面背景图。'
                '选图后能拖动和缩放决定显示哪一块，框内就是实际效果，还能开关遮罩预览。'
                '“遮罩浓度”和“课表透明度”两个滑杆可以自己调，让课程文字看得更清楚。',
          ),
          _TutorialStep(
            number: '8',
            icon: Icons.event_repeat_outlined,
            title: '遇到国家调休',
            text:
                '右上角菜单的“检查国家调休”会联网读取国家公布的调休上班日。国家通知不会说明学校补哪一天，'
                '所以到了调休日，主界面会出现橙色提示条：点“设置”，直接选“要补哪一天”的课程（例如 9月20日补第 4 周周二的课，就选那天对应的日期），'
                '教学周和星期会自动对应，也能用下拉框微调。保存后这一天的课表、桌面小组件和上课提醒会一起换成被补那天的安排。'
                '选错了点“取消”即可恢复按实际周次上课。',
          ),
          _TutorialStep(
            number: '9',
            icon: Icons.notifications_active_outlined,
            title: '设置上课提醒',
            text:
                '在“提醒设置”中点“提前时间”，可以自己输入 1 到 1440 分钟；提醒方式可选“仅通知”“通知加震动”或“通知加震动和声音”。'
                '如果提醒时间正在上另一节课，默认会延后到下课 3 分钟后。备忘录的提前时间可以在同一页单独设置。',
          ),
          _TutorialStep(
            number: '10',
            icon: Icons.widgets_outlined,
            title: '添加桌面小组件',
            text:
                '长按手机桌面空白处，进入“小组件”或“服务卡片”，找到“TJ Class Schedule”，添加“下一节课”。'
                '安装或修改课表后，请打开 App 一次让小组件同步；如果刚装新版看不到变化，把小组件删掉重新添加即可。',
          ),
          _TutorialStep(
            number: '11',
            icon: Icons.timer_outlined,
            title: '调整小组件外观与刷新',
            text:
                '在“外观设置”的“小组件颜色”里可以单独给小组件设颜色，只影响普通状态，临近上课时的提醒色不变。'
                '下面的“倒计时刷新频率”有三档：省电（更省电，数字可能有几分钟不准）、正常（每分钟刷新）、精确（每秒刷新，最准但最耗电）。',
          ),
          _TutorialStep(
            number: '12',
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
