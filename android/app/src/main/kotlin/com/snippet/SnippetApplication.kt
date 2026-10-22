package com.snippet

import android.app.Application
import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SnippetApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val log = File(filesDir, "diagnostics.txt")
        recordLastExits(log)
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                log.appendText("${stamp()} CRASH in ${thread.name}\n${error.stackTraceToString()}\n")
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, error)
        }
    }

    private fun recordLastExits(log: File) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val seen = File(filesDir, "diagnostics_exit_seen.txt")
            val last = seen.takeIf { it.exists() }?.readText()?.trim()?.toLongOrNull() ?: 0L
            var newest = last
            for (info in manager.getHistoricalProcessExitReasons(packageName, 0, 6)) {
                if (info.timestamp <= last) continue
                if (info.timestamp > newest) newest = info.timestamp
                val reason = when (info.reason) {
                    ApplicationExitInfo.REASON_CRASH -> "CRASH"
                    ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
                    ApplicationExitInfo.REASON_ANR -> "ANR"
                    ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
                    ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
                    ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
                    ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
                    else -> "reason ${info.reason}"
                }
                log.appendText("${stamp(info.timestamp)} EXIT $reason ${info.processName} ${info.description ?: ""}\n")
            }
            seen.writeText(newest.toString())
        } catch (_: Throwable) {
        }
    }

    private fun stamp(at: Long = System.currentTimeMillis()): String =
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(at))
}
