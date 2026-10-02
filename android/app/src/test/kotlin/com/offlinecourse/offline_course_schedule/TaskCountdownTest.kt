package com.offlinecourse.offline_course_schedule

import org.junit.Assert.*
import org.junit.Test

class TaskCountdownTest {
    @Test fun countdownBoundaries() {
        assertEquals("已截止", TaskCountdown.text(-1))
        assertEquals("剩余不到1分钟", TaskCountdown.text(59999))
        assertEquals("剩余 1小时 5分钟", TaskCountdown.text(65 * 60000L))
        assertEquals("剩余 2天 3小时", TaskCountdown.text(51 * 3600000L))
    }
}
