package com.operon.browser

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Keeps a running agent task protected while Operon is not the app on screen.
 *
 * Android is free to reclaim a backgrounded process, and reclaiming it would
 * drop the DevTools socket, the page state and any confirmation the user still
 * owes the agent. A foreground service is the supported way to say "this is
 * still work the user asked for".
 *
 * The notification is also the control surface: pause/resume while the task is
 * still working, and stop at any time. Both actions go back to Dart through
 * [AgentBridge], because the run itself lives there; this service deliberately
 * owns no task state that could drift from the loop.
 */
class AgentForegroundService : Service() {
    private var paused = false
    private var canPause = true
    private var title = DEFAULT_TITLE
    private var body = DEFAULT_BODY

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // The system can recreate a service without the intent that started
        // it; there is no task to show in that case.
        val command = intent ?: run {
            stopSelf()
            return START_NOT_STICKY
        }
        when (command.action) {
            ACTION_START, ACTION_UPDATE -> {
                title = command.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() }
                    ?: title
                body = command.getStringExtra(EXTRA_BODY)?.takeIf { it.isNotBlank() }
                    ?: body
                paused = command.getBooleanExtra(EXTRA_PAUSED, paused)
                canPause = command.getBooleanExtra(EXTRA_CAN_PAUSE, canPause)
                postNotification()
            }

            ACTION_TOGGLE -> {
                // A paused task must still be resumable; a blocked one (waiting
                // for a person) has nothing to pause.
                if (!canPause) return START_NOT_STICKY
                paused = !paused
                if (!AgentBridge.emitAction(if (paused) "pause" else "resume")) {
                    // No Dart side to act on it: the run is gone, and a control
                    // that does nothing is worse than no control.
                    stopSelf()
                    return START_NOT_STICKY
                }
                postNotification()
            }

            ACTION_STOP -> {
                AgentBridge.emitAction("stop")
                stopSelf()
            }

            // The system recreated the service without a task to show.
            else -> stopSelf()
        }
        // A task is not replayed after the process dies: the page it drove is
        // gone too, and resuming a run against a blank WebView is unsafe.
        return START_NOT_STICKY
    }

    private fun postNotification() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: Exception) {
            // A revoked notification permission or a platform refusal must not
            // take the app down. The task keeps running; only its notification
            // is missing, and a service without one must not stay around.
            Log.w(TAG, "cannot post task notification: ${error.message}")
            stopSelf()
        }
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_operon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            // Task detail can include a page title or a form field; the lock
            // screen should not be the place that leaks it.
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)

        if (canPause) {
            builder.addAction(
                0,
                if (paused) "继续" else "暂停",
                servicePendingIntent(ACTION_TOGGLE, 1),
            )
        }
        builder.addAction(0, "停止", servicePendingIntent(ACTION_STOP, 2))
        return builder.build()
    }

    private fun servicePendingIntent(action: String, requestCode: Int): PendingIntent {
        return PendingIntent.getService(
            this,
            requestCode,
            Intent(this, AgentForegroundService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Operon 后台任务",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "任务运行时显示进度，并提供暂停与停止"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        manager.createNotificationChannel(channel)
    }

    /**
     * Swiping the app away is a stop request. Keeping the service alive would
     * leave a notification for a task whose activity and WebView are gone.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        AgentBridge.emitAction("stop")
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "com.operon.browser.agent.START"
        const val ACTION_UPDATE = "com.operon.browser.agent.UPDATE"
        const val ACTION_TOGGLE = "com.operon.browser.agent.TOGGLE"
        const val ACTION_STOP = "com.operon.browser.agent.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_PAUSED = "paused"
        const val EXTRA_CAN_PAUSE = "canPause"

        private const val TAG = "AgentForegroundService"
        private const val CHANNEL_ID = "operon_agent_running"
        private const val NOTIFICATION_ID = 2001
        private const val DEFAULT_TITLE = "Operon 正在执行"
        private const val DEFAULT_BODY = "智能体正在操作页面"
    }
}
