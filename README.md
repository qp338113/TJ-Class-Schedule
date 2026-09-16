# TJ Class Schedule

面向同济学生的 Android 本地课程表。支持从同济 1 系统直接读取个人课表，也支持 CSV、XLSX、图片识别和手工添加课程。

> 非同济大学官方应用。本项目不会代表学校提供服务，请以学校教务通知和实际教学安排为准。

## 主要功能

- 在应用内完成同济统一认证，并从个人课表页面读取课程
- 使用桌面网页模式，改善手机端课表显示不完整的问题
- 只解析课表区域中的真实课程卡片，并按星期、节次排序
- 支持 CSV、XLSX 和常见图片格式导入，识别错误可在预览中修正或删除
- 支持单双周、不连续周次、多地点和一门课多个时间段
- 今日课表、本周课表、快速切换教学周和下一节课倒计时
- 国家法定节假日不显示课程；调休补班日可指定目标教学周和星期
- 本地精确通知、可调提前时间、三档声音/震动模式和锁屏课程提示
- 荣耀、华为、小米、OPPO、vivo 等国产 Android 后台设置说明
- 桌面小组件显示下一节课、时间、地点、教师和倒计时
- 长按课程卡片修改，支持单日临时停课、删除确认和时间冲突检测
- 导入前差异统计、合并或替换、撤销导入，以及本地 JSON 备份恢复

## 隐私说明

- 课程、学期、设置和临时停课数据保存在设备本地 SQLite 数据库中。
- 不提供账号体系、云同步、统计 SDK 或广告 SDK。
- 网络仅用于用户主动打开同济 1 系统读取课表，以及检查国家法定节假日与调休安排。
- 统一认证在 WebView 中完成；应用不会把密码上传到开发者服务器。
- 清除应用数据或卸载前，建议先在“备份与恢复”中导出 JSON 备份。

更完整的说明见 [PRIVACY.md](PRIVACY.md)。

## 环境要求

- Flutter 3.47.4（stable）
- Dart 3.13.3
- Java 17
- Android SDK；最低 Android 8.0（API 26），targetSdk 34

## 本地运行

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

构建 APK：

```bash
flutter build apk --release
```

构建产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

## 发布签名

仓库中的 Release 配置目前使用调试签名，方便个人测试。正式向他人分发前，请创建自己的 Android 签名文件，并通过本机 `key.properties` 配置。签名文件和 `key.properties` 已加入 `.gitignore`，不要提交到 GitHub。

## 项目结构

```text
lib/
├── application/   # Riverpod 状态与业务协调
├── data/          # SQLite、备份和国家节假日数据
├── domain/        # 课程模型、周次规则和统一课表引擎
├── import/        # CSV、XLSX、图片及网页课表解析
├── notifications/ # 本地通知规划与调度
├── presentation/  # Flutter 页面
└── widget/        # 桌面小组件数据同步
```

## 测试

项目包含周次解析、节假日、调休、课程冲突、导入、数据库、通知规划和主要界面的自动化测试：

```bash
flutter test
```

## 参考与致谢

同济统一认证的 WebView 交互思路参考了 [mmmlllnnn/TongJi_Canvas](https://github.com/mmmlllnnn/TongJi_Canvas)。本项目是独立的 Flutter 课表应用，不包含代签、多人账号或成绩管理功能，也不代表原项目作者为本项目背书。

国家节假日数据依据中国政府网发布的国务院办公厅年度放假安排。

## 联系作者

- 作者：Algernon
- QQ：22725876
- 微信：LJ-QWQ1144
- 反馈群：1103397369

## 开源许可证

本项目使用 [MIT License](LICENSE)。欢迎学习、修改和分发；使用时请保留许可证及著作权声明。
