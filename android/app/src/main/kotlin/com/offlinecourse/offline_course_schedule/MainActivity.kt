package com.offlinecourse.offline_course_schedule

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "offline_course_schedule/widget",
        ).setMethodCallHandler { call, result ->
            if (call.method != "update") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val courses = call.argument<List<Map<String, Any?>>>("courses") ?: emptyList()
            // 小组件自己的背景色；为 null 表示恢复默认，直接删掉这个键。
            // Dart 侧颜色是 32 位无符号 ARGB，超过 Int.MAX_VALUE 时会按 int64 传过来，
            // 所以这里用 Number 取再转 Int，不能直接声明成 Int。
            val color = (call.argument<Any?>("color") as? Number)?.toInt()
            // 刷新频率由 Flutter 侧决定；为 null 时交给原生侧按默认（省电）处理。
            val refreshMode = call.argument<String>("refreshMode")
            val editor = getSharedPreferences(NextCourseWidget.PREFS_NAME, MODE_PRIVATE)
                .edit()
                .putString(NextCourseWidget.COURSES_KEY, JSONArray(courses).toString())
            if (refreshMode == null) {
                editor.remove(NextCourseWidget.REFRESH_MODE_KEY)
            } else {
                editor.putString(NextCourseWidget.REFRESH_MODE_KEY, refreshMode)
            }
            if (color == null) {
                editor.remove(NextCourseWidget.COLOR_KEY)
            } else {
                editor.putInt(NextCourseWidget.COLOR_KEY, color)
            }
            editor.apply()
            NextCourseWidget.updateAll(this)
            result.success(null)
        }
    }
}
