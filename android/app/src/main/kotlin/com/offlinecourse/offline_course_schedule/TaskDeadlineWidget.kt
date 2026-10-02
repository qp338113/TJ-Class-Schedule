package com.offlinecourse.offline_course_schedule

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale

class TaskDeadlineWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = updateAll(context)
    override fun onDisabled(context: Context) = updateAll(context)
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_REFRESH, Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_DATE_CHANGED -> updateAll(context)
        }
    }

    companion object {
        const val TASKS_KEY = "tasks"
        private const val ACTION_REFRESH = "com.offlinecourse.offline_course_schedule.REFRESH_TASK_WIDGET"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TaskDeadlineWidget::class.java))
            val raw = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.task_widget_tasks", null)
                ?: context.getSharedPreferences(NextCourseWidget.PREFS_NAME, Context.MODE_PRIVATE)
                    .getString(TASKS_KEY, "[]") ?: "[]"
            val array = runCatching { JSONArray(raw) }.getOrElse { JSONArray() }
            val tasks = (0 until array.length()).map { array.getJSONObject(it) }.sortedBy { it.getLong("dueMillis") }
            val now = System.currentTimeMillis()
            val next = tasks.firstOrNull { it.getLong("dueMillis") > now }
            val overdue = tasks.count { it.getLong("dueMillis") <= now }
            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.next_course_widget)
                views.setTextViewText(R.id.widget_label, "作业倒计时 · ${tasks.size} 项待完成")
                views.setTextViewText(R.id.widget_course_name, next?.getString("title") ?: "暂无待截止作业")
                views.setTextViewText(R.id.widget_course_teacher, next?.getString("course") ?: "打开 App 查看全部作业")
                views.setTextViewText(R.id.widget_course_location, "已逾期 $overdue 项 · 点击查看作业")
                views.setTextViewText(R.id.widget_course_time, next?.let {
                    "截止：" + SimpleDateFormat("M月d日 HH:mm", Locale.CHINA).format(java.util.Date(it.getLong("dueMillis")))
                } ?: if (overdue > 0) "有 $overdue 项作业已逾期" else "没有未完成的截止任务")
                views.setViewVisibility(R.id.widget_countdown_precise, View.GONE)
                views.setTextViewText(R.id.widget_countdown, next?.let {
                    TaskCountdown.text(it.getLong("dueMillis") - now)
                } ?: "已逾期 $overdue 项")
                views.setInt(R.id.widget_root, "setBackgroundResource",
                    if (next != null && next.getLong("dueMillis") - now <= 86400000) R.drawable.widget_background_urgent
                    else R.drawable.widget_background)
                val open = Intent(context, MainActivity::class.java)
                    .putExtra("open_tasks", true).putExtra("task_id", next?.getString("id") ?: "")
                    .setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 3001 + id,
                    open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                manager.updateAppWidget(id, views)
            }
            schedule(context, ids.isNotEmpty(), next, now)
        }

        private fun schedule(context: Context, hasWidgets: Boolean, next: JSONObject?, now: Long) {
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val operation = PendingIntent.getBroadcast(context, 3002,
                Intent(context, TaskDeadlineWidget::class.java).setAction(ACTION_REFRESH),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            if (!hasWidgets || next == null) { alarm.cancel(operation); return }
            val step = if (next.getLong("dueMillis") - now <= 86400000) 60000 else 300000
            val trigger = minOf((now / step + 1) * step, next.getLong("dueMillis"))
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarm.canScheduleExactAlarms()) {
                alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, operation)
            } else { alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, operation) }
        }
    }
}
