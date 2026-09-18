package com.offlinecourse.offline_course_schedule

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
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
        // 除了自己排的刷新闹钟，系统级事件也要重算并重排：
        // 重启、应用更新、用户改时间/时区/日期都会让原来的闹钟失效或文案过期。
        when (intent.action) {
            ACTION_REFRESH,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            -> updateAll(context)
        }    }

    companion object {
        const val PREFS_NAME = "next_course_widget"
        const val COURSES_KEY = "courses"

        // 小组件自己的背景色（ARGB int）。SharedPreferences 没有 putInt 的 null 语义，
        // 所以“未自定义”用“键不存在”表示，而不是哨兵值。
        const val COLOR_KEY = "widget_color"

        // 倒计时刷新频率：省电 / 正常 / 精确（见 Dart 侧 WidgetRefreshMode）。
        const val REFRESH_MODE_KEY = "widget_refresh_mode"

        private const val MODE_NORMAL = "normal"
        private const val MODE_PRECISE = "precise"

        private const val ACTION_REFRESH =
            "com.offlinecourse.offline_course_schedule.REFRESH_WIDGET"

        // 底色亮度低于该值时改用浅色文字。Color.luminance 就是 WCAG 相对亮度，
        // 阈值取自深浅两套文字各自等对比度交点（约 0.22 ~ 0.34）里偏保守的位置。
        private const val DARK_BACKGROUND_LUMINANCE = 0.22f

        // 浅色底上的文字色，与 layout XML 里写死的值一致。
        private val TEXT_DARK_LABEL = 0xFF667085.toInt()
        private val TEXT_DARK_NAME = 0xFF1D2939.toInt()
        private val TEXT_DARK_TIME = 0xFF344054.toInt()
        private val TEXT_DARK_COUNTDOWN = 0xFFB54708.toInt()
        private val TEXT_DARK_TEACHER = 0xFF475467.toInt()
        private val TEXT_DARK_LOCATION = 0xFF667085.toInt()

        // 深色底上的浅色阶梯：主标题最亮、次要信息渐淡，保留原来的层次感。
        private val TEXT_LIGHT_LABEL = 0xFFD0D5DD.toInt()
        private val TEXT_LIGHT_NAME = 0xFFFFFFFF.toInt()
        private val TEXT_LIGHT_TIME = 0xFFE4E7EC.toInt()
        private val TEXT_LIGHT_COUNTDOWN = 0xFFFDB022.toInt()
        private val TEXT_LIGHT_TEACHER = 0xFFD0D5DD.toInt()
        private val TEXT_LIGHT_LOCATION = 0xFF98A2B3.toInt()

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
            val customColor = readCustomColor(context)
            val views = RemoteViews(context.packageName, R.layout.next_course_widget)
            if (item == null) {
                // 没有后续课程时用的就是普通档，同样套自定义色，
                // 否则一没课就变回默认色，观感会割裂。
                applyWidgetColors(views, R.drawable.widget_background, customColor)
                // 桌面会复用同一个 View，标签要显式写回，否则会残留上一次的“下一项安排”。
                views.setTextViewText(R.id.widget_label, "下一节课")
                views.setTextViewText(R.id.widget_course_name, "暂无后续课程")
                views.setTextViewText(R.id.widget_course_time, "打开 App 检查课表")
                views.setTextViewText(R.id.widget_course_location, "")
                views.setTextViewText(R.id.widget_course_teacher, "")
                views.setViewVisibility(R.id.widget_countdown, View.GONE)
                views.setViewVisibility(R.id.widget_countdown_precise, View.GONE)
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
                // 备忘录不是“课”，文案要说“事件开始”，标签也不能写“下一节课”。
                val isMemo = item.optBoolean("isMemo", false)
                views.setTextViewText(
                    R.id.widget_label,
                    if (isMemo) "下一项安排" else "下一节课",
                )
                views.setTextViewText(R.id.widget_course_name, item.getString("name"))
                views.setTextViewText(R.id.widget_course_time, "$prefix ${item.getString("time")}")
                val countdownPrefix = if (isMemo) "距离事件开始" else "距离上课"
                val precise = context
                    .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .getString(REFRESH_MODE_KEY, null) == MODE_PRECISE
                if (precise && remaining > 0L) {
                    // 精确模式用 Chronometer 显示到秒。
                    // 不能靠“每秒排一次闹钟”来实现：AlarmManager 的精确闹钟受系统限流
                    // （约每分钟才会派发一次，低电耗模式下更久），秒数会停在旧值反而误导。
                    // Chronometer 由桌面进程自行每秒走动，不依赖应用被唤醒。
                    views.setViewVisibility(R.id.widget_countdown, View.GONE)
                    views.setViewVisibility(R.id.widget_countdown_precise, View.VISIBLE)
                    views.setChronometer(
                        R.id.widget_countdown_precise,
                        SystemClock.elapsedRealtime() + remaining,
                        "$countdownPrefix %s",
                        true,
                    )
                    views.setChronometerCountDown(R.id.widget_countdown_precise, true)
                } else {
                    // 省电/正常模式按分钟显示：刷新间隔就是分钟级，显示秒数会停在旧值。
                    // 到点（remaining <= 0）也走这里，兜底显示“即将开始”而绝不出现负值。
                    views.setViewVisibility(R.id.widget_countdown, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_countdown_precise, View.GONE)
                    val minutes = (remaining + 59_999L) / 60_000L // 向上取整，避免过早显示 0 分钟
                    val countdown = when {
                        remaining <= 0L -> "即将开始"
                        remaining < 60_000L -> "即将开始"
                        remaining < 60 * 60_000L -> "$countdownPrefix $minutes 分钟"
                        else -> {
                            val hours = remaining / 3_600_000L
                            val restMinutes = remaining % 3_600_000L / 60_000L // 小时口径下分钟向下取整
                            if (restMinutes == 0L) {
                                "$countdownPrefix $hours 小时"
                            } else {
                                "$countdownPrefix $hours 小时 $restMinutes 分钟"
                            }
                        }
                    }
                    views.setTextViewText(R.id.widget_countdown, countdown)
                }
                // 备忘录没有教师，这一行留空而不是写“教师未填写”。
                val teacher = item.optString("teacher")
                views.setViewVisibility(
                    R.id.widget_course_teacher,
                    if (teacher.isBlank()) View.GONE else View.VISIBLE,
                )
                views.setTextViewText(
                    R.id.widget_course_teacher,
                    teacher.ifBlank { "教师未填写" },
                )
                views.setTextViewText(
                    R.id.widget_course_location,
                    // 备忘录的地点本来就可以不填，不必提示“地点未填写”。
                    if (isMemo) {
                        item.optString("location")
                    } else {
                        item.optString("location").ifBlank { "地点未填写" }
                    },
                )
                // 阈值维持原来的 30 分钟 / 120 分钟两档不变。
                val background = when {
                    remaining <= 30 * 60_000L -> R.drawable.widget_background_urgent
                    remaining <= 120 * 60_000L -> R.drawable.widget_background_soon
                    else -> R.drawable.widget_background
                }
                applyWidgetColors(views, background, customColor)
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

        /// 读取小组件自己的背景色；键不存在表示未自定义，返回 null。
        private fun readCustomColor(context: Context): Int? {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (!prefs.contains(COLOR_KEY)) return null
            return prefs.getInt(COLOR_KEY, 0)
        }

        /// 应用背景与文字颜色。
        ///
        /// [background] 是当前这一档（普通 / 紧迫）原本就该用的 drawable。
        /// 自定义色只替换普通档：`widget_background_soon`（≤120min）与
        /// `widget_background_urgent`（≤30min）保持原样，紧迫度提示不丢。
        ///
        /// 普通档不能直接 setBackgroundColor——那会丢掉圆角。改为“纯白底 drawable +
        /// backgroundTintList”，结果色精确等于自定义色且保留 22dp 圆角。
        /// 注意 `RemoteViews.setColorStateList` 是 API 31 才有的：低版本退回默认外观，
        /// 不为任意取色牺牲圆角。
        private fun applyWidgetColors(
            views: RemoteViews,
            background: Int,
            customColor: Int?,
        ) {
            val normalTier = background == R.drawable.widget_background
            val tintColor =
                if (normalTier && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    customColor
                } else {
                    null
                }
            if (tintColor != null) {
                views.setInt(
                    R.id.widget_root,
                    "setBackgroundResource",
                    R.drawable.widget_background_custom,
                )
                views.setColorStateList(
                    R.id.widget_root,
                    "setBackgroundTintList",
                    ColorStateList.valueOf(tintColor),
                )
                applyTextColors(views, light = isDarkBackground(tintColor))
            } else {
                views.setInt(R.id.widget_root, "setBackgroundResource", background)
                // View.setBackgroundResource 会重新套用之前存下的 backgroundTint，
                // 不显式清掉的话，换回默认/紧迫档时旧颜色会残留上去。
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    views.setColorStateList(
                        R.id.widget_root,
                        "setBackgroundTintList",
                        null as ColorStateList?,
                    )
                }
                // 桌面会复用同一个 View，不显式写文字色会残留上一次的配色。
                applyTextColors(views, light = false)
            }
        }

        /// 按底色亮暗选择整套文字配色：[light] 为 true 时用浅色阶梯。
        private fun applyTextColors(views: RemoteViews, light: Boolean) {
            views.setTextColor(
                R.id.widget_label,
                if (light) TEXT_LIGHT_LABEL else TEXT_DARK_LABEL,
            )
            views.setTextColor(
                R.id.widget_course_name,
                if (light) TEXT_LIGHT_NAME else TEXT_DARK_NAME,
            )
            views.setTextColor(
                R.id.widget_course_time,
                if (light) TEXT_LIGHT_TIME else TEXT_DARK_TIME,
            )
            views.setTextColor(
                R.id.widget_countdown,
                if (light) TEXT_LIGHT_COUNTDOWN else TEXT_DARK_COUNTDOWN,
            )
            views.setTextColor(
                R.id.widget_countdown_precise,
                if (light) TEXT_LIGHT_COUNTDOWN else TEXT_DARK_COUNTDOWN,
            )
            views.setTextColor(
                R.id.widget_course_teacher,
                if (light) TEXT_LIGHT_TEACHER else TEXT_DARK_TEACHER,
            )
            views.setTextColor(
                R.id.widget_course_location,
                if (light) TEXT_LIGHT_LOCATION else TEXT_DARK_LOCATION,
            )
        }

        private fun isDarkBackground(color: Int): Boolean {
            return Color.luminance(color) < DARK_BACKGROUND_LUMINANCE
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
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NextCourseWidget::class.java)
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val operation = PendingIntent.getBroadcast(
                context,
                2002,
                Intent(context, NextCourseWidget::class.java).setAction(ACTION_REFRESH),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            // 桌面上没有小组件时不必空转闹钟。
            if (manager.getAppWidgetIds(component).isEmpty()) {
                alarmManager.cancel(operation)
                return
            }
            val item = nextItem(context)
            val now = System.currentTimeMillis()
            val mode = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(REFRESH_MODE_KEY, null)
            val triggerAt = if (item == null) {
                // 当前没有后续安排（例如当天课已上完）。也要在次日零点重算一次，
                // 否则小组件会一直停在“暂无后续课程”，直到用户自己打开 App。
                nextDayStart(now)
            } else {
                val start = item.getLong("startMillis")
                val remaining = start - now
                // 倒计时文案带分钟（精确模式带秒），必须按对应频率重算，
                // 否则数字会长时间停在旧值——这正是“只有点了才刷新”的原因。
                // 注意：精确模式的秒数由 Chronometer 在桌面进程里自行走动，
                // 不靠闹钟。AlarmManager 的精确闹钟受系统限流（约每分钟才会派发一次，
                // 低电耗模式下更久），排每秒既拿不到回调又白耗电。
                // 因此这里只需按分钟重算，用于切换背景档位与「到点切下一节」。
                val step = when (mode) {
                    // 精确：秒数交给 Chronometer，闹钟仍按分钟。
                    MODE_PRECISE -> 60_000L
                    // 正常：始终每分钟刷新，简单可预期。
                    MODE_NORMAL -> 60_000L
                    // 省电（默认）：临近上课每分钟，更远时 5 分钟。
                    else -> if (remaining <= 2 * 60 * 60_000L) 60_000L else 5 * 60_000L
                }
                // 对齐到下一个整刻度，避免闹钟轻微提前导致白刷一次；
                // 上课时刻本身必须刷，那时 nextItem 会跳过已开始的课，切到下一节。
                minOf((now / step + 1) * step, start)
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            }
        }

        /// 次日零点的时间戳，用于没有后续安排时的兜底重算。
        private fun nextDayStart(now: Long): Long {
            val calendar = java.util.Calendar.getInstance()
            calendar.timeInMillis = now
            calendar.add(java.util.Calendar.DAY_OF_YEAR, 1)
            calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
            calendar.set(java.util.Calendar.MINUTE, 0)
            calendar.set(java.util.Calendar.SECOND, 0)
            calendar.set(java.util.Calendar.MILLISECOND, 0)
            return calendar.timeInMillis
        }
    }
}
