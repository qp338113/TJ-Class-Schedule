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
            getSharedPreferences(NextCourseWidget.PREFS_NAME, MODE_PRIVATE)
                .edit()
                .putString(NextCourseWidget.COURSES_KEY, JSONArray(courses).toString())
                .apply()
            NextCourseWidget.updateAll(this)
            result.success(null)
        }
    }
}
