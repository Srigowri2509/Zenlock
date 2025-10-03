package com.example.zenlock

import android.content.Context
import android.content.SharedPreferences

object RulesBridge {

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /** Deadline (epoch ms) for this package, or 0 if none */
    private fun deadlineMs(ctx: Context, pkg: String): Long {
        // Flutter SharedPreferences keys are prefixed with "flutter."
        val key = "flutter.lock_$pkg"
        val raw = prefs(ctx).getString(key, null) ?: return 0L
        return raw.toLongOrNull() ?: 0L
    }

    /** Milliseconds remaining for the lock; 0 if unlocked/expired */
    @JvmStatic
    fun remainingMs(ctx: Context, pkg: String): Long {
        val deadline = deadlineMs(ctx, pkg)
        if (deadline <= 0L) return 0L
        val now = System.currentTimeMillis()
        val left = deadline - now
        return if (left > 0L) left else 0L
    }

    /** True if the app is currently locked */
    @JvmStatic
    fun isLocked(ctx: Context, pkg: String): Boolean = remainingMs(ctx, pkg) > 0L
}
