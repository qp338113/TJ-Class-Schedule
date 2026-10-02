package com.offlinecourse.offline_course_schedule

object TaskCountdown {
    fun text(remaining: Long): String {
        if (remaining <= 0) return "已截止"
        val minutes = remaining / 60000
        return when {
            minutes == 0L -> "剩余不到1分钟"
            minutes >= 1440 -> "剩余 ${minutes / 1440}天 ${minutes % 1440 / 60}小时"
            minutes >= 60 -> "剩余 ${minutes / 60}小时 ${minutes % 60}分钟"
            else -> "剩余 $minutes 分钟"
        }
    }
}
