package com.studypeaks.app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.studypeaks.app/lock_task"
    private var methodChannel: MethodChannel? = null
    private var wasInLockTaskMode = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startLockTask" -> {
                    try {
                        startLockTask()
                        wasInLockTaskMode = true
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_TASK_ERROR", e.message, null)
                    }
                }
                "stopLockTask" -> {
                    try {
                        stopLockTask()
                        wasInLockTaskMode = false
                        result.success(true)
                    } catch (e: Exception) {
                        // Silently succeed if not in lock task mode
                        result.success(false)
                    }
                }
                "isInLockTaskMode" -> {
                    result.success(isInLockTaskModeCompat())
                }
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

    private fun isInLockTaskModeCompat(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            @Suppress("DEPRECATION")
            am.isInLockTaskMode
        }
    }

    override fun onResume() {
        super.onResume()
        // Detect if user manually exited lock task mode
        if (wasInLockTaskMode && !isInLockTaskModeCompat()) {
            wasInLockTaskMode = false
            methodChannel?.invokeMethod("onLockTaskModeExited", null)
        }
    }

    override fun onDestroy() {
        // Safety: release lock task if activity is destroyed
        try {
            if (isInLockTaskModeCompat()) {
                stopLockTask()
            }
        } catch (_: Exception) {
            // Ignore errors during cleanup
        }
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.onDestroy()
    }
}
