package com.operon.browser

import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * The one link from the foreground service back to Dart.
 *
 * The service outlives the activity in some paths (a notification action can
 * arrive while the Flutter UI is stopped), so it cannot hold the activity. The
 * channel is registered by [MainActivity] and cleared when the engine goes
 * away; a tap on a dead channel is dropped instead of crashing the service.
 */
object AgentBridge {
    private const val TAG = "AgentBridge"

    private var channel: MethodChannel? = null

    fun attach(active: MethodChannel) {
        channel = active
    }

    fun detach(active: MethodChannel) {
        if (channel === active) channel = null
    }

    /** Sends `pause`, `resume` or `stop` to the running run, if one is listening. */
    fun emitAction(action: String): Boolean {
        val active = channel ?: return false
        return try {
            active.invokeMethod("onTaskAction", action)
            true
        } catch (error: Exception) {
            // The engine can be torn down between the tap and this call.
            Log.w(TAG, "action $action not delivered: ${error.message}")
            false
        }
    }
}
