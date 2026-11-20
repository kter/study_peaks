package com.studypeaks.app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.studypeaks.app/lock_task"
    private var methodChannel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())
    private var pendingPin: MethodChannel.Result? = null
    private var promptShown = false
    private var focusReturnedAt: Long? = null
    private var promptDeadline = 0L
    private var pinned = false

    private val monitorPinning = object : Runnable {
        override fun run() {
            val active = isInLockTaskModeCompat()
            val pending = pendingPin
            if (pending != null) {
                val now = SystemClock.elapsedRealtime()
                val dismissed = hasWindowFocus() &&
                    focusReturnedAt?.let { now - it >= 500 } == true
                val noPrompt = !promptShown && now >= promptDeadline
                if (active || dismissed || noPrompt) {
                    pendingPin = null
                    pinned = active
                    pending.success(active)
                }
            } else if (pinned && !active) {
                pinned = false
                methodChannel?.invokeMethod("onLockTaskModeExited", null)
            }
            if (pendingPin != null || pinned) handler.postDelayed(this, 250)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startLockTask" -> requestPin(result)
                "stopLockTask" -> result.success(releasePin())
                "isInLockTaskMode" -> result.success(isInLockTaskModeCompat())
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    runOnUiThread {
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestPin(result: MethodChannel.Result) {
        if (pendingPin != null) {
            result.success(false)
            return
        }
        pendingPin = result
        promptShown = false
        focusReturnedAt = null
        promptDeadline = SystemClock.elapsedRealtime() + 5_000L
        try {
            startLockTask()
            handler.removeCallbacks(monitorPinning)
            handler.post(monitorPinning)
        } catch (error: Exception) {
            pendingPin = null
            result.error("LOCK_TASK_ERROR", error.message, null)
        }
    }

    private fun releasePin(): Boolean {
        pendingPin?.success(false)
        pendingPin = null
        pinned = false
        handler.removeCallbacks(monitorPinning)
        if (!isInLockTaskModeCompat()) return false
        return try {
            stopLockTask()
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (pendingPin != null) {
            if (!hasFocus) promptShown = true
            focusReturnedAt = if (hasFocus && promptShown) SystemClock.elapsedRealtime() else null
        }
    }

    private fun isInLockTaskModeCompat(): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            manager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            @Suppress("DEPRECATION")
            manager.isInLockTaskMode
        }
    }

    override fun onDestroy() {
        releasePin()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.onDestroy()
    }
}
