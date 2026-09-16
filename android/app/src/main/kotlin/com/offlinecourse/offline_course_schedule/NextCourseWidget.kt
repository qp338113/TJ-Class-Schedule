package com.offlinecourse.offline_course_schedule

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

class NextCourseWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
        scheduleNextRefresh(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) updateAll(context)
    }

    companion object {
        const val PREFS_NAME = "next_course_widget"
        const val COURSES_KEY = "courses"
        private const val ACTION_REFRESH =
            "com.offlinecourse.offline_course_schedule.REFRESH_WIDGET"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NextCourseWidget::class.java)
            val ids = manager.getAppWidgetIds(component)
            ids.forEach { updateWidget(context, manager, it) }
            scheduleNextRefresh(context)
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val item = nextItem(context)
            val views = RemoteViews(context.packageName, R.layout.next_course_widget)
            if (item == null) {
                views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.widget_background)
                views.setTextViewText(R.id.widget_course_name, "暂无后续课程")
                views.setTextViewText(R.id.widget_course_time, "打开 App 检查课表")
                views.setTextViewText(R.id.widget_course_location, "")
                views.setTextViewText(R.id.widget_course_teacher, "")
                views.setViewVisibility(R.id.widget_countdown, View.GONE)
            } else {
                val start = item.getLong("startMillis")
                val remaining = start - System.currentTimeMillis()
                val now = java.util.Calendar.getInstance()
                val courseTime = java.util.Calendar.getInstance().apply { timeInMillis = start }
                val sameDay = now.get(java.util.Calendar.YEAR) == courseTime.get(java.util.Calendar.YEAR) &&
                    now.get(java.util.Calendar.DAY_OF_YEAR) == courseTime.get(java.util.Calendar.DAY_OF_YEAR)
                val prefix = if (sameDay) {
                    "今天"
                } else {
                    "${item.getInt("month")}月${item.getInt("day")}日 ${item.getString("weekday")}" 
                }
                views.setTextViewText(R.id.widget_course_name, item.getString("name"))
                views.setTextViewText(R.id.widget_course_time, "$prefix ${item.getString("time")}")
                views.setViewVisibility(R.id.widget_countdown, View.VISIBLE)
                views.setChronometer(
                    R.id.widget_countdown,
                    SystemClock.elapsedRealtime() + remaining,
                    "距离上课 %s",
                    true,
                )
                views.setChronometerCountDown(R.id.widget_countdown, true)
                views.setTextViewText(
                    R.id.widget_course_teacher,
                    item.optString("teacher").ifBlank { "教师未填写" },
                )
                views.setTextViewText(
                    R.id.widget_course_location,
                    item.optString("location").ifBlank { "地点未填写" },
                )
                val background = when {
                    remaining <= 30 * 60_000L -> R.drawable.widget_background_urgent
                    remaining <= 120 * 60_000L -> R.drawable.widget_background_soon
                    else -> R.drawable.widget_background
                }
                views.setInt(R.id.widget_root, "setBackgroundResource", background)
            }
            val openApp = PendingIntent.getActivity(
                context,
                2001,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, openApp)
            manager.updateAppWidget(widgetId, views)
        }

        private fun nextItem(context: Context): org.json.JSONObject? {
            val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(COURSES_KEY, "[]") ?: "[]"
            val courses = runCatching { JSONArray(raw) }.getOrElse { JSONArray() }
            val now = System.currentTimeMillis()
            for (index in 0 until courses.length()) {
                val item = courses.getJSONObject(index)
                if (item.optLong("startMillis") > now) return item
            }
            return null
        }

        private fun scheduleNextRefresh(context: Context) {
            val item = nextItem(context)
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val operation = PendingIntent.getBroadcast(
                context,
                2002,
                Intent(context, NextCourseWidget::class.java).setAction(ACTION_REFRESH),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            if (item == null) {
                alarmManager.cancel(operation)
                return
            }
            val start = item.getLong("startMillis")
            val now = System.currentTimeMillis()
            val triggerAt = listOf(
                start - 120 * 60_000L,
                start - 30 * 60_000L,
                start + 1_000L,
            ).filter { it > now }.minOrNull() ?: start + 1_000L
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            }
        }
    }
}
